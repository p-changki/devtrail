#!/usr/bin/env python3
"""DevTrail — L3 폴더 허브 생성기.

폴더 하나만 보는 대시보드를 만든다. 환경변수로 값을 받아 stdout 으로 낸다.

핵심은 '쿼리를 볼트 상태에 맞춰 고른다'는 것이다.

  값 커버리지 >= 50%   정식   frontmatter 기반. 정확하다.
            10~50%   병용   frontmatter 우선, 없으면 파일시스템으로 보완
             < 10%   폴백   파일시스템 메타만. 근사치라고 밝힌다.

커버리지를 무시하고 정식 쿼리를 박으면 Dataview 가 필드 없는 노트를 조용히
제외해 빈 결과가 나온다. 사용자는 그걸 "밀린 게 없다"로 읽고 방치한다.
원본 볼트에서 카드노트 12개 · 월간리뷰 0개가 그렇게 만들어졌다.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import t as T  # noqa: E402

FULL, MIXED, FALLBACK = "full", "mixed", "fallback"
STALE_DAYS = 90
THIN_BYTES = 500


def tier(pct):
    if pct >= 50:
        return FULL
    if pct >= 10:
        return MIXED
    return FALLBACK


def block_recent(src):
    return f"""## {T("hub.recent")}

```dataview
TABLE WITHOUT ID
  file.link AS "{T("col.note")}",
  dateformat(file.mtime, "yyyy-MM-dd") AS "{T("col.modified")}"
FROM "{src}"
WHERE file.name != "_index"
SORT file.mtime DESC
LIMIT 15
```"""


def block_stale(src, pct):
    t = tier(pct)
    if t == FULL:
        note = ""
        where = "review_at AND review_at <= date(today)"
        order = "review_at ASC"
    elif t == MIXED:
        note = T("hub.mixed_review", pct=pct) + T("hub.mixed_note")
        where = (f'(review_at AND review_at <= date(today))\n'
                 f'  OR (!review_at AND file.mtime <= date(today) - dur({STALE_DAYS} days))')
        order = "file.mtime ASC"
    else:
        note = (T("hub.low_review", pct=pct) + T("hub.approx_mtime")
                + T("hub.align_hint"))
        where = f"file.mtime <= date(today) - dur({STALE_DAYS} days)"
        order = "file.mtime ASC"

    return f"""## {T("hub.due")}

{note}```dataview
LIST
FROM "{src}"
WHERE file.name != "_index"
  AND ({where})
SORT {order}
LIMIT 15
```"""


def block_unfinished(src, pct):
    t = tier(pct)
    if t == FULL:
        note = ""
        where = 'status = "draft"'
    elif t == MIXED:
        note = T("hub.mixed_status", pct=pct)
        where = f'status = "draft" OR (!status AND file.size < {THIN_BYTES})'
    else:
        note = T("hub.low_status", pct=pct) + T("hub.approx_short")
        where = f"file.size < {THIN_BYTES}"

    return f"""## {T("hub.unfinished")}

{note}```dataview
TABLE WITHOUT ID file.link AS "{T("col.note")}", file.size AS "{T("col.size")}"
FROM "{src}"
WHERE file.name != "_index" AND ({where})
SORT file.size ASC
LIMIT 10
```"""


def block_orphan(src):
    return f"""## {T("hub.orphans")}

```dataview
LIST
FROM "{src}"
WHERE file.name != "_index"
  AND length(file.outlinks) = 0 AND length(file.inlinks) = 0
SORT file.ctime DESC
LIMIT 10
```"""


def main():
    src = os.environ.get("DT_HUB_FROM", "")
    title = os.environ.get("DT_HUB_TITLE", T("col.folder"))
    key = os.environ.get("DT_HUB_KEY", "")
    date = os.environ.get("DT_HUB_DATE", "")
    if not src:
        print(T("err.need_from"), file=sys.stderr)
        return 2

    def pct(name):
        try:
            return round(float(os.environ.get(name, "0")), 1)
        except ValueError:
            return 0.0

    cov_review = pct("DT_HUB_COV_REVIEW")
    cov_status = pct("DT_HUB_COV_STATUS")

    parts = [
        "---",
        "tags:",
        "  - type/moc",
        "type: moc",
        "scope: folder",           # 폴더 허브 · 주제 MOC 를 이걸로 구분한다
        f"devtrail_key: {key}",    # devtrail path 로 되찾을 수 있게
        f"created: {date}",
        f"updated: {date}",
        "---",
        "",
        f"# {title}",
        "",
        T("hub.scope"),
        "",
        block_recent(src),
        "",
        block_stale(src, cov_review),
        "",
        block_unfinished(src, cov_status),
        "",
        block_orphan(src),
        "",
    ]
    print("\n".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
