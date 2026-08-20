#!/usr/bin/env python3
"""DevTrail — 볼트 진단기. 쓰기는 하지 않는다.

6개 축을 재고 JSON 하나로 낸다. 사람이 읽는 형태는 scancmd.sh 가 만든다.

설계 원칙:
  - 폴더 '이름'으로 역할을 판단하지 않는다. 사람마다 Daily · 일지 · journal 로
    다르게 부른다. 내용의 형태(날짜 파일명 비율 · 최근성 · 하위구조)로 추론하고
    확신도를 함께 낸다. 확정은 사람이 한다.
  - 필드가 '있는 것'과 '값까지 있는 것'을 반드시 구분한다. 원본 볼트에서
    review_at 은 키가 13.8% 있었지만 값이 있는 건 0.3%(6개) 였다. 이 둘을 합치면
    커버리지를 40배 과대평가하고, 그 위에서 만든 쿼리는 조용히 빈 결과를 낸다.
"""

import json
import os
import re
import sys
from collections import Counter

SKIP_DIRS = {".obsidian", ".trash", ".smart-env", ".claudian", ".copilot-index",
             ".git", ".DS_Store", "node_modules"}

DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
WEEK_RE = re.compile(r"\d{4}-?W\d{2}", re.I)
TAG_RE = re.compile(r"(?<![\w/#])#([A-Za-z가-힣][\w가-힣/-]*)")

# 커버리지를 재는 필드. 허브 쿼리가 이것들에 의존한다.
TRACKED_FIELDS = ["type", "status", "tags", "created", "updated", "project",
                  "review_at", "category", "scope"]


def walk_md(vault):
    """볼트의 마크다운 파일을 (절대경로, 볼트기준 상대경로)로 낸다."""
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for name in files:
            if name.endswith(".md"):
                full = os.path.join(root, name)
                yield full, os.path.relpath(full, vault)


