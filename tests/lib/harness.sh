#!/usr/bin/env bash
# DevTrail — 테스트 하네스.
#
# 외부 의존 없이 도는 최소한의 어서션 모음이다. bats 같은 걸 쓰지 않는 이유는
# 기여자가 추가 설치 없이 바로 돌릴 수 있어야 하기 때문이다.
#
# ⚠️ macOS 기본 bash 3.2 에서 돌아야 한다.
#    mapfile · declare -A 금지. 한글 앞 변수는 중괄호로 감싼다: "${n}개"
#
# 쓰는 법:
#   . "$(dirname "$0")/lib/harness.sh"
#   t_start "path 명령"
#   t_eq "설명" "기대값" "$(실제)"
#   t_end

# ── 상태 ─────────────────────────────────────────────────────────────────────
T_PASS=0
T_FAIL=0
T_NAME=""
T_FAILED_LINES=""

# 집계는 파일에 쌓는다.
#
# ⚠️ 서브셸 ( ... ) 안에서 T_FAIL 을 올려도 부모에는 남지 않는다.
#    변수만 쓰면 서브셸에서 실패한 테스트가 "통과"로 보고된다 —
#    실제로 그랬다(test-bootstrap.sh 가 3건 실패하고 exit 0 을 냈다).
#    파일은 서브셸을 넘어 살아남는다.
T_TALLY="${TMPDIR:-/tmp}/dt-tally-$$"
: > "$T_TALLY"

# ── 색 (harness 는 common.sh 에 의존하지 않는다) ─────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  T_G=$'\033[32m'; T_R=$'\033[31m'; T_D=$'\033[2m'; T_0=$'\033[0m'
else
  T_G=''; T_R=''; T_D=''; T_0=''
fi

# 부가 설명 한 줄. 단언이 아니라 **안내**다 — 건너뛴 이유 같은 것.
#
# ⚠️ 여기 없으면 안 된다. dim 은 lib/common.sh 의 함수라 CLI 안에서만
#    산다. 테스트 파일들이 그걸 모르고 불러 왔고, 5개 파일에서
#    `dim: command not found` 가 나면서 **그 안내가 통째로 사라졌다** —
#    "건너뜀" 이라고 말하려던 자리가 조용해졌다는 뜻이다.
#    2026-08-23 에 stderr 게이트가 잡았다.
dim() { printf '%s\n' "$*"; }

t_start() {
  T_NAME="$1"
  printf '\n%s▶%s %s\n' "$T_D" "$T_0" "$T_NAME"
}

_t_ok()   {
  T_PASS=$((T_PASS + 1))
  printf 'P\n' >> "$T_TALLY"
  printf '  %s✓%s %s\n' "$T_G" "$T_0" "$1"
}
_t_bad()  {
  T_FAIL=$((T_FAIL + 1))
  printf 'F\t%s › %s\n' "$T_NAME" "$1" >> "$T_TALLY"
  printf '  %s✗%s %s\n' "$T_R" "$T_0" "$1"
  shift
  for line in "$@"; do printf '      %s\n' "$line"; done
}

# ── 어서션 ───────────────────────────────────────────────────────────────────

# t_eq <설명> <기대> <실제>
t_eq() {
  if [ "$2" = "$3" ]; then _t_ok "$1"
  else _t_bad "$1" "기대: $2" "실제: $3"; fi
}

# t_ne <설명> <기대하지 않는 값> <실제>
t_ne() {
  if [ "$2" != "$3" ]; then _t_ok "$1"
  else _t_bad "$1" "이 값이 아니어야 함: $2"; fi
}

# t_contains <설명> <부분문자열> <전체>
t_contains() {
  # ⚠️ 빈 바늘은 무엇에나 들어 있다 — 단언이 공허하게 통과한다.
  #    2026-08-22 에 실제로 그랬다: 테스트가 CLI 전용 함수 L 을 불러
  #    "command not found" 를 내면서도 초록이었다.
  if [ -z "$2" ]; then
    _t_bad "$1" "찾을 문자열이 비어 있습니다 — 단언이 아무것도 검사하지 않습니다"
    return
  fi
  case "$3" in
    *"$2"*) _t_ok "$1" ;;
    *) _t_bad "$1" "포함해야 함: $2" "실제: $(printf '%s' "$3" | head -c 200)" ;;
  esac
}

# t_not_contains <설명> <부분문자열> <전체>
t_not_contains() {
  case "$3" in
    *"$2"*) _t_bad "$1" "포함하면 안 됨: $2" ;;
    *) _t_ok "$1" ;;
  esac
}

