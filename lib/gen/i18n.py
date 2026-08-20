"""DevTrail — 생성기용 메시지.

⚠️ 언어는 '표시'만 바꾼다. frontmatter 의 key·tag·필드명은 절대 바뀌지 않는다.
   Dataview 쿼리가 그것들로 동작하므로, 언어를 바꿔도 쿼리가 깨지지 않는다.

셸이 DEVTRAIL_LANG 을 넘긴다. 없으면 ko.
"""

import os

LANG = os.environ.get("DEVTRAIL_LANG", "ko")
if LANG not in ("ko", "en"):
    LANG = "ko"

_M = {
    # ── 허브 (hub.py) ────────────────────────────────────────────────────────
    "hub.scope": {
        "ko": "> 이 폴더만 봅니다. DevTrail 이 만들었고 `devtrail augment --refresh-hubs` 로 갱신됩니다.",
        "en": "> This folder only. Created by DevTrail; refresh with `devtrail augment --refresh-hubs`.",
    },
    "hub.recent":   {"ko": "최근",            "en": "Recent"},
    "hub.due":      {"ko": "재방문할 때가 됐다", "en": "Due for review"},
    "hub.nothing":  {"ko": "밀린 게 없다",     "en": "Nothing due"},
    "hub.unfinished": {"ko": "미완성",         "en": "Unfinished"},
    "hub.orphans":  {"ko": "연결이 없다",      "en": "No links"},
    "col.note":     {"ko": "노트",            "en": "Note"},
    "col.modified": {"ko": "수정",            "en": "Modified"},
    "col.size":     {"ko": "크기",            "en": "Size"},
    "col.folder":   {"ko": "폴더",            "en": "Folder"},

    "hub.approx_mtime": {
        "ko": "**마지막 수정일로 근사**합니다.\n",
        "en": "approximated by **last modified date**.\n",
    },
    "hub.approx_short": {
        "ko": "**분량이 적은 노트로 근사**합니다.\n\n",
        "en": "approximated by **short notes**.\n\n",
    },
    "hub.mixed_review": {
        "ko": "> ℹ️ `review_at` 커버리지가 {pct}% 입니다 — ",
        "en": "> ℹ️ `review_at` coverage is {pct}% — ",
    },
    "hub.mixed_status": {
        "ko": "> ℹ️ `status` 커버리지가 {pct}% 입니다 — 분량이 적은 노트도 함께 봅니다.\n\n",
        "en": "> ℹ️ `status` coverage is {pct}% — short notes are included too.\n\n",
    },
    "hub.low_review": {
        "ko": "> ℹ️ 이 볼트는 `review_at` 을 거의 쓰지 않아 (커버리지 {pct}%) ",
        "en": "> ℹ️ This vault barely uses `review_at` (coverage {pct}%), so it is ",
    },
    "hub.low_status": {
        "ko": "> ℹ️ 이 볼트는 `status` 를 거의 쓰지 않아 (커버리지 {pct}%) ",
        "en": "> ℹ️ This vault barely uses `status` (coverage {pct}%), so it is ",
    },
    "hub.align_hint": {
        "ko": "> 정확하게 하려면: `devtrail align --field review_at`\n\n",
        "en": "> For exact results: `devtrail align --field review_at`\n\n",
    },
    "hub.mixed_note": {
        "ko": "값이 있는 노트는 예정일로, 없는 노트는 마지막 수정일로 봅니다.\n\n",
        "en": "Notes with a value use it; the rest fall back to last modified.\n\n",
    },
    "err.need_from": {
        "ko": "DT_HUB_FROM 이 필요합니다",
        "en": "DT_HUB_FROM is required",
    },

    # ── L1 대시보드 (hubs.py) ────────────────────────────────────────────────
    "l1.dashboard":  {"ko": "대시보드",      "en": "Dashboard"},
    "l1.checkin":    {"ko": "일일 체크인",   "en": "Daily check-in"},
    "l1.today":      {"ko": "오늘",          "en": "Today"},
    "l1.this_week":  {"ko": "이번 주",       "en": "This week"},
    "l1.inbox":      {"ko": "받은 것",       "en": "Inbox"},
    "l1.areas":      {"ko": "영역",          "en": "Areas"},
    "l1.generated":  {
        "ko": "> DevTrail 이 만들었습니다. 직접 고쳐도 됩니다 — 다시 만들지 않습니다.",
        "en": "> Created by DevTrail. Safe to edit — it will not be regenerated.",
    },
}


def t(key, **kw):
    """메시지를 낸다. 키가 없으면 [key] 로 눈에 띄게 낸다 — 죽지 않는다."""
    entry = _M.get(key)
    if entry is None:
        return "[%s]" % key
    s = entry.get(LANG) or entry.get("ko") or "[%s]" % key
    return s.format(**kw) if kw else s