def read_frontmatter(path, max_bytes=8192):
    """frontmatter 블록만 읽는다. 본문은 읽지 않는다 — 개인 내용을 열지 않기 위해서다.

    반환: {키: 값} — 값은 문자열이거나 리스트다. 값이 빈 키도 남긴다.

    ⚠️ YAML 다중행 리스트를 반드시 처리해야 한다:
           tags:
             - type/devlog
       한 줄짜리 `키: 값`만 보면 tags 를 '값 없음'으로 오판한다.
       실제로 그렇게 만들었다가 태그 집계가 실제의 1% 로 나왔다.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            head = fh.read(max_bytes)
    except OSError:
        return None

    if not head.startswith("---"):
        return None
    end = head.find("\n---", 3)
    if end == -1:
        return None

    fields = {}
    current = None
    for line in head[3:end].split("\n"):
        item = re.match(r"^\s+-\s*(.*)$", line)
        if item and current:
            v = item.group(1).strip().strip("\"'")
            if v:
                # `tags:` 는 앞줄에서 빈 문자열로 들어가 있다.
                # setdefault 는 이미 있는 키를 건드리지 않으므로 리스트로 교체해야 한다.
                if not isinstance(fields.get(current), list):
                    fields[current] = []
                fields[current].append(v)
            continue
        m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            current = key
            if val.startswith("[") and val.endswith("]"):
                # 인라인 배열: tags: [a, b]
                fields[key] = [x.strip().strip("\"'") for x in val[1:-1].split(",") if x.strip()]
            else:
                fields[key] = val
    return fields


def field_has_value(v):
    """값이 실제로 들어 있는가. 빈 키와 구분하는 판정 한 곳."""
    if isinstance(v, list):
        return len(v) > 0
    return bool(v) and v not in ("[]", "{}", '""', "''", "null", "~", "-")


def extract_tags(fields):
    """frontmatter 에서 태그를 뽑는다. 리스트·인라인·문자열 전부 처리한다."""
    raw = fields.get("tags")
    out = []
    if isinstance(raw, list):
        out = [t.lstrip("#") for t in raw if t]
    elif isinstance(raw, str) and raw:
        out = [t.lstrip("#") for t in re.split(r"[,\s]+", raw) if t]
    return [t for t in out if t]


# 역할 후보에서 빼는 경로. 자동 수집물·백업은 원본 폴더를 흉내내서
# 그대로 두면 진짜 역할 폴더를 밀어낸다 (실제로 레포docs 하위 30여 개가
# devlog 후보 상위를 점령했다).
NOISE_RE = re.compile(r"(archive|아카이브|backup|백업|_staging|/_|template|템플릿)", re.I)
MAX_ROLE_DEPTH = 3
RECENT_DAYS = 90


def analyse_folders(vault, files_by_dir, now=0):
    """폴더별 신호를 재고 역할 후보를 점수화한다."""
    out = []
    for rel_dir, entries in sorted(files_by_dir.items()):
        if not entries:
            continue
        names = [os.path.basename(p)[:-3] for p in entries]
        n = len(names)
        dated = sum(1 for x in names if DATE_RE.search(x))
        weekly = sum(1 for x in names if WEEK_RE.search(x))
        mtimes = []
        for p in entries:
            try:
                mtimes.append(os.path.getmtime(p))
            except OSError:
                pass
        sub = 0
        full_dir = os.path.join(vault, rel_dir) if rel_dir != "." else vault
        try:
            sub = sum(1 for e in os.scandir(full_dir)
                      if e.is_dir() and e.name not in SKIP_DIRS and not e.name.startswith("."))
        except OSError:
            pass

        last = int(max(mtimes)) if mtimes else 0
        depth = 0 if rel_dir == "." else rel_dir.count("/") + 1
        noisy = bool(NOISE_RE.search("/" + rel_dir))

        # 규모와 최근성으로 확신도를 깎는다. 노트 3개짜리 폴더가
        # 105개짜리 폴더를 이기면 안 된다.
        #
        # ⚠️ 바닥을 둔다. min(n/30,1) 만 쓰면 노트 8개짜리 폴더가 0.27 이 되어
        #    0.3 임계값에서 잘린다 — 이제 막 쓰기 시작한 사람의 일지 폴더가
        #    통째로 안 잡힌다. 순위를 가르는 데는 충분하고 바닥은 지킨다.
        scale = max(min(n / 30.0, 1.0), 0.45)
        recent = 1.0 if (now and last and (now - last) < RECENT_DAYS * 86400) else 0.55

        roles = {}
        eligible = depth <= MAX_ROLE_DEPTH and not noisy

        # 일지·주간은 '날짜 파일이 충분히 쌓인 폴더'다.
        if eligible and n >= 3:
            if dated / n >= 0.6:
                roles["devlog"] = round((dated / n) * scale * recent, 2)
            if weekly / n >= 0.5:
                roles["weekly"] = round((weekly / n) * scale * recent, 2)

        # 프로젝트 컨테이너는 반대다 — 직속 노트가 적은 게 정상이다.
        # n >= 3 안에 묶어뒀다가 README 하나뿐인 진짜 프로젝트 폴더를 놓쳤다.
        if eligible:
            if sub >= 2 and n <= sub:
                marked = 0
                try:
                    for e in os.scandir(full_dir):
                        if not e.is_dir() or e.name.startswith("."):
                            continue
                        if os.path.isdir(os.path.join(e.path, "docs")) or \
                           os.path.isfile(os.path.join(e.path, "README.md")):
                            marked += 1
                except OSError:
                    pass
                if marked >= 2:
                    roles["projects"] = round(min(marked / 3.0, 1.0) * recent, 2)

        out.append({
            "path": rel_dir,
            "notes": n,
            "subfolders": sub,
            "depth": depth,
            "dated_ratio": round(dated / n, 2) if n else 0,
            "last_modified": last,
            "role_candidates": roles,
        })

    # 역할별 상위 2개만 남긴다 — 사용자가 고를 수 있는 분량이어야 한다.
    best = {}
    for f in out:
        for role, sc in f["role_candidates"].items():
            best.setdefault(role, []).append((sc, f["path"]))
    keep = {role: {p for sc, p in sorted(v, reverse=True)[:2] if sc >= 0.3}
            for role, v in best.items()}
    for f in out:
        f["role_candidates"] = {r: sc for r, sc in f["role_candidates"].items()
                                if f["path"] in keep.get(r, ()) and sc >= 0.3}
    return out


REQUIRED_PLUGINS = ["obsidian-shellcommands", "templater-obsidian", "dataview", "auto-note-mover"]
RECOMMENDED_PLUGINS = ["calendar", "omnisearch", "obsidian-linter", "homepage"]
REQUIRED_CORE = ["daily-notes", "templates", "properties"]


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def dir_size(path):
    total = 0
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def analyse_obsidian(vault, wanted_keys, wanted_folders):
    """플러그인 준비도 · 충돌 · RAG 상태. .obsidian 이 없으면 신규 볼트다."""
    dot = os.path.join(vault, ".obsidian")
    if not os.path.isdir(dot):
        return {"present": False,
                "_note": "볼트를 Obsidian 에서 한 번도 열지 않았다"}

    community = load_json(os.path.join(dot, "community-plugins.json"), []) or []
    core = load_json(os.path.join(dot, "core-plugins.json"), {}) or {}
    hotkeys = load_json(os.path.join(dot, "hotkeys.json"), {}) or {}
    app = load_json(os.path.join(dot, "app.json"), {}) or {}

    anm = load_json(os.path.join(dot, "plugins/auto-note-mover/data.json"), {}) or {}
    tpl = load_json(os.path.join(dot, "plugins/templater-obsidian/data.json"), {}) or {}
    linter_path = os.path.join(dot, "plugins/obsidian-linter/data.json")

    # 단축키 점유: 우리가 쓰려는 조합이 이미 배정돼 있는가
    occupied = {}
    for cmd, binds in hotkeys.items():
        for b in binds or []:
            combo = "+".join(sorted(b.get("modifiers") or [])) + "+" + str(b.get("key", ""))
            occupied[combo] = cmd
    conflicts_hotkey = [{"combo": c, "taken_by": occupied[c]} for c in wanted_keys if c in occupied]

    # 폴더 이름 충돌: 우리가 만들 경로가 이미 존재하는가
    conflicts_folder = [f for f in wanted_folders
                        if os.path.isdir(os.path.join(vault, f))]

    smart_env = os.path.join(vault, ".smart-env")
    has_rag = "smart-connections" in community

    return {
        "present": True,
        "plugins": {
            "community_enabled": len(community),
            "required_missing": [p for p in REQUIRED_PLUGINS if p not in community],
            "recommended_missing": [p for p in RECOMMENDED_PLUGINS if p not in community],
            "core_missing": [p for p in REQUIRED_CORE if not core.get(p)],
            "zk_prefixer_on": bool(core.get("zk-prefixer")),
        },
        "conflicts": {
            "hotkeys": conflicts_hotkey,
            "folders": conflicts_folder,
            "auto_note_mover_rules": len(anm.get("folder_tag_pattern") or []),
            "auto_note_mover_trigger": anm.get("trigger_auto_manual"),
            "templater_folder_templates": len(tpl.get("folder_templates") or []),
            "linter_present": os.path.isfile(linter_path),
            "always_update_links": app.get("alwaysUpdateLinks"),
            "attachment_folder": app.get("attachmentFolderPath"),
        },
        "rag": {
            "smart_connections": has_rag,
            "index_bytes": dir_size(smart_env) if os.path.isdir(smart_env) else 0,
            "excluded_configured": bool(
                (load_json(os.path.join(smart_env, "smart_env.json"), {}) or {})
                .get("smart_sources", {}).get("folder_exclusions")),
        },
    }


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "볼트 경로가 필요합니다"}, ensure_ascii=False))
        return 2
    vault = os.path.abspath(sys.argv[1])
    if not os.path.isdir(vault):
        print(json.dumps({"error": f"볼트 경로 없음: {vault}"}, ensure_ascii=False))
        return 2

    tree = load_json(sys.argv[2]) if len(sys.argv) > 2 else None
    hk = load_json(sys.argv[3]) if len(sys.argv) > 3 else None

    wanted_folders = []
    if tree:
        for f in tree.get("folders", []):
            wanted_folders.append(f["path"])
            for c in f.get("children", []):
                wanted_folders.append(f["path"] + "/" + c["path"])
    wanted_keys = []
    if hk:
        for group in ("templater", "shellcommands", "plugin"):
            for b in hk.get(group, []):
                wanted_keys.append("+".join(sorted(b["modifiers"])) + "+" + b["key"])

    files_by_dir = {}
    total = 0
    fm_present = 0
    # 필드별로 '키가 있는 수'와 '값까지 있는 수'를 따로 센다.
    field_key = Counter()
    field_val = Counter()
    tag_counter = Counter()
    typed_notes = 0
    custom_fields = Counter()

    for full, rel in walk_md(vault):
        total += 1
        d = os.path.dirname(rel) or "."
        files_by_dir.setdefault(d, []).append(full)

        fields = read_frontmatter(full)
        if fields is None:
            continue
        fm_present += 1

        for k, v in fields.items():
            if k in TRACKED_FIELDS:
                field_key[k] += 1
                if field_has_value(v):
                    field_val[k] += 1
            else:
                custom_fields[k] += 1

        for t in extract_tags(fields):
            tag_counter[t] += 1
        if field_has_value(fields.get("type", "")):
            typed_notes += 1

    def pct(x):
        return round(x * 100 / total, 1) if total else 0.0

    type_tags = sum(c for t, c in tag_counter.items() if t.startswith("type/"))
    all_tags = sum(tag_counter.values())

    result = {
        "vault": vault,
        "scale": {
            "notes": total,
            "folders": len(files_by_dir),
            "frontmatter_notes": fm_present,
            "frontmatter_pct": pct(fm_present),
        },
        "fields": {
            k: {
                "with_key": field_key[k],
                "with_value": field_val[k],
                "key_pct": pct(field_key[k]),
                "value_pct": pct(field_val[k]),
            }
            for k in TRACKED_FIELDS
        },
        "custom_fields": custom_fields.most_common(10),
        "tags": {
            "total_uses": all_tags,
            "type_namespaced": type_tags,
            "type_pct": round(type_tags * 100 / all_tags, 1) if all_tags else 0.0,
            "top": tag_counter.most_common(20),
        },
        "folders": analyse_folders(vault, files_by_dir, now=int(__import__("time").time())),
        "obsidian": analyse_obsidian(vault, wanted_keys, wanted_folders),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