# t_exit <설명> <기대 종료코드> <명령...>
t_exit() {
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then _t_ok "$desc"
  else _t_bad "$desc" "기대 종료코드: $want" "실제: $got"; fi
}

# t_file <설명> <경로>
t_file() {
  if [ -f "$2" ]; then _t_ok "$1"
  else _t_bad "$1" "파일이 없음: $2"; fi
}

# t_no_file <설명> <경로>
t_no_file() {
  if [ ! -f "$2" ]; then _t_ok "$1"
  else _t_bad "$1" "파일이 있으면 안 됨: $2"; fi
}

# t_dir <설명> <경로>
t_dir() {
  if [ -d "$2" ]; then _t_ok "$1"
  else _t_bad "$1" "디렉터리가 없음: $2"; fi
}

# t_json <설명> <파일>  — 유효한 JSON 인가
t_json() {
  if jq -e . "$2" >/dev/null 2>&1; then _t_ok "$1"
  else _t_bad "$1" "유효한 JSON 이 아님: $2"; fi
}

# ── 마무리 ───────────────────────────────────────────────────────────────────
t_end() {
  # 변수가 아니라 집계 파일을 읽는다 — 서브셸에서 난 실패도 여기 있다.
  local pass fail total
  pass=$(grep -c '^P$' "$T_TALLY" 2>/dev/null | tr -d ' ')
  fail=$(grep -c '^F' "$T_TALLY" 2>/dev/null | tr -d ' ')
  total=$(( ${pass:-0} + ${fail:-0} ))
  echo
  if [ "${fail:-0}" -gt 0 ]; then
    printf '%s✗ %s/%s 실패%s\n' "$T_R" "$fail" "$total" "$T_0"
    grep '^F' "$T_TALLY" 2>/dev/null | cut -f2- | sed 's/^/    /'
    rm -f "$T_TALLY"
    exit 1
  fi
  printf '%s✓ %s개 통과%s\n' "$T_G" "$total" "$T_0"
  rm -f "$T_TALLY"
  exit 0
}

# ── 격리된 볼트 만들기 ───────────────────────────────────────────────────────
#
# 테스트마다 새 볼트와 새 설정을 쓴다. 상태가 새면 다음 테스트가 왜 통과하는지
# 알 수 없어진다.
#
# t_vault <이름> [노트개수]  → 전역 T_VAULT · T_HOME · T_CONFIG 설정
t_vault() {
  local name="$1" notes="${2:-0}"
  T_VAULT="$T_TMP/$name"
  T_HOME="$T_TMP/${name}-home"
  T_CONFIG="$T_HOME/devtrail.config.json"
  mkdir -p "$T_VAULT" "$T_HOME"

  if [ "$notes" -gt 0 ]; then
    mkdir -p "$T_VAULT/Daily"
    local i=1
    while [ "$i" -le "$notes" ]; do
      printf -- '---\nstatus: done\n---\n# 일지\n' \
        > "$T_VAULT/Daily/2026-08-$(printf '%02d' "$i").md"
      i=$((i + 1))
    done
  fi

  export DEVTRAIL_HOME="$T_HOME" DEVTRAIL_CONFIG="$T_CONFIG"
}

# t_config <루트> [추가 jq 표현식]
#
# ⚠️ ${1:-notes} 로 쓰면 빈 문자열을 넘겨도 notes 가 된다.
#    빈 루트(볼트 최상위에 바로 두는 경우)를 테스트할 수 없어진다.
#    인자 개수로 판단한다.
t_config() {
  local root extra="${2:-.}"
  if [ $# -ge 1 ]; then root="$1"; else root="notes"; fi
  # ⚠️ version 과 lang 을 반드시 넣는다. 실제 v3 설정과 같은 모양이어야 한다.
  #    lang 이 없으면 dt_lang 이 로케일로 떨어져, CI 환경(LC_ALL=C.UTF-8)에서
  #    한국어 단언이 통째로 실패한다 — 실제로 그랬다.
  jq -n --arg v "$T_VAULT" --arg r "$root" '{
    version: 3,
    lang: "ko",
    vault: { backend: "local", path: $v, root: $r },
    dirs: {},
    headings: { issues_pr: "## Issues / PRs", worklog: "## Work log" },
    github: { user: "tester", repos: [], project_groups: {} },
    ai: { provider: "claude", summary_enabled: false },
    install: { mode: "new", modules: ["devlog"] }
  }' | jq "$extra" > "$T_CONFIG"
}
