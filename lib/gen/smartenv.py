#!/usr/bin/env python3
"""DevTrail — Smart Connections(RAG) 제외 설정 생성기.

인덱스를 넓히는 게 아니라 좁히는 것이 이 레이어의 품질을 결정한다.
자동 수집물과 반복 서식을 빼지 않으면 유사도 검색이 무의미해진다.

⚠️ 헤딩 제외 목록을 손으로 관리하면 반드시 샌다.
   원본 볼트는 `🔗 오늘 만든/연결한 노트 (자동 집계)` 는 제외했는데
   같은 성격의 `📺 오늘 본 유튜브` 는 빠뜨렸다. 그 결과 매일 똑같은
   Dataview 쿼리 문자열이 모든 개발일지에 임베딩됐다.

   그래서 여기서는 템플릿을 읽어 **Dataview 코드블록을 품은 헤딩을 찾아
   생성한다.** 템플릿에 쿼리를 추가하면 제외 목록이 자동으로 따라온다.
"""

import json
import os
import re
import sys

DATAVIEW_RE = re.compile(r"```dataview", re.I)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")


def headings_with_dataview(path):
    """Dataview 블록이 들어 있는 헤딩 제목을 낸다."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []

    found, current = [], None
    for line in lines:
        m = HEADING_RE.match(line)
        if m:
            current = m.group(2).strip()
            continue
        if current and DATAVIEW_RE.search(line):
            if current not in found:
                found.append(current)
    return found


def main():
    tree_path, cfg_path, templates_dir = sys.argv[1:4]
    existing_path = sys.argv[4] if len(sys.argv) > 4 else ""

    def load(p, d=None):
        try:
            with open(p, encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return d

    tree = load(tree_path)
    cfg = load(cfg_path, {}) or {}
    if not tree:
        print(f"트리 정의를 읽을 수 없습니다: {tree_path}", file=sys.stderr)
        return 2

    root = (cfg.get("vault") or {}).get("root") or ""
    dirs = cfg.get("dirs") or {}

    def full(key, default_path):
        rel = dirs.get(key) or default_path
        return f"{root}/{rel}" if root else rel

    # 인덱싱하지 않을 폴더: 자동 수집물 · 첨부 · 아카이브 · 템플릿
    excl_folders = []
    for f in tree.get("folders", []):
        if f.get("no_index"):
            excl_folders.append(full(f["key"], f["path"]))
    # 개인 영역은 설치했더라도 임베딩하지 않는다.
    for f in tree.get("folders", []):
        if f.get("module") == "personal":
            excl_folders.append(full(f["key"], f["path"]))

    foreign = [x for x in os.environ.get("DT_FOREIGN_FOLDERS", "").split("\n") if x]
    excl_folders += foreign

    # 헤딩 제외: 템플릿에서 생성한다
    excl_headings = []
    if os.path.isdir(templates_dir):
        for name in sorted(os.listdir(templates_dir)):
            if name.endswith(".md"):
                for h in headings_with_dataview(os.path.join(templates_dir, name)):
                    if h not in excl_headings:
                        excl_headings.append(h)

    existing = load(existing_path, {}) if existing_path else {}
    sources = dict(existing.get("smart_sources") or {})

    old_folders = [x for x in (sources.get("folder_exclusions") or "").split(",") if x.strip()]
    old_heads = [x for x in (sources.get("excluded_headings") or "").split(",") if x.strip()]

    merged_folders = list(dict.fromkeys([x.strip() for x in old_folders] + excl_folders))
    merged_heads = list(dict.fromkeys([x.strip() for x in old_heads] + excl_headings))

    sources["folder_exclusions"] = ",".join(merged_folders)
    sources["excluded_headings"] = ",".join(merged_heads)
    sources.setdefault("min_chars", 200)

    out = dict(existing)
    out["smart_sources"] = sources
    out.setdefault("is_obsidian_vault", True)

    print(json.dumps(out, ensure_ascii=False, indent=2))
    print(f"폴더 제외 {len(merged_folders)}개 · 헤딩 제외 {len(merged_heads)}개 "
          f"(템플릿에서 {len(excl_headings)}개 생성)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
