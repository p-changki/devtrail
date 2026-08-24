#!/usr/bin/env bash
# 파일명 규칙·헤딩이 **막다른 길이 아닌가**.
#
# ⚠️ 왜 이 파일이 생겼나 (2026-08-24 실물 QA)
#
#    기존 볼트를 흡수하면 개발일지 파일명("2026-08-24 개발일지.md")과
#    헤딩("## 🔗 오늘의 이슈 / PR")이 DevTrail 기본값과 다르다. 그런데:
#
#      셋업      물어보지 않았다
#      config    "변경할 수 없는 키입니다" 로 거부했다
#      스크립트  못 찾으면 "건너뜀" 한 줄 찍고 exit 0 했다
#
#    세 곳 다 성공처럼 끝나서, 사용자에게는 **눌렀는데 아무 일도 안 난다**
#    로만 보였다. 고칠 길 자체가 없었다.
#
#    그래서 여기서 보는 것은 두 가지다:
#      ① 사용자가 스스로 고칠 수 있는가 (config set 이 받는가)
#      ② 어긋났을 때 **무엇을 어떻게** 고치라고 말하는가
#
# ⚠️ "메시지가 있다" 로는 안 된다. 예전 메시지도 있었다 — 다만 아무것도
#    알려주지 않았을 뿐이다. 실제로 **고칠 명령이 들어 있는지**를 본다.
set -u
. "$(dirname "$0")/lib/harness.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DT="$ROOT/bin/devtrail"
T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

# ═══ ① 사용자가 스스로 고칠 수 있는가 ═══════════════════════════════════════
t_start "config set — 파일명·헤딩"
t_vault free
t_config notes

t_contains "keys 가 자유 입력 키를 안내한다" "naming.devlog_file" "$("$DT" config keys 2>&1)"
t_contains "헤딩 키도 안내한다"              "headings.issues_pr" "$("$DT" config keys 2>&1)"

set_ok() {   # set_ok <설명> <키> <값>
  "$DT" config set "$2" "$3" --apply >/dev/null 2>&1
  t_eq "$1" "$3" "$(jq -r ".$2" "$T_CONFIG" 2>/dev/null)"
}
set_no() {   # set_no <설명> <키> <값>
  local before after
  before=$(jq -c . "$T_CONFIG")
  "$DT" config set "$2" "$3" --apply >/dev/null 2>&1
  after=$(jq -c . "$T_CONFIG")
  # ⚠️ 종료코드만 보면 안 된다. 거부했다면서 파일은 바꿔 놓는 경우를 잡는다.
  t_eq "$1" "$before" "$after"
}

set_ok "개발일지 파일명을 바꾼다"   naming.devlog_file  '{{DATE}} 개발일지.md'
set_ok "주간리뷰 파일명을 바꾼다"   naming.weekly_file  '{{ISOWEEK}} 주간리뷰.md'
set_ok "이슈/PR 헤딩을 바꾼다"      headings.issues_pr  '## 🔗 오늘의 이슈 / PR'
set_ok "오전 헤딩을 바꾼다"         headings.morning    '### 오전'

# ⚠️ 자유 입력이라고 아무거나 받으면 안 된다. 아래는 전부 **조용히 망가지는**
#    값이다 — 저장은 되고, 나중에 스크립트가 할 일을 못 찾는다.
set_no "{{DATE}} 없는 파일명은 거부"   naming.devlog_file  'devlog.md'
set_no "{{ISOWEEK}} 없는 주간 파일명"  naming.weekly_file  'weekly.md'
set_no ".md 가 아니면 거부"            naming.devlog_file  '{{DATE}} 개발일지'
set_no "경로가 섞이면 거부"            naming.devlog_file  'sub/{{DATE}}.md'
set_no "# 없는 헤딩은 거부"            headings.issues_pr  '오늘의 이슈'
set_no "빈 값은 거부"                  headings.issues_pr  ''
set_no "여러 줄 헤딩은 거부"           headings.issues_pr  '## 하나
## 둘'
set_no "허용 목록 밖 키는 거부"        naming.date_format  '%d/%m/%Y'

