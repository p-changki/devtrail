#!/usr/bin/env python3
"""DevTrail — 단축키 · Templater 폴더매핑 · daily-notes 생성기.

셋 다 '커맨드 ID나 경로 안에 볼트 경로가 들어간다'는 공통점이 있어 함께 둔다.

⚠️ 정적 hotkeys.json 을 복사하면 안 된다.
   Templater 커맨드 ID 안에 볼트 경로가 통째로 들어간다:
       templater-obsidian:create-<루트>/<템플릿폴더>/<파일>.md
   사용자가 루트를 다른 이름으로 정하면 템플릿 단축키가 전부 죽는다.
   설치는 성공했는데 단축키만 조용히 안 먹는, 실물 QA 에서 놓치기 쉬운 종류다.

⚠️ 이미 쓰이는 키는 빼앗지 않는다. fallback_keys 에서 빈 키를 찾아 재배정하고,
   그것도 없으면 그 단축키는 배정하지 않는다(기능은 명령 팔레트로 쓸 수 있다).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import LANG, t as T  # noqa: E402


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def combo(mods, key):
    return "+".join(sorted(mods)) + "+" + key


def build_hotkeys(spec, tmpl_rel, existing, shell_ids, have=None):
    """우리 단축키를 조립한다. 점유된 조합은 피한다."""
    occupied = {}
    for cmd, binds in (existing or {}).items():
        for b in binds or []:
            occupied[combo(b.get("modifiers") or [], str(b.get("key", "")))] = cmd

    out = dict(existing or {})
    pool = list(spec.get("fallback_keys") or [])
    assigned, skipped, remapped = [], [], []

    def place(cmd_id, mods, key):
        # 이미 우리가 배정한 커맨드면 그대로 둔다.
        # 이걸 안 하면 재실행할 때마다 '남이 쓰는 키'로 보고 새 키를 소모해
        # fallback 이 금방 고갈된다(실제로 5개가 배정되지 못했다).
        if cmd_id in (existing or {}):
            assigned.append((cmd_id, "유지"))
            return
        c = combo(mods, key)
        if c in occupied and occupied[c] != cmd_id:
            # 점유됨 — 빈 키를 찾는다
            for alt in list(pool):
                ac = combo(mods, alt)
                if ac not in occupied:
                    pool.remove(alt)
                    out[cmd_id] = [{"modifiers": mods, "key": alt}]
                    occupied[ac] = cmd_id
                    remapped.append((cmd_id, c, ac))
                    return
            skipped.append((cmd_id, c, occupied[c]))
            return
        out[cmd_id] = [{"modifiers": mods, "key": key}]
        occupied[c] = cmd_id
        assigned.append((cmd_id, c))

    for t in spec.get("templater", []):
        # 아직 배포하지 않은 템플릿에는 단축키를 걸지 않는다.
        # 걸어두면 눌렀을 때 "템플릿 없음"이 뜬다 — 부분 설치를 지원하려면 확인해야 한다.
        name = tpl_name(t)
        if have is not None and name not in have:
            continue
        # 여기가 경로가 박히는 자리다. 실제 템플릿 폴더로 조립한다.
        place(f"templater-obsidian:create-{tmpl_rel}/{name}",
              t["modifiers"], t["key"])

    for sc in spec.get("shellcommands", []):
        real = shell_ids.get(sc["id"])
        if not real:
            continue           # 아직 셸커맨드가 병합되지 않았다
        place(f"obsidian-shellcommands:shell-command-{real}",
              sc["modifiers"], sc["key"])

    for p in spec.get("plugin", []):
        place(p["command"], p["modifiers"], p["key"])

    return out, assigned, remapped, skipped


def tpl_name(entry):
    """언어에 맞는 템플릿 파일명.

    ⚠️ 파일명이 언어를 타므로 여기서 고른다. 한국어 이름을 그대로 쓰면
       영어 볼트에서 단축키가 없는 파일을 가리켜 "템플릿 없음"이 뜬다.
    """
    if LANG == "en":
        return entry.get("template_en") or entry["template"]
    return entry["template"]


def build_templater(tmpl_rel, paths, existing, have=None, spec=None):
    """폴더 → 템플릿 매핑. 새 노트를 만들면 양식이 자동으로 채워진다."""
    # (폴더 키, 한국어 파일명, 영어 파일명)
    mapping = [
        ("devlog",  "개발일지양식.md",              "Devlog.md"),
        ("devnote", "개발메모 템플릿.md",           "Dev note.md"),
        ("inbox",   "Inbox Capture 템플릿.md",      "Inbox capture.md"),
        ("idea",    "아이디어 빠른저장 템플릿.md",  "Quick idea.md"),
        ("trouble", "트러블슈팅 템플릿.md",         "Troubleshooting.md"),
        ("youtube", "유튜브 노트 템플릿.md",        "YouTube note.md"),
        ("library", "라이브러리 등록 템플릿.md",    "Library entry.md"),
        ("zettel",  "영구 카드노트 템플릿.md",      "Zettel.md"),
        ("moc",     "MOC 템플릿.md",                "MOC.md"),
        ("report",  "회고 템플릿.md",               "Retro.md"),
        ("todo",    "투두리스트 템플릿.md",         "Todo list.md"),
        ("journal", "일기양식.md",                  "Journal.md"),
        ("book",    "책 템플릿.md",                 "Book.md"),
    ]
    out = dict(existing or {})
    old = out.get("folder_templates") or []
    taken = {m.get("folder") for m in old}

    added = []
    for key, tpl_ko, tpl_en in mapping:
        tpl = tpl_en if LANG == "en" else tpl_ko
        folder = paths.get(key)
        if not folder or folder in taken:
            continue           # 사용자가 이미 매핑한 폴더는 건드리지 않는다
        if have is not None and tpl not in have:
            continue           # 없는 템플릿을 가리키면 새 노트가 빈 채로 만들어진다
        old.append({"folder": folder, "template": f"{tmpl_rel}/{tpl}"})
        added.append(folder)

    out["folder_templates"] = old
    out["templates_folder"] = out.get("templates_folder") or tmpl_rel
    out["syntax_highlighting"] = out.get("syntax_highlighting", True)
    _set_trigger(out)
    _set_template_hotkeys(out, spec, tmpl_rel, have)
    return out, added


def _set_template_hotkeys(out, spec, tmpl_rel, have):
    """단축키를 걸 템플릿을 Templater 에 등록한다.

    ⚠️ Templater 는 이 목록에 있는 템플릿에만 명령을 만든다:

         register_templates_hotkeys() {
           this.plugin.settings.enabled_templates_hotkeys.forEach(
             t => this.add_template_hotkey(t))
         }

       비워두면 templater-obsidian:create-<경로> 라는 명령이 아예 없다.
       그런데 hotkeys.json 에는 그 ID 로 키가 배정된다 — 존재하지 않는
       명령에 키를 거는 셈이라 눌러도 아무 일도 일어나지 않는다.
       "단축키 13개 등록" 이라고 보고하면서 실제로는 0개였다
       (2026-08-22 실물 QA 에서 ⌘⇧D 가 무반응인 것으로 발견).

    build_hotkeys 와 같은 목록을 써야 한다. 어긋나면 다시 죽은 키가 생긴다.
    """
    want = []
    for t in (spec or {}).get("templater", []) or []:
        name = tpl_name(t)
        if have is not None and name not in have:
            continue           # 없는 템플릿에 명령을 만들면 눌렀을 때 오류가 뜬다
        want.append("%s/%s" % (tmpl_rel, name))

    # 사용자가 직접 넣은 항목은 그대로 둔다. 문자열·객체 두 형태를 모두 쓴다.
    old = list(out.get("enabled_templates_hotkeys") or [])
    known = set()
    for e in old:
        known.add(e if isinstance(e, str) else (e or {}).get("template", ""))
    for w in want:
        if w not in known:
            old.append(w)
            known.add(w)
    out["enabled_templates_hotkeys"] = old


def templater_schema_version(plugin_dir):
    """설치된 Templater 가 쓰는 설정 스키마 버전. 못 읽으면 None.

    ⚠️ 값을 짐작하지 않는다. 틀린 data_version 을 쓰면 Templater 가
       마이그레이션을 건너뛰거나 반대로 우리 설정을 지운다.
    """
    if not plugin_dir:
        return None
    import re
    main_js = os.path.join(plugin_dir, "main.js")
    if not os.path.isfile(main_js):
        return None
    try:
        with open(main_js, encoding="utf-8", errors="replace") as f:
            src = f.read()
    except OSError:
        return None
    m = re.search(r"data_version\s*:\s*(\d+)", src)
    return int(m.group(1)) if m else None


def _set_trigger(out):
    """새 파일을 만들 때 폴더 템플릿이 자동으로 들어가게 한다.

    ⚠️ Templater 2.x 는 키를 바꿨다. 예전 키(trigger_on_file_creation,
       enable_folder_templates)는 로드할 때 **삭제된다**:

         for (n of ["trigger_on_file_creation", "enable_system_commands",
                    "enable_folder_templates", "enable_file_templates"])
           delete i[n]

       그래서 예전 키만 쓰면 모드가 "none" 이 되고 자동 삽입이 통째로
       꺼진다 — 2026-08-22 실물 QA 에서 확인했다. 게다가 data_version 이
       없으면 Templater 가 "설정을 초기화했습니다" 경고까지 띄운다.

    설치된 플러그인이 말하는 버전을 읽어 맞는 키를 쓴다.
    읽지 못하면 예전 키로 떨어진다 — 구버전에서는 그게 맞는 키다.
    """
    ver = templater_schema_version(os.environ.get("DT_TEMPLATER_DIR", ""))
    if ver is None:
        out["trigger_on_file_creation"] = True
        out["enable_folder_templates"] = True
        return
    out["data_version"] = ver
    out["trigger_on_file_creation_mode"] = "folder"
    # 예전 키가 남아 있으면 경고를 띄우므로 치운다.
    for k in ("trigger_on_file_creation", "enable_folder_templates",
              "enable_file_templates"):
        out.pop(k, None)


def main():
    what = sys.argv[1]
    spec = load(sys.argv[2], {}) or {}
    paths_json = load(sys.argv[3], {}) or {}
    existing = load(sys.argv[4], {}) if len(sys.argv) > 4 and sys.argv[4] else {}

    paths = paths_json.get("paths") or {}
    tmpl_rel = paths.get("templates") or ("Templates" if LANG == "en" else "템플릿")

    # 실제로 배포된 템플릿 파일명. 없으면 확인을 건너뛴다.
    import os
    tdir = os.environ.get("DT_TEMPLATES_DIR", "")
    have = None
    if tdir and os.path.isdir(tdir):
        have = {f for f in os.listdir(tdir) if f.endswith(".md")}

    if what == "templater":
        out, added = build_templater(tmpl_rel, paths, existing, have, spec)
        print(json.dumps(out, ensure_ascii=False, indent=2))
        print(f"폴더 매핑 {len(added)}개 추가 · 전체 {len(out['folder_templates'])}개",
              file=sys.stderr)
        return 0

    if what == "daily":
        out = dict(existing or {})
        out["folder"] = paths.get("devlog") or out.get("folder") or ""
        out["template"] = f"{tmpl_rel}/개발일지양식.md"
        print(json.dumps(out, ensure_ascii=False, indent=2))
        print(f"데일리노트 → {out['folder']}", file=sys.stderr)
        return 0

    if what == "hotkeys":
        shell_ids = load(sys.argv[5], {}) if len(sys.argv) > 5 and sys.argv[5] else {}
        out, assigned, remapped, skipped = build_hotkeys(
            spec, tmpl_rel, existing, shell_ids, have)
        print(json.dumps(out, ensure_ascii=False, indent=2))
        print(T("hk.assigned", a=len(assigned), r=len(remapped), s=len(skipped)),
              file=sys.stderr)
        for cmd, old, new in remapped:
            print(T("hk.remapped", old=old, new=new), file=sys.stderr)
        for cmd, c, by in skipped:
            print(f"  건너뜀 {c} (이미 사용: {by})", file=sys.stderr)
        return 0

    print(f"알 수 없는 대상: {what}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
