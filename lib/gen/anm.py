#!/usr/bin/env python3
"""DevTrail — Auto Note Mover 규칙 생성기.

태그 → 폴더 라우팅 규칙을 만들어 기존 설정과 병합한다. stdout 으로 낸다.

⚠️ 이 플러그인은 규칙 목록을 위에서부터 훑어 '첫 매칭'에서 멈춘다.
   그래서 순서가 곧 계약이다.

   원본 볼트는 project/* 규칙이 type/dev-note/* 보다 앞에 있었고, 두 태그를
   다 가진 노트가 방금 넣은 폴더 밖으로 끌려나갔다. 그걸 템플릿에
   `AutoNoteMover: disable` 을 박아 우회했다.

   여기서는 우회 대신 순서를 바로잡는다:
     ① type/dev-note/frontend   2단계 — 가장 구체적
     ② type/devlog              1단계
     ③ project/*                프로젝트 귀속
     ④ area/*                   가장 일반적

⚠️ 기존 사용자의 규칙은 건드리지 않는다. 같은 태그를 이미 라우팅하고 있으면
   우리 규칙을 넣지 않는다 — 그들의 의도가 우선이다.
"""

import json
import os
import sys


# 실제 프로젝트 키인가.
#
# project_groups 는 두 가지를 담는다:
#   "my-app": "myapp"    실제 프로젝트   → 태그·폴더·라우팅에 쓴다
#   "acme-*": "acme"     PR 섹션 매칭 규칙 → summary.sh 만 쓴다
#
# 태그와 폴더 이름이 되므로 파일명에 못 쓰는 문자가 있으면 프로젝트가 아니다.
# ADR 0001 D1a · D3 참조.
_BAD_KEY_CHARS = set('*?[]/\\:<>|"')


def is_project_key(key):
    if not key or len(key) > 64:
        return False
    return not (_BAD_KEY_CHARS & set(key))


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def collect_rules(tree, cfg):
    """tree.json 과 설정에서 (구체성, 태그, 폴더) 목록을 만든다."""
    root = (cfg.get("vault") or {}).get("root") or ""
    dirs = cfg.get("dirs") or {}

    def resolve(key, default_path):
        return dirs.get(key) or default_path

    def full(rel):
        return f"{root}/{rel}" if root else rel

    rules = []
    excluded = []

    for f in tree.get("folders", []):
        rel = resolve(f["key"], f["path"])
        # 자동 이동을 하지 않는 폴더는 규칙 대신 제외 목록으로 간다.
        if f.get("no_automove") or f.get("no_index"):
            excluded.append(full(rel))
        elif f.get("tag"):
            rules.append((f["tag"].count("/"), f["tag"], full(rel)))

        for c in f.get("children", []):
            crel = resolve(c["key"], f"{rel}/{c['path']}")
            if f.get("no_automove"):
                continue                      # 부모가 제외면 자식도 제외된다
            if c.get("tag"):
                rules.append((c["tag"].count("/"), c["tag"], full(crel)))

    # 프로젝트 귀속은 타입보다 뒤다. 값이 섹션명이고 키가 레포명이다.
    #
    # ⚠️ wildcard 키("acme-*")는 프로젝트가 아니라 PR 요약 섹션을 찾는
    #    매칭 규칙이다(summary.sh 가 접두사 일치를 지원한다).
    #    거르지 않으면 #project/acme-* → 프로젝트/acme-* 규칙이 생긴다.
    #    Obsidian 태그에 * 를 쓸 수 없으므로 영원히 매치되지 않는 죽은
    #    규칙이고, 폴더 이름에도 * 가 들어간다.
    groups = ((cfg.get("github") or {}).get("project_groups") or {})
    proj_rel = resolve("projects", "개발/프로젝트")
    for repo in sorted(set(groups.keys())):
        if not is_project_key(repo):
            continue
        rules.append((-1, f"project/{repo}", full(f"{proj_rel}/{repo}")))

    # 구체성 내림차순, 같으면 태그 이름순. project/* 는 -1 이라 맨 뒤로 간다.
    rules.sort(key=lambda r: (-r[0], r[1]))
    return rules, excluded


