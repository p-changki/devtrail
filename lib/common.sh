#!/usr/bin/env bash
# DevTrail — shared helpers.
# Sourced by every subcommand. No side effects beyond variable definitions.
#
# ⚠️ macOS 기본 bash는 3.2다. 지켜야 할 두 가지:
#
#   1) mapfile · declare -A 등 bash 4 기능 금지.
#   2) 한글이 뒤따르는 변수는 반드시 중괄호로 감싼다.
#        "${n}개"  (O)      "$n개"  (X)
#      bash 3.2는 한글의 첫 바이트를 변수명에 흡수해 `n<0xEA>: unbound variable`
#      로 죽는다. set -u 와 겹치면 그 자리에서 스크립트가 끝난다.
#      실제로 doctor 의 요약 줄이 '문제를 발견했을 때만' 죽고 있었다.

set -uo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
DEVTRAIL_ROOT="${DEVTRAIL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEVTRAIL_HOME="${DEVTRAIL_HOME:-$HOME/.devtrail}"
CONFIG_FILE="${DEVTRAIL_CONFIG:-$DEVTRAIL_HOME/devtrail.config.json}"

# ── Output ───────────────────────────────────────────────────────────────────
#
# 색은 의미로 부른다. docs/design-tokens.md 가 단일 출처다.
#
# ⚠️ 16색만 쓴다. 24비트(\033[38;2;r;g;bm)는 SSH · tmux · 구형 터미널에서 깨진다.
# ⚠️ 색만으로 정보를 전달하지 않는다. 아래 함수들이 기호를 함께 낸다 —
#    색맹 사용자와 NO_COLOR 환경에서도 구분돼야 한다.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_MUTED=$'\033[2m'                       # ink-muted
  C_SUCCESS=$'\033[32m'                    # accent · success
  C_WARNING=$'\033[33m'                    # warning
  C_DANGER=$'\033[31m'                     # danger
  C_INFO=$'\033[34m'                       # info
else
  C_RESET=''; C_BOLD=''
  C_MUTED=''; C_SUCCESS=''; C_WARNING=''; C_DANGER=''; C_INFO=''
fi

# 이전 이름. 외부 스크립트가 참조할 수 있어 남겨두지만 새로 쓰지 않는다.
C_DIM="$C_MUTED"; C_GREEN="$C_SUCCESS"; C_YELLOW="$C_WARNING"
C_RED="$C_DANGER"; C_BLUE="$C_INFO"

