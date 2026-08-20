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
    groups = ((cfg.get("github") or {}).get("project_groups") or {})
    proj_rel = resolve("projects", "개발/프로젝트")
    for repo in sorted(set(groups.keys())):
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

    kept, skipped = [], []
    for _, tag, folder in ours:
        if f"#{tag}" in old_tags or tag in old_tags:
            skipped.append(tag)          # 이미 라우팅 중이면 그들 것을 남긴다
            continue
        kept.append({"folder": folder, "tag": f"#{tag}", "pattern": ""})

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
        # 우리 규칙이 앞이다 — 내부적으로 구체성 순서라 자기들끼리는 안 싸운다.
        # 겹치는 태그는 이미 걸러냈으므로 기존 규칙도 그대로 동작한다.
        "folder_tag_pattern": kept + old_rules,
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