def main():
    tree_path, cfg_path, profile_path = sys.argv[1:4]
    existing_path = sys.argv[4] if len(sys.argv) > 4 else ""
    foreign = [x for x in (os.environ.get("DT_FOREIGN_FOLDERS", "").split("\n")) if x]

    tree = load(tree_path)
    cfg = load(cfg_path, {})
    profile = load(profile_path, {})
    if not tree:
        print(f"트리 정의를 읽을 수 없습니다: {tree_path}", file=sys.stderr)
        return 2

    existing = load(existing_path, {}) if existing_path else {}
    old_rules = existing.get("folder_tag_pattern") or []
    old_tags = {r.get("tag") for r in old_rules if r.get("tag")}

    ours, excluded = collect_rules(tree, cfg)

    # 우리 규칙을 '구체성 순서 그대로' 한 덩어리로 낸다.
    #
    # ⚠️ 예전에는 새로 만든 규칙만 앞에 붙이고(kept + old_rules) 이미 있던
    #    우리 규칙은 뒤에 남겨뒀다. 그래서 나중에 프로젝트를 등록하면
    #    #project/acme-be 가 이미 있던 #type/devlog 보다 앞으로 갔다.
    #    Auto Note Mover 는 첫 매칭을 쓰므로(for i=0..), 프로젝트 태그가 붙은
    #    개발일지가 프로젝트 폴더로 끌려갔다 — 사용자 노트가 사라진 것처럼
    #    보이는 종류의 사고다(2026-08-22 실물 QA 에서 실제로 발생).
    #
    # 사용자가 우리 규칙의 folder 를 고쳤다면 그 값을 존중한다.
    old_by_tag = {}
    for r in old_rules:
        t = r.get("tag")
        if t:
            old_by_tag[t.lstrip("#")] = r

    ordered, skipped = [], []
    our_tags = set()
    for _, tag, folder in ours:
        our_tags.add(tag)
        if tag in old_by_tag:
            skipped.append(tag)          # 이미 라우팅 중이면 그들 것을 남긴다
            ordered.append(old_by_tag[tag])
            continue
        ordered.append({"folder": folder, "tag": f"#{tag}", "pattern": ""})
    kept = [r for r in ordered if r.get("tag", "").lstrip("#") not in set(skipped)]

    # 우리가 모르는 규칙은 사용자 것이다. 순서를 바꾸지 않고 뒤에 붙인다.
    foreign_rules = [r for r in old_rules
                     if (r.get("tag") or "").lstrip("#") not in our_tags]

    auto = profile.get("automove") or {}
    trigger = auto.get("trigger", "Manual")

    old_excluded = [e.get("folder") for e in (existing.get("excluded_folder") or [])
                    if e.get("folder")]
    ex = list(dict.fromkeys(
        old_excluded + excluded + [".obsidian", ".trash"] +
        (foreign if auto.get("exclude_foreign_folders") else [])
    ))

    merged = dict(existing)
    merged.update({
        "trigger_auto_manual": trigger,
        "use_regex_to_check_for_tags": existing.get("use_regex_to_check_for_tags", False),
        "use_regex_to_check_for_excluded_folder":
            existing.get("use_regex_to_check_for_excluded_folder", False),
        "statusBar_trigger_indicator": existing.get("statusBar_trigger_indicator", True),
        "excluded_folder": [{"folder": f} for f in ex],
        # 우리 규칙이 앞이고, 그 안에서 구체성 순서를 항상 유지한다.
        # type/* 가 project/* 보다 먼저 와야 개발일지가 제자리에 남는다.
        "folder_tag_pattern": ordered + foreign_rules,
    })

    print(json.dumps(merged, ensure_ascii=False, indent=2))
    if skipped:
        print(f"이미 라우팅 중이라 건너뛴 태그 {len(skipped)}개: "
              f"{', '.join(skipped[:5])}{' …' if len(skipped) > 5 else ''}",
              file=sys.stderr)
    print(f"규칙 {len(kept)}개 추가 · 기존 {len(old_rules)}개 유지 · "
          f"제외 폴더 {len(ex)}개 · 트리거 {trigger}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
