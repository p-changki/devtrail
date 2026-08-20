#!/usr/bin/env bash
# DevTrail — 전체 검사.
#
#   ./tests/run.sh          전부
#   ./tests/run.sh fast     느린 것(swift 빌드) 빼고
#   ./tests/run.sh lint     문법·JSON·파이썬만        (CI: ubuntu)
#   ./tests/run.sh guard    이 저장소 고유의 함정만    (CI: ubuntu)
#
# CI 도 이 스크립트를 부른다. 로컬과 CI 가 같은 것을 돌려야
# "내 머신에서는 됐는데" 가 안 생긴다.
#
# ⚠️ 동작 테스트(path·augment·scan·undo)는 CI 에서 macOS 잡이 돌린다.
#    이 프로젝트가 실제로 설치되는 곳이 macOS 이고, bash 3.2 함정은
#    ubuntu 의 bash 5 에서 재현되지 않는다.
# ⚠️ macOS 기본 bash 3.2 에서 돌아야 한다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

GROUP="${1:-all}"
case "$GROUP" in
  all|fast|lint|guard) ;;
  *) echo "사용법: run.sh [all|fast|lint|guard]"; exit 2 ;;
esac

# 이 그룹에서 돌릴 것인가
_want() {
  case "$GROUP" in
    lint)  [ "$1" = lint ] ;;
    guard) [ "$1" = guard ] ;;
    *)     [ "$1" != swift ] || command -v swift >/dev/null 2>&1 ;;
  esac
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'
else
  G=''; R=''; B=''; D=''; Z=''
fi

FAILED=""
SKIPPED=0
# run <그룹> <이름> <명령…>
run() {
  local group="$1" name="$2"; shift 2
  if ! _want "$group"; then SKIPPED=$((SKIPPED + 1)); return 0; fi
  printf '\n%s━━ %s %s\n' "$B" "$name" "$Z"
  if "$@"; then
    printf '%s✓ %s%s\n' "$G" "$name" "$Z"
  else
    printf '%s✗ %s%s\n' "$R" "$name" "$Z"
    FAILED="${FAILED}${name}
"
  fi
}

