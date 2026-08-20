"""DevTrail — 생성기용 메시지.

⚠️ 언어는 '표시'만 바꾼다. frontmatter 의 key·tag·필드명은 절대 바뀌지 않는다.
   Dataview 쿼리가 그것들로 동작하므로, 언어를 바꿔도 쿼리가 깨지지 않는다.

셸이 DEVTRAIL_LANG 을 넘긴다. 없으면 ko.
"""

import os

LANG = os.environ.get("DEVTRAIL_LANG", "ko")
if LANG not in ("ko", "en"):
    LANG = "ko"

# 태그 네임스페이스.
#
# ⚠️ #type/* · #project/* · #area/* 는 언어와 무관하다 — 자동 이동 규칙이
#    이것들로 동작한다. 언어를 타는 것은 사용자가 손으로 붙이는 두 가지뿐이다.
#
#   주제 → topic      주제 분류
#   상태 → maturity   숙성도. 'status' 를 쓰지 않는 이유는 frontmatter 의
#                     status 필드(draft·active·done)와 뜻이 달라서다.
NS = {
    "topic":    {"ko": "주제", "en": "topic"},
    "maturity": {"ko": "상태", "en": "maturity"},
}


def ns(key):
    """태그 네임스페이스. 예: ns("topic") → 주제 | topic"""
    e = NS.get(key)
    return (e.get(LANG) or e.get("ko")) if e else key


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
    "l1.entry": {
        "ko": "> 볼트의 진입점입니다. 왼쪽 사이드바에서 북마크해두면 편합니다.",
        "en": "> The entry point to your vault. Bookmark it in the left sidebar.",
    },
    "l1.routine_intro": {
        "ko": "> 하루를 여닫는 순서입니다. 5분이면 됩니다.",
        "en": "> How to open and close the day. Five minutes.",
    },
    "l1.h_daily":     {"ko": "☀️ 일일 루틴",   "en": "☀️ Daily routine"},
    "l1.h_morning":   {"ko": "🕗 아침 (2분)",  "en": "🕗 Morning (2 min)"},
    "l1.h_working":   {"ko": "💻 작업 중 (수시)", "en": "💻 While working (anytime)"},
    "l1.h_evening":   {"ko": "🌇 퇴근 전 (3분)", "en": "🌇 Before logging off (3 min)"},
    "l1.h_friday":    {"ko": "📅 금요일 (10분)", "en": "📅 Friday (10 min)"},
    "l1.h_projects":  {"ko": "🏗️ 진행 중인 프로젝트", "en": "🏗️ Active projects"},
    "l1.h_areas":     {"ko": "🧭 영역별 개발메모", "en": "🧭 Notes by area"},
    "l1.h_maint":     {"ko": "🧹 볼트 유지보수", "en": "🧹 Vault maintenance"},
    "l1.h_created":   {"ko": "🟢 오늘 만든 노트", "en": "🟢 Created today"},
    "l1.h_stale":     {"ko": "🔴 오래 묵은 것",  "en": "🔴 Gone stale"},
    "l1.h_week":      {"ko": "🟡 이번 주 개발일지 (공백일 확인)",
                       "en": "🟡 This week's devlogs (spot the gaps)"},
    "l1.h_recent_act":{"ko": "최근 활동",       "en": "Recent activity"},
    "l1.h_recent_log":{"ko": "최근 개발일지",   "en": "Recent devlogs"},
    "l1.h_recent_7":  {"ko": "최근 7일에 만든 노트", "en": "Created in the last 7 days"},
    "l1.h_orphans":   {"ko": "연결이 없는 노트", "en": "Notes with no links"},
    "l1.h_inbox_age": {"ko": "Inbox 적체 (오래된 순)", "en": "Inbox backlog (oldest first)"},

    "l1.morning_1": {
        "ko": "1. `⌘⇧D` — 개발일지를 만들고 오늘 할 것 Top 3 을 적는다",
        "en": "1. `⌘⇧D` — create today's devlog and write your top 3",
    },
    "l1.morning_2": {
        "ko": "2. `⌘⇧G` — GitHub 활동을 일지에 넣는다",
        "en": "2. `⌘⇧G` — pull GitHub activity into the devlog",
    },
    "l1.evening_1": {
        "ko": "1. 개발일지의 '오늘 배운 것' 을 한 줄 채운다",
        "en": "1. Fill in one line under \"what I learned today\"",
    },
    "l1.evening_2": {
        "ko": "2. 아래 '오래 묵은 것' 을 한 번 훑는다",
        "en": "2. Skim \"gone stale\" below",
    },
    "l1.evening_3": {
        "ko": "3. 미완료를 내일로 옮긴다",
        "en": "3. Move anything unfinished to tomorrow",
    },
    "l1.friday": {
        "ko": "주간리뷰를 만들고 아래 헬스체크를 본다.",
        "en": "Create the weekly review and run the health check below.",
    },
    "l1.tbl_what":  {"ko": "무엇",  "en": "What"},
    "l1.tbl_key":   {"ko": "단축키", "en": "Hotkey"},
    "l1.row_note":  {"ko": "배운 것을 메모", "en": "Note something you learned"},
    "l1.row_idea":  {"ko": "아이디어 캡처",  "en": "Capture an idea"},
    "l1.row_save":  {"ko": "자료 저장",      "en": "Save a reference"},
    "l1.row_stuck": {"ko": "막힌 것을 기록",  "en": "Log something you got stuck on"},
    "l1.row_stuck_v": {
        "ko": "트러블슈팅 폴더에서 새 노트",
        "en": "New note in the Troubleshooting folder",
    },
    "l1.approx_size": {
        "ko": "> ℹ️ `status` 커버리지가 {pct}% 라 분량으로 근사합니다.",
        "en": "> ℹ️ `status` coverage is {pct}%, so note length is used instead.",
    },
    "l2.desc": {
        "ko": "L2 영역 허브. 하위 폴더 허브로 가는 입구.",
        "en": "L2 area hub. Entry point to the folder hubs below.",
    },
    "col.log":    {"ko": "일지",   "en": "Log"},
    "col.status": {"ko": "상태",   "en": "Status"},
    "col.stage":  {"ko": "단계",   "en": "Stage"},
    "col.days":   {"ko": "체류일", "en": "Days"},
    "col.where":  {"ko": "위치",   "en": "Where"},

    "nav.devlog":   {"ko": "📝 개발일지",   "en": "📝 Devlog"},
    "nav.devnote":  {"ko": "📂 개발메모",   "en": "📂 Notes"},
    "nav.projects": {"ko": "🏗️ 프로젝트",  "en": "🏗️ Projects"},
    "nav.idea":     {"ko": "💡 아이디어",   "en": "💡 Ideas"},
    "nav.trouble":  {"ko": "🔧 트러블슈팅", "en": "🔧 Troubleshooting"},
    "nav.library":  {"ko": "📚 라이브러리", "en": "📚 Libraries"},
    "nav.inbox":    {"ko": "📥 Inbox",      "en": "📥 Inbox"},
    "nav.zettel":   {"ko": "🗂 카드노트",   "en": "🗂 Zettel"},

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