# ═══ ② 어긋났을 때 고칠 길을 말하는가 ═══════════════════════════════════════
#
# ⚠️ 여기가 핵심이다. ①만 있으면 "고칠 수는 있는데 고쳐야 하는 줄 모르는"
#    상태가 그대로 남는다.
t_start "어긋났을 때의 안내"
t_vault hint
t_config notes '.naming.devlog_file = "{{DATE}} devlog.md"'

(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/init/prompts.sh"; . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
A="$DEVTRAIL_HOME/scripts/activity.sh"
t_file "activity.sh 렌더" "$A"

DEVLOG_DIR="$T_VAULT/notes/개발/개발일지"
mkdir -p "$DEVLOG_DIR"

# ── (a) 폴더에 노트는 있는데 이름 규칙이 다르다 ─────────────────────────────
#
# ⚠️ 이게 사용자가 실제로 겪은 상황이다. 폴더는 맞게 찾았는데 파일명이
#    달라서 영영 못 만난다.
printf -- '---\n---\n# 일지\n' > "$DEVLOG_DIR/2026-08-24 개발일지.md"
out=$(DEVTRAIL_ACTIVITY_WAIT=1 bash "$A" 2026-08-24 2>&1)

t_contains "찾던 경로를 말한다"       "2026-08-24 devlog.md"    "$out"
t_contains "폴더의 실제 파일을 보여준다" "2026-08-24 개발일지.md" "$out"
t_contains "무엇을 고쳐야 하는지 말한다" "naming.devlog_file"     "$out"
# ⚠️ "설정을 확인하세요" 로는 부족하다. 복붙할 수 있는 명령이어야 한다.
t_contains "고치는 명령을 준다"       "config set"              "$out"
t_contains "--apply 까지 준다"        "--apply"                 "$out"

# ── (b) 폴더가 비었다 — 규칙 문제가 아니다. 엉뚱한 안내를 하면 안 된다 ──────
t_vault hint2
t_config notes
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/init/prompts.sh"; . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
A2="$DEVTRAIL_HOME/scripts/activity.sh"
mkdir -p "$T_VAULT/notes/개발/개발일지"
out=$(DEVTRAIL_ACTIVITY_WAIT=1 bash "$A2" 2026-08-24 2>&1)
t_contains "비었으면 만들라고 한다"   "먼저 만드세요"           "$out"
t_not_contains "규칙 얘기는 안 한다"  "naming.devlog_file"      "$out"

# ── (c) 노트는 있는데 헤딩이 없다 ───────────────────────────────────────────
t_vault hint3
t_config notes
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/init/prompts.sh"; . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
A3="$DEVTRAIL_HOME/scripts/activity.sh"
D3="$T_VAULT/notes/개발/개발일지"; mkdir -p "$D3"
printf -- '---\n---\n## 🔗 오늘의 이슈 / PR\n\n## 📝 작업 로그\n' \
  > "$D3/2026-08-24 devlog.md"
out=$(DEVTRAIL_ACTIVITY_WAIT=1 bash "$A3" 2026-08-24 2>&1)

t_contains "못 찾은 헤딩을 말한다"      "Issues / PRs"       "$out"
t_contains "노트의 실제 헤딩을 보여준다" "오늘의 이슈 / PR"   "$out"
t_contains "헤딩 설정 키를 말한다"      "headings.issues_pr" "$out"
t_contains "고치는 명령을 준다"         "config set"         "$out"

# ── (d) 이벤트로 불렸는데 이름이 규칙과 다르다 ──────────────────────────────
#
# ⚠️ 예전에는 이 경로가 **완전히 조용했다**. 정확히 고쳐야 할 사람에게만
#    아무 말도 안 하는 셈이었다.
out=$(DEVTRAIL_EVENT_FILE="$D3/2026-08-24 개발일지.md" \
      DEVTRAIL_ACTIVITY_WAIT=1 bash "$A3" 2026-08-24 2>&1)
t_contains "규칙과 다르다고 말한다"   "naming.devlog_file"      "$out"
t_contains "만들어진 이름을 보여준다" "2026-08-24 개발일지.md"  "$out"

# ⚠️ 날짜만 다른 경우는 정상이다. 여기서 경고하면 노트 만들 때마다 시끄럽다.
out=$(DEVTRAIL_EVENT_FILE="$D3/2026-08-20 devlog.md" \
      DEVTRAIL_ACTIVITY_WAIT=1 bash "$A3" 2026-08-24 2>&1)
t_eq "지난 날짜 노트에는 조용하다" "" "$out"

# ⚠️ 개발일지 폴더 **밖**의 노트에도 조용해야 한다.
out=$(DEVTRAIL_EVENT_FILE="$T_VAULT/notes/딴-노트.md" \
      DEVTRAIL_ACTIVITY_WAIT=1 bash "$A3" 2026-08-24 2>&1)
t_eq "무관한 노트에는 조용하다" "" "$out"

# ═══ ③ 안내를 아는 곳이 하나인가 ════════════════════════════════════════════
#
# ⚠️ 이 저장소는 dirs.devlog 기본값을 네 곳에 두고 같은 결함을 네 번 고쳤다.
#    안내 문구가 스크립트마다 따로 있으면 같은 일이 또 난다.
t_start "안내는 한 곳에서만 안다"
t_contains "_lib 이 hint_fix 를 정의한다" \
  "hint_fix()" "$(cat "$ROOT/templates/scripts/_lib.sh.tmpl")"
for f in activity summary; do
  body=$(cat "$ROOT/templates/scripts/$f.sh.tmpl")
  t_not_contains "$f 가 config set 문구를 따로 안 적는다" \
    "config set" "$body"
done

# ═══ ④ doctor 가 누르기 전에 잡는가 ═════════════════════════════════════════
#
# ⚠️ ②는 사용자가 **누른 뒤**에 알려준다. 그 전에 알 수 있어야 한다 —
#    doctor 는 "왜 안 되지" 일 때 사람이 실제로 여는 곳이다.
t_start "doctor — 파일명·헤딩"

d_vault() {   # d_vault <이름> <파일명> <본문 헤딩...>
  t_vault "$1"; t_config notes
  D="$T_VAULT/notes/개발/개발일지"; mkdir -p "$D"
  printf -- '---\n---\n%s\n' "$3" > "$D/$2"
}

# (a) 파일명이 규칙과 하나도 안 맞는다
d_vault dr1 '2026-08-24 개발일지.md' '## 🔗 오늘의 이슈 / PR'
out=$("$DT" doctor 2>&1)
t_contains "규칙과 안 맞는다고 말한다"   "파일명 규칙과 하나도 안 맞" "$out"
t_contains "설정된 규칙을 보여준다"      "{{DATE}} devlog.md"         "$out"
t_contains "실제 파일명을 보여준다"      "2026-08-24 개발일지.md"     "$out"
t_contains "고치는 명령을 준다"          "config set naming.devlog_file" "$out"

# (b) 파일명은 맞는데 헤딩이 다르다
d_vault dr2 '2026-08-24 devlog.md' '## 🔗 오늘의 이슈 / PR'
out=$("$DT" doctor 2>&1)
t_contains "파일명은 통과시킨다"         "개발일지 파일명 규칙"       "$out"
t_contains "없는 헤딩을 말한다"          "없는 헤딩"                  "$out"
t_contains "실제 헤딩을 보여준다"        "오늘의 이슈 / PR"           "$out"
t_contains "헤딩 고치는 명령을 준다"     "config set headings.issues_pr" "$out"

# (c) 둘 다 맞으면 조용하다
#
# ⚠️ 이게 없으면 "항상 경고하는" 구현도 (a)(b)를 통과한다.
d_vault dr3 '2026-08-24 devlog.md' '## Issues / PRs

## Work log'
out=$("$DT" doctor 2>&1)
t_not_contains "맞으면 규칙 경고 안 함"  "안 맞습니다"                "$out"
t_not_contains "맞으면 헤딩 경고 안 함"  "없는 헤딩"                  "$out"
t_contains "맞다고 말해준다"             "헤딩이 최근 일지와 맞습니다" "$out"

# (d) 일지가 아직 없으면 규칙 탓을 하지 않는다
t_vault dr4; t_config notes
mkdir -p "$T_VAULT/notes/개발/개발일지"
out=$("$DT" doctor 2>&1)
t_not_contains "빈 폴더에는 규칙 경고 안 함" "안 맞습니다" "$out"
t_end