# ── 정적 검사 ────────────────────────────────────────────────────────────────
check_shell() {
  bash -n bin/devtrail install.sh || return 1
  for f in lib/*.sh lib/merge/*.sh lib/init/*.sh \
           tests/*.sh tests/lib/*.sh templates/scripts/*.tmpl; do
    [ -e "$f" ] || continue
    bash -n "$f" || return 1
  done
  echo "  셸 문법 OK"
}

check_python() {
  python3 -m py_compile lib/gen/*.py templates/dashboard/server.py || return 1
  echo "  파이썬 OK"
}

check_json() {
  local f
  for f in preset/tree.json preset/profiles/*.json preset/obsidian/*.json \
           templates/devtrail.config.json templates/obsidian/shellcommands.json; do
    [ -e "$f" ] || continue
    jq -e . "$f" >/dev/null || { echo "  ❌ $f"; return 1; }
  done
  echo "  JSON OK"
}

# ── 이 프로젝트 고유의 함정 ──────────────────────────────────────────────────
#
# 둘 다 실제로 사고가 났던 것이다. 문법 검사로는 안 잡힌다.
check_bash32() {
  # macOS 기본 bash 3.2 는 한글의 첫 바이트를 변수명에 흡수해
  # "unbound variable" 로 죽는다. 중괄호로 감싸야 한다.
  #
  # ⚠️ 먼저 정규식 자체가 동작하는지 확인한다.
  #    [가-힣] 범위는 로케일을 탄다. C 로케일의 ubuntu 러너에서 이 범위가
  #    아무것도 못 맞추면 검사는 '통과'로 보이지만 실제로는 아무것도
  #    안 본 것이다 — 거짓 초록불이 가장 위험하다.
  if ! printf '%s\n' 'echo "$n개"' | grep -qE '\$[A-Za-z_][A-Za-z0-9_]*[가-힣]'; then
    echo "  ❌ 한글 정규식이 동작하지 않습니다 (로케일 문제)"
    echo "     LANG=${LANG:-unset} LC_ALL=${LC_ALL:-unset}"
    echo "     이대로면 검사가 통과해도 아무것도 지키지 못합니다."
    return 1
  fi
  #
  # 검사 대상에서 이 파일과 규약 문서를 뺀다 — 나쁜 예시를 드는 것은 정상이다.
  # scan-secrets.sh 도 같은 이유로 자신을 제외한다.
  local hits
  hits=$(git grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[가-힣]' \
         -- '*.sh' 'bin/devtrail' 'install.sh' 2>/dev/null \
         | grep -v '^tests/run\.sh:' | grep -v '^tests/lib/harness\.sh:' \
         | grep -vE ':[0-9]+:[[:space:]]*#')
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "  → 한글 앞 변수는 중괄호로: \"\${n}개\""
    return 1
  fi
  echo "  bash 3.2 한글 흡수 없음"
}

check_no_hardcoded_paths() {
  # 프리셋의 템플릿·허브·스킬에 볼트 경로가 박히면 사용자가 폴더명을 바꿀 때 깨진다.
  local hits
  hits=$(grep -rlE '창기/|"notes/개발' preset/templates preset/guides preset/learn 2>/dev/null)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  ❌ /'
    return 1
  fi
  echo "  경로 하드코딩 없음"
}

check_file_size() {
  # 400줄을 넘으면 분리를 검토한다. 600줄은 실패다.
  local over="" f n
  for f in lib/*.sh lib/merge/*.sh lib/init/*.sh lib/gen/*.py bin/devtrail; do
    [ -e "$f" ] || continue
    n=$(wc -l < "$f" | tr -d ' ')
    if [ "$n" -gt 600 ]; then
      printf '  ❌ %-28s %s줄 (600 초과)\n' "$f" "$n"
      over="y"
    elif [ "$n" -gt 400 ]; then
      printf '  %s⚠️  %-28s %s줄 (분리 검토)%s\n' "$D" "$f" "$n" "$Z"
    fi
  done
  [ -z "$over" ] && echo "  파일 길이 OK"
  [ -z "$over" ]
}

check_version() {
  # 버전은 VERSION 파일 하나에만 있어야 한다.
  # 두 곳에 박아두면 릴리스할 때 한쪽을 빠뜨린다 — 실제로 그랬다.
  [ -f VERSION ] || { echo "  ❌ VERSION 파일이 없다"; return 1; }

  local v; v=$(tr -d ' \n' < VERSION)
  case "$v" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "  ❌ 유의적 버전이 아니다: $v"; return 1 ;;
  esac

  local hard
  hard=$(git grep -nE 'VERSION="[0-9]+\.[0-9]+' -- 'bin' 'lib' 'app' 2>/dev/null)
  if [ -n "$hard" ]; then
    printf '%s\n' "$hard" | sed 's/^/  ❌ 하드코딩: /'
    return 1
  fi

  # CLI 가 내는 값과 파일이 같아야 한다
  local cli; cli=$(./bin/devtrail version 2>/dev/null | awk '{print $2}')
  [ "$cli" = "$v" ] || { echo "  ❌ devtrail version=$cli · VERSION=$v"; return 1; }

  # CHANGELOG 에 이 버전이 있어야 한다
  grep -q "^## \[$v\]" CHANGELOG.md 2>/dev/null \
    || { echo "  ❌ CHANGELOG 에 [$v] 항목이 없다"; return 1; }

  echo "  버전 $v · 단일 출처 · CHANGELOG 있음"
}

check_migrations() {
  # DT_SCHEMA 를 올려놓고 마이그레이션 파일을 안 만들면,
  # 사용자에게 "올려야 한다"고 말해놓고 아무것도 하지 않는다.
  local want n f
  want=$(grep -E '^DT_SCHEMA=' lib/migrate.sh | head -1 | cut -d= -f2)
  case "$want" in ''|*[!0-9]*) echo "  ❌ DT_SCHEMA 를 읽을 수 없다"; return 1 ;; esac

  n=2   # v1 은 최초 스키마라 마이그레이션이 없다
  while [ "$n" -le "$want" ]; do
    f=$(ls lib/migrations/$(printf '%03d' "$n")-*.sh 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "  ❌ v${n} 마이그레이션 파일이 없다"; return 1; }
    grep -q "^_mg_$(printf '%03d' "$n")()" "$f" \
      || { echo "  ❌ $f 에 _mg_$(printf '%03d' "$n")() 가 없다"; return 1; }
    grep -q "^_mg_$(printf '%03d' "$n")_why=" "$f" \
      || { echo "  ❌ $f 에 설명(_why)이 없다"; return 1; }
    n=$((n + 1))
  done
  echo "  스키마 v${want} · 마이그레이션 짝 맞음"
}

# ── 실행 ─────────────────────────────────────────────────────────────────────
# 정적 — 어느 OS 에서나 같은 답이 나온다
run lint  "셸 문법"        check_shell
run lint  "파이썬"         check_python
run lint  "JSON"          check_json

# 이 저장소 고유의 함정 — 문법 검사로는 안 잡힌다
run guard "bash 3.2"      check_bash32
run guard "경로 하드코딩"   check_no_hardcoded_paths
run guard "파일 길이"      check_file_size
run guard "버전"          check_version
run guard "마이그레이션"   check_migrations
run guard "시크릿"         ./tests/scan-secrets.sh
run guard "스킬 규약"      ./tests/check-skills.sh

# 동작 — 실제로 실행해 봐야 아는 것
run behav "path"          ./tests/test-path.sh
run behav "augment"       ./tests/test-augment.sh
run behav "scan"          ./tests/test-scan.sh
run behav "undo·마이그레이션" ./tests/test-undo.sh

[ "$GROUP" = all ] && run swift "swift 빌드" \
  sh -c 'cd app && swift build -c release 2>&1 | tail -1' 

# ── 결과 ─────────────────────────────────────────────────────────────────────
echo
if [ -n "$FAILED" ]; then
  printf '%s실패:%s\n' "$R" "$Z"
  printf '%s' "$FAILED" | sed 's/^/  /'
  exit 1
fi
if [ "$SKIPPED" -gt 0 ]; then
  printf '%s전부 통과%s %s(%s 그룹 · %s개 건너뜀)%s\n' "$G" "$Z" "$D" "$GROUP" "$SKIPPED" "$Z"
else
  printf '%s전부 통과%s\n' "$G" "$Z"
fi
