#!/usr/bin/env bash
# devtrail path — 경로 해석 단일 창구.
#
# 여기가 깨지면 템플릿·스킬·쿼리가 전부 엉뚱한 곳을 가리킨다.
# 가장 먼저 지켜야 할 계약이다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"

# ── 기본 해석 ────────────────────────────────────────────────────────────────
t_start "tree.json 기본값"
t_vault basic
t_config notes

t_eq "루트 아래 상대경로" \
  "notes/개발/개발일지" "$("$DT" path --rel devlog)"
t_eq "하위 폴더 (점 표기)" \
  "notes/개발/개발메모/Frontend" "$("$DT" path --rel devnote.frontend)"
t_eq "절대경로는 볼트 경로로 시작" \
  "$T_VAULT/notes/개발/개발일지" "$("$DT" path devlog)"

# ── config 가 tree.json 을 이긴다 (「얹기」의 핵심) ───────────────────────────
t_start "config.dirs 우선순위"
t_vault adopt
t_config notes '.dirs.devlog = "Daily"'

t_eq "config 값이 이긴다" \
  "notes/Daily" "$("$DT" path --rel devlog)"
t_eq "매핑 안 한 키는 기본값" \
  "notes/개발/아이디어" "$("$DT" path --rel idea)"

# ── 빈 루트 (볼트 최상위에 바로 두는 사람) ───────────────────────────────────
t_start "빈 루트"
t_vault emptyroot
t_config "" '.dirs.devlog = "Daily"'

t_eq "앞 슬래시가 붙지 않는다" \
  "Daily" "$("$DT" path --rel devlog)"
t_not_contains "절대경로에 이중 슬래시가 없다" \
  "//" "$("$DT" path devlog)"

# ── 오류 처리 ────────────────────────────────────────────────────────────────
t_start "알 수 없는 키"
t_vault unknown
t_config notes

t_exit "종료코드 1" 1 "$DT" path nosuchkey
t_contains "안내 문구" "전체 목록" "$("$DT" path nosuchkey 2>&1)"

# ── 전체 목록 · JSON ─────────────────────────────────────────────────────────
t_start "목록과 JSON"
t_vault listing
t_config notes

n=$("$DT" path | wc -l | tr -d ' ')
t_ne "목록이 비지 않는다" "0" "$n"
t_eq "tree.json 정의 수와 일치" \
  "$(jq '[.folders[], (.folders[].children // [])[]] | length' "$ROOT/preset/tree.json")" "$n"

"$DT" path --json > "$T_TMP/paths.json"
t_json "유효한 JSON" "$T_TMP/paths.json"
t_eq "abs·rel 둘 다 낸다" \
  "notes/개발/개발일지" "$(jq -r '.devlog.rel' "$T_TMP/paths.json")"

# ── 생성된 스크립트가 같은 해석기를 쓰는가 ─────────────────────────────────
#
# ⚠️ 회귀: _lib.sh 가 cfg '.dirs.devlog' 를 직접 읽던 시절, 새로 설치한
#    볼트(.dirs 가 {})에서 경로가 "<루트>/" 가 됐다.
#      activity · summary · backfill  개발일지를 영영 못 찾음
#      weekly                         볼트 루트에 파일을 만듦
#    기본값이 dt_dir 과 _lib.sh 두 곳에 있었던 탓이다.
t_start "생성된 스크립트의 경로 해석"
t_vault gen
t_config notes
t_eq "설정의 dirs 는 비어 있다" "{}" "$(jq -c '.dirs' "$T_CONFIG")"

# init 전체를 돌리지 않고 렌더링만 한다.
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/init/prompts.sh"
  . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
t_file "_lib.sh 생성" "$DEVTRAIL_HOME/scripts/_lib.sh"

# ⚠️ 렌더 시점 치환자가 남으면 스크립트가 존재하지 않는 경로를 부른다.
#    {{DATE}} 는 실행 시점에 파일명 규칙으로 치환되므로 남아 있는 게 맞다.
left=$(grep -o '{{DEVTRAIL_BIN}}\|{{CONFIG_FILE}}\|{{DEVTRAIL_HOME}}' \
       "$DEVTRAIL_HOME/scripts/"*.sh 2>/dev/null | head -3)
t_eq "렌더 시점 치환자가 남지 않는다" "" "$left"

got=$(bash -c '. "$1"; printf "%s" "$DEVLOG_DIR"' _ "$DEVTRAIL_HOME/scripts/_lib.sh" 2>/dev/null)
t_eq "DEVLOG_DIR 이 기본 폴더까지 간다" "$T_VAULT/notes/개발/개발일지" "$got"

gotw=$(bash -c '. "$1"; printf "%s" "$WEEKLY_DIR"' _ "$DEVTRAIL_HOME/scripts/_lib.sh" 2>/dev/null)
t_eq "WEEKLY_DIR 도 마찬가지" "$T_VAULT/notes/개발/주간리뷰" "$gotw"

gotf=$(bash -c '. "$1"; printf "%s" "$(devlog_path 2026-08-22)"' _ "$DEVTRAIL_HOME/scripts/_lib.sh" 2>/dev/null)
t_eq "개발일지 파일 경로" "$T_VAULT/notes/개발/개발일지/2026-08-22 devlog.md" "$gotf"
# 볼트 루트 바로 아래를 가리키면 그게 예전 결함이다.
t_not_contains "루트 바로 밑이 아니다" "notes/2026-08-22" "$gotf"