info()  { printf '%s\n' "$*"; }
step()  { printf '%s▶%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()    { printf '%s✅%s %s\n' "$C_SUCCESS" "$C_RESET" "$*"; }
# ⚠️ 경고·오류는 stderr 로 낸다.
#
#    stdout 으로 내면 명령 치환에 갇힌다:
#
#      spec=$(sp_read "$file")    # 안에서 die 하면 메시지가 $() 에 삼켜진다
#
#    스펙이 잘못돼도 화면에 아무것도 나오지 않았다(2026-08-22 실측).
#    사용자는 무엇이 틀렸는지 알 길이 없었다.
#
#    ⚠️ 성공 출력(ok · info · step · dim)은 stdout 그대로 둔다.
#       $(devtrail path devlog) 처럼 값으로 받는 곳이 있다.
warn()  { printf '%s⚠️ %s %s\n' "$C_WARNING" "$C_RESET" "$*" >&2; }
fail()  { printf '%s❌%s %s\n' "$C_DANGER" "$C_RESET" "$*" >&2; }
dim()   { printf '%s%s%s\n' "$C_MUTED" "$*" "$C_RESET"; }
die()   { fail "$*"; exit 1; }

# ── Config access ────────────────────────────────────────────────────────────
# cfg <jq-path> [default]
#   cfg '.vault.path'
#   cfg '.github.user' ''
# ⚠️ jq의 `//` 를 쓰면 안 된다. jq에서 false 는 falsy라 `false // empty` 가
#    빈값을 반환하고, 결국 기본값으로 폴백한다. 그러면 사용자가 false 로 끈
#    설정(backup.enabled 등)이 전부 무시된다 — 2026-08-20 실사용 검증에서
#    백업을 껐는데도 실행되는 것으로 발견.
#    null 인지만 검사하고, false 는 "false" 문자열로 그대로 넘긴다.
cfg() {
  local path="$1" default="${2-}"
  [ -f "$CONFIG_FILE" ] || { printf '%s' "$default"; return 0; }
  local v
  v=$(jq -r "($path) | if . == null then empty else tostring end" "$CONFIG_FILE" 2>/dev/null) || v=''
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$default"
}

# cfg_array <jq-path> — one item per line
cfg_array() {
  [ -f "$CONFIG_FILE" ] || return 0
  jq -r "${1}[]? // empty" "$CONFIG_FILE" 2>/dev/null
}

config_exists() { [ -f "$CONFIG_FILE" ]; }

require_config() {
  config_exists || die "$(L "설정이 없습니다. 먼저 'devtrail init' 을 실행하세요." \
          "No config yet. Run 'devtrail init' first.") ($CONFIG_FILE)"
}

# ── Vault path resolution ────────────────────────────────────────────────────
# 볼트 경로는 설정에 절대경로로 저장된다. root는 볼트 안의 최상위 폴더명.
vault_path()  { cfg '.vault.path'; }
# 루트 폴더는 비어 있을 수 있다 — 볼트 최상위에 바로 노트를 두는 사람이 있다.
# 그때 "$p/" 처럼 슬래시가 남으면 아래 경로들이 전부 // 로 어긋난다.
vault_root() {
  local p r; p=$(vault_path); r=$(cfg '.vault.root')
  if [ -n "$r" ]; then printf '%s/%s' "${p%/}" "$r"; else printf '%s' "${p%/}"; fi
}
# 볼트 기준 상대경로 결합. Dataview FROM 에 쓰는 값이다.
# 루트가 비면 앞에 슬래시가 붙어 FROM "/Daily" 가 되고, Dataview 는 이걸 못 찾는다.
vault_rel() {
  local r; r=$(cfg '.vault.root')
  if [ -n "$r" ]; then printf '%s/%s' "$r" "$1"; else printf '%s' "$1"; fi
}

# dt_devlog_name <날짜> — 그 날짜의 개발일지 파일명.
#
# ⚠️ 이 기본값을 다른 곳에 두지 않는다. '{{DATE}} devlog.md' 가 생성 스크립트·
#    메뉴바 앱·snapshot 세 곳에 각자 있었고, 그중 하나만 바뀌면 "파일이 있는데
#    없다" 고 말하는 화면이 생긴다. 이 저장소는 dirs.devlog 로 같은 병을 네 번
#    고쳤다.
dt_devlog_name() {
  local d="$1" pat
  pat=$(cfg '.naming.devlog_file' '{{DATE}} devlog.md')
  printf '%s' "${pat//\{\{DATE\}\}/$d}"
}

# dt_dir <key> — 볼트 루트 기준 상대경로.
#   1) config 의 dirs.<key>        사용자가 채택한 경로가 최우선
#   2) preset/tree.json 의 path    프리셋 기본값
# 둘 다 없으면 빈 문자열이고, 그러면 호출부에서 "창기//devlog.md" 같은
# 경로가 만들어진다. 실제로 그렇게 나왔다 — 반드시 폴백을 둔다.
dt_dir() {
  local key="$1" v tree
  v=$(cfg ".dirs[\"$key\"]" '')
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  tree="${DEVTRAIL_TREE:-$DT_PRESET/tree.json}"
  [ -f "$tree" ] || return 0
  # 언어에 따라 path 또는 path_en 을 고른다.
  #
  # ⚠️ key 는 언어와 무관하다. 라우팅·허브·스킬이 전부 key 로 동작하므로
  #    사용자가 언어를 바꿔도 자동 분류가 깨지지 않는다.
  # ⚠️ path_en 이 없으면 path 로 떨어진다 — 이미 영어인 폴더(Frontend 등)는
  #    번역을 두지 않았다.
  jq -r --arg k "$key" --argjson en "$([ "$(dt_lang)" = en ] && echo true || echo false)" '
    def pick: if $en then (.path_en // .path) else .path end;
    [ .folders[] | . as $p
      | ({key: $p.key, path: ($p | pick)}),
        (($p.children // [])[] | {key: .key, path: (($p | pick) + "/" + (. | pick))}) ]
    | map(select(.key == $k)) | (.[0].path // empty)
  ' "$tree" 2>/dev/null
}

# 절대경로. 키가 해석되지 않으면 볼트 루트를 그대로 돌려준다(슬래시 안 붙임).
dt_path() {
  local rel; rel=$(dt_dir "$1")
  if [ -n "$rel" ]; then printf '%s/%s' "$(vault_root)" "$rel"; else vault_root; fi
}

dir_devlog()    { dt_path devlog; }
dir_weekly()    { dt_path weekly; }
dir_templates() { dt_path templates; }

# ── Dependency checks ────────────────────────────────────────────────────────
# ── JSON 조립 ────────────────────────────────────────────────────────────────
#
# ⚠️ init 전용이 아니다. 셋업 계획(setup plan)도 같은 변환을 쓴다.
#    init/write.sh 안에 두면 다른 곳에서 쓰려고 한 벌 더 만들게 된다.

# 개행 목록 → JSON 배열. 빈 입력은 [] 가 된다.
_dt_json_array() {
  printf '%s' "${1-}" | jq -R -s 'split("\n") | map(select(length > 0))'
}

# 개행 목록 → { "이름": "이름", ... } 항등 매핑.
# project_groups 는 '레포명 → 개발일지 섹션명' 이다. 기본은 레포명 그대로 쓰고,
# fe/be 로 나뉜 레포를 한 섹션에 모으고 싶으면 나중에 값만 바꾸면 된다.
_dt_json_identity() {
  printf '%s' "${1-}" \
    | jq -R -s 'split("\n") | map(select(length > 0)) | map({key: ., value: .}) | from_entries'
}

has() { command -v "$1" >/dev/null 2>&1; }

require_bins() {
  local missing=()
  for b in "$@"; do has "$b" || missing+=("$b"); done
  if [ ${#missing[@]} -gt 0 ]; then
    die "$(L "필수 도구 없음" "Missing required tools"): ${missing[*]}  ('devtrail doctor')"
  fi
}

# preset 자산이 있는 곳 (ADR 0006 M4-5).
#
# ⚠️ 왜 이런 우회가 필요한가 — 2026-08-24 실물 QA
#
#    preset 안에는 **한글 이름 파일 27개**가 있다(가이드·템플릿). 그런데
#    Finder 로 앱을 드래그하면 파일 이름이 **NFC → NFD 로 정규화**된다.
#    코드 서명은 NFC 이름을 봉인했으므로, 이름이 바뀌는 순간 macOS 는
#    "봉인된 파일이 없다" 로 보고 **"손상되었습니다"** 를 띄운다.
#
#    같은 바이너리 · 같은 195개 파일인데도 그렇다. 손상이 아니라 **이름
#    표기가 달라진 것**이다.
#
#    cp·ditto·rsync 는 NFC 를 보존해서 개발 중에는 한 번도 재현되지 않았다.
#    **사용자가 하는 방법(드래그)에서만** 깨졌다.
#
# ⚠️ 그래서 번들에는 `preset/` 대신 **`preset.tar` 하나**를 넣는다. 봉인되는
#    이름이 ASCII 하나뿐이면 정규화가 무엇이든 서명이 깨지지 않는다.
#    안의 이름은 tar 가 바이트 그대로 지킨다.
#
# ⚠️ 푸는 곳은 사용자 홈이다. 번들 안은 읽기 전용이고, 그래야 서명도 성하다.
dt_preset_dir() {
  # 1) 그냥 있으면 그것을 쓴다 (저장소 · git 설치본)
  [ -d "$DEVTRAIL_ROOT/preset" ] && { printf '%s' "$DEVTRAIL_ROOT/preset"; return 0; }

  # ⚠️ **zip 이다, tar 가 아니다.** macOS 의 bsdtar 는 푸는 과정에서 한글
  #    이름을 NFD 로 분해한다(실측). 그러면 서명은 지켜져도 **사용자 볼트에
  #    들어가는 노트 이름이 바뀐다.** `ditto -c -k` 로 만든 zip 은 NFC 를
  #    그대로 지킨다 — 확인하고 골랐다.
  local arc="$DEVTRAIL_ROOT/preset.zip"
  [ -f "$arc" ] || { printf '%s' "$DEVTRAIL_ROOT/preset"; return 1; }

  # 2) 내용으로 캐시 이름을 정한다 — 앱이 바뀌면 자동으로 새 디렉터리다.
  #    버전 문자열을 쓰면 같은 버전에서 자산만 바뀔 때 낡은 것을 계속 쓴다.
  local sum dst
  sum=$(shasum -a 256 "$arc" 2>/dev/null | cut -c1-16)
  [ -n "$sum" ] || { printf '%s' "$DEVTRAIL_ROOT/preset"; return 1; }
  dst="$DEVTRAIL_HOME/assets/preset-$sum"

  [ -d "$dst" ] && { printf '%s' "$dst"; return 0; }

  # 3) 원자적으로 푼다. 반쯤 풀린 디렉터리를 다음 사람이 진짜라고 읽으면 안 된다.
  local tmp
  tmp="$dst.tmp.$$"
  rm -rf "$tmp"
  mkdir -p "$tmp" || { printf '%s' "$DEVTRAIL_ROOT/preset"; return 1; }
  if ditto -x -k "$arc" "$tmp" 2>/dev/null; then
    mv "$tmp" "$dst" 2>/dev/null || rm -rf "$tmp"
  else
    rm -rf "$tmp"
  fi
  [ -d "$dst" ] && printf '%s' "$dst" || printf '%s' "$DEVTRAIL_ROOT/preset"
}

# ⚠️ 여기서 **한 번만** 정한다. 35곳이 각자 부르면 그 자체가 두 번째 출처다.
#
#    저장소·git 설치본에는 preset/ 이 그대로 있으므로 값만 넣고 끝난다 —
#    번들일 때만 압축을 푼다.
DT_PRESET=$(dt_preset_dir)
export DT_PRESET

# 생성기를 돌릴 수 있는가 (ADR 0006 D7-B).
#
# ⚠️ **python3 을 무조건 요구하지 않는다.** 생성기 8종은 Swift 헬퍼로
#    이관됐다(M2·M3). 헬퍼가 있으면 python3 은 폴백일 뿐인데, 가드가 계속
#    요구하면 **돌 수 있는 기능을 막는다** — 사용자에게는 그냥 버그다.
#
# ⚠️ 헬퍼가 없을 때의 python3 폴백과 안내는 그대로 둔다. 없앤 것은
#    "헬퍼가 있는데도 막는" 경우뿐이다.
require_gen() {
  dt_helper >/dev/null 2>&1 && return 0
  has python3 && return 0
  die "$(L "생성기가 없습니다 — Swift 헬퍼도 python3 도 없습니다" \
          "No generator — neither the Swift helper nor python3 is available"): ('devtrail doctor')"
}

# ── Misc ─────────────────────────────────────────────────────────────────────
# 날짜(BSD/GNU 양쪽 지원). today_offset -1 → 어제
today_offset() {
  local off="${1:-0}"
  if date -v-1d >/dev/null 2>&1; then
    if [ "$off" -lt 0 ]; then date -v"${off}d" +%Y-%m-%d; else date -v"+${off}d" +%Y-%m-%d; fi
  else
    date -d "$off days" +%Y-%m-%d
  fi
}

confirm() {
  local prompt="${1:-계속할까요?}" reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ── 생성기 통로 ──────────────────────────────────────────────────────────────
#
# ⚠️ 생성기를 부르는 곳은 **여기 하나**다. 호출부 11곳이 각자 python3 를
#    부르면, 헬퍼로 옮길 때 하나를 빠뜨린다 — 이 저장소가 dirs.devlog 로
#    네 번 겪은 병이다.
#
# ⚠️ 헬퍼가 없으면 **python3 로 떨어진다.** 이관이 끝나기 전에도 저장소가
#    그대로 돌고, 기존 Git 설치형 사용자는 아무것도 잃지 않는다 (ADR 0006).
#
# ⚠️ 어느 쪽을 썼는지 조용히 넘기지 않는다. `devtrail doctor` 가 말한다.

# 헬퍼 실행 파일. 없으면 빈 문자열.
dt_helper() {
  local p
  # 1) 테스트·개발용 명시 지정
  p="${DT_HELPER_OVERRIDE:-}"
  [ -n "$p" ] && [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  # 2) .app 번들 안 (DMG 설치본)
  p="$DEVTRAIL_ROOT/../Helpers/devtrail-helper"
  [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  # 3) 저장소의 빌드 산출물 (개발 중)
  for p in "$DEVTRAIL_ROOT/app/.build/release/DevTrailHelper" \
           "$DEVTRAIL_ROOT/app/.build/debug/DevTrailHelper"; do
    [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# 번들 안에서 돌 때, 함께 나온 도구를 먼저 쓴다.
#
# ⚠️ 왜 PATH 인가 (ADR 0006 M4)
#
#    jq 는 40개 파일 **139곳**에서 맨몸으로 불린다. 호출부를 하나씩 고치면
#    다음에 새로 쓰는 곳에서 또 빠진다 — 이 저장소가 dirs.devlog 기본값으로
#    네 번 겪은 결함이다. 진입점 한 곳에서 PATH 를 세우고 끝낸다.
#
# ⚠️ **앞에** 붙인다. DMG 로 받은 사용자에게는 우리가 해시를 못 박고 실제로
#    돌려 본 그 버전이 돌아야 한다. 뒤에 붙이면 기계마다 다른 jq 가 잡힌다.
#
# ⚠️ 번들이 아닐 때는 아무것도 하지 않는다. 개발 중에는 각자의 jq 를 쓴다.
dt_bundled_bin_dir() {
  local p="$DEVTRAIL_ROOT/../Helpers"
  [ -d "$p" ] && [ -x "$p/jq" ] && { (cd "$p" && pwd); return 0; }
  return 1
}

_dt_use_bundled_bins() {
  local d
  d=$(dt_bundled_bin_dir) || return 0
  case ":$PATH:" in
    *":$d:"*) return 0 ;;   # 이미 있다 — 두 번 붙이지 않는다
  esac
  PATH="$d:$PATH"
  export PATH
}
_dt_use_bundled_bins

# 하위 명령 → python 스크립트. 폴백에 쓴다.
#
# ⚠️ 이 표가 곧 "무엇이 이관됐는가" 다. 헬퍼에 없는 명령을 여기 적으면
#    폴백이 영원히 도는데 아무도 모른다 — 새 명령을 더할 때 양쪽을 함께 본다.
_dt_gen_script() {
  case "$1" in
    gen-smartenv) printf '%s' "$DEVTRAIL_ROOT/lib/gen/smartenv.py" ;;
    gen-anm)      printf '%s' "$DEVTRAIL_ROOT/lib/gen/anm.py" ;;
    gen-hotkeys)  printf '%s' "$DEVTRAIL_ROOT/lib/gen/hotkeys.py" ;;
    gen-hub)      printf '%s' "$DEVTRAIL_ROOT/lib/gen/hub.py" ;;
    gen-hubs)     printf '%s' "$DEVTRAIL_ROOT/lib/gen/hubs.py" ;;
    gen-scan)     printf '%s' "$DEVTRAIL_ROOT/lib/gen/scan.py" ;;
    gen-snapshot) printf '%s' "$DEVTRAIL_ROOT/lib/snapshot.py" ;;
    *) return 1 ;;
  esac
}

# dt_gen <하위명령> [인자…]
#
# 헬퍼가 있으면 헬퍼, 없으면 python3. 표준입출력·종료코드를 그대로 전달한다.
dt_gen() {
  local sub="$1"; shift
  local helper script
  if helper=$(dt_helper); then
    "$helper" "$sub" "$@"
    return $?
  fi
  script=$(_dt_gen_script "$sub") || {
    printf '%s\n' "알 수 없는 생성기: $sub" >&2
    return 2
  }
  python3 "$script" "$@"
}

# 언어. dt_dir 이 dt_lang 을 쓰므로 저널보다 먼저 읽는다.
# shellcheck source=lib/i18n.sh
. "$DEVTRAIL_ROOT/lib/i18n.sh"

# ⚠️ 해결된 언어를 **자식 프로세스에 물려준다.** 여기 한 곳에서만 한다.
#
#    python 생성기들은 DEVTRAIL_LANG 환경변수로만 언어를 안다 (lib/gen/i18n.py).
#    설정 파일을 인자로 받지만 거기서 lang 을 읽지 않는다. 그런데 이 변수를
#    export 하던 곳은 init.sh 와 setup/spec.sh **둘뿐**이었다.
#
#    그래서 `devtrail obsidian apply` 처럼 그 둘을 안 거치는 경로에서는
#    셸은 설정대로 en 인데 python 은 기본값 ko 로 떨어졌다. 영어 사용자의
#    Templater 설정에 templates_folder 가 "템플릿" 으로 박혔다 — 그 볼트에
#    없는 폴더다. 2026-08-23 에 골든 계약 테스트의 변이 검증에서 드러났다.
#
#    호출부 12곳에 흩뿌리지 않는다. 하나를 빠뜨리면 같은 병이 재발한다.
#    dt_lang 은 이미 DEVTRAIL_LANG 을 1순위로 읽으므로 멱등이다 —
#    바깥에서 넘긴 일회성 지정은 그대로 존중된다.
DEVTRAIL_LANG="$(dt_lang)"
export DEVTRAIL_LANG

# 변경 저널. 모든 명령이 쓸 수 있어야 하므로 여기서 읽어들인다.
# common.sh 의 die/warn/dim/vault_path 를 쓰므로 반드시 파일 끝에서 부른다.
# shellcheck source=lib/journal.sh
. "$DEVTRAIL_ROOT/lib/journal.sh"