# ── activity 가 이벤트 파일로 걸러지는가 ────────────────────────────────────
#
# ⚠️ 회귀: file-created 는 '빈 파일이 생기는 순간' 쏜다. Templater 는 그 뒤에
#    본문을 쓴다. 예전에는 1.5초만 기다려서 같은 조작이 될 때도 안 될 때도
#    있었다(2026-08-22 실물 QA). 지금은 이벤트로 불렸을 때만 기다리고,
#    무관한 파일이면 바로 빠진다.
t_start "activity 의 이벤트 처리"
t_vault ev
t_config notes
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/init/prompts.sh"; . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
A="$DEVTRAIL_HOME/scripts/activity.sh"
t_file "activity.sh 생성" "$A"

# ⚠️ $1 은 날짜다. 파일 경로를 인자로 받으면 "잘못된 날짜 형식" 으로 죽는다.
t_contains "이벤트는 환경변수로 받는다" 'DEVTRAIL_EVENT_FILE' "$(cat "$A")"
t_not_contains "이벤트를 1번 인자로 받지 않는다" 'EVENT_FILE="${1:-}"' "$(cat "$A")"

# 무관한 파일이면 즉시 빠진다 — 안 그러면 노트 하나당 프로세스가 잠든다.
out=$(DEVTRAIL_EVENT_FILE="$T_VAULT/notes/전혀-다른-노트.md"       DEVTRAIL_ACTIVITY_WAIT=1 bash "$A" 2>&1)
t_eq "무관한 파일이면 아무 말 없이 끝" "" "$out"

# 셸커맨드 설정이 그 환경변수를 실제로 넘기는가 — 어긋나면 필터가 죽는다.
SC="$ROOT/templates/obsidian/shellcommands.json"
cmd=$(jq -r '.[] | select(.alias|test("자동")) | .platform_specific_commands.default' "$SC")
t_contains "셸커맨드가 이벤트 파일을 넘긴다" "DEVTRAIL_EVENT_FILE" "$cmd"
t_contains "Obsidian 변수를 쓴다" "event_file_path" "$cmd"

# ⚠️ Shell commands 는 변수 값을 셸용으로 이스케이프해서 넣는다(\/Users\/...).
#    우리가 큰따옴표로 다시 감싸면 역슬래시가 값에 남아 경로가 틀어지고,
#    필터가 항상 '다른 파일' 로 판정해 자동 삽입이 영영 안 돈다.
#    감싸지 않으면 셸이 이스케이프를 풀어 공백·괄호까지 안전하다.
t_not_contains "이벤트 변수를 따옴표로 감싸지 않는다" \
  'DEVTRAIL_EVENT_FILE="{{event_file_path' "$cmd"

# 실제로 셸이 이스케이프를 풀어 원래 경로가 되는지 — 규칙을 말로만 두지 않는다.
esc='\/tmp\/my\ note\ \(1\).md'
t_eq "이스케이프된 경로가 원래대로 풀린다" "/tmp/my note (1).md" \
  "$(bash -c "V=$esc; printf '%s' \"\$V\"")"

# file-created 는 본문보다 먼저 온다. 쿨다운 뒤 한 번만 실행해야 한다.
t_eq "늦게 실행"     "true"  "$(jq -r '.[] | select(.alias|test("자동")) | .debounce.executeLate'  "$SC")"
t_eq "일찍 실행 안 함" "false" "$(jq -r '.[] | select(.alias|test("자동")) | .debounce.executeEarly' "$SC")"
t_ne "쿨다운이 0 이 아님" "0"   "$(jq -r '.[] | select(.alias|test("자동")) | .debounce.cooldownDuration' "$SC")"

# ── 웹 대시보드도 같은 해석기를 쓰는가 ──────────────────────────────────────
#
# ⚠️ 회귀: server.py 가 dirs.devlog 를 직접 읽고 기본값 "devlog" 를 자기가
#    갖고 있었다. 새로 설치한 볼트는 dirs 가 비어 있어서 화면이
#    <루트>/devlog/... 를 가리키며 "개발일지 없음" 이라고 말했다 —
#    파일은 개발/개발일지 에 멀쩡히 있었다(2026-08-22 실물 QA).
t_start "대시보드의 경로 해석"
SRV="$ROOT/templates/dashboard/server.py"
t_file "server.py" "$SRV"
t_contains "CLI 로 해석한다" 'DEVTRAIL_BIN, "path", "devlog", "--rel"' "$(cat "$SRV")"
# 자기만의 기본값을 가지면 화면과 실제가 갈린다.
t_not_contains "기본값을 품지 않는다" '"dirs.devlog", "devlog"' "$(cat "$SRV")"

# 실제로 해석되는지 — 문자열 검사만으로는 '부르지만 결과를 버리는' 코드를 못 잡는다.
t_vault dash
t_config notes
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/init/prompts.sh"; . "$ROOT/lib/init/write.sh"
  _init_render_scripts >/dev/null 2>&1
)
got=$(DEVTRAIL_BIN="$ROOT/bin/devtrail" DEVTRAIL_CONFIG="$T_CONFIG" python3 -c '
import os, sys, json, importlib.util
spec = importlib.util.spec_from_file_location("srv", sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0]]
spec.loader.exec_module(m)
cfg = json.load(open(os.environ["DEVTRAIL_CONFIG"], encoding="utf-8"))
print(m.devlog_path(cfg, "2026-08-22"))
' "$SRV" 2>/dev/null)
t_eq "개발일지 경로가 실제 폴더" "$T_VAULT/notes/개발/개발일지/2026-08-22 devlog.md" "$got"
t_not_contains "루트 바로 밑이 아니다" "notes/devlog/" "$got"

t_end
