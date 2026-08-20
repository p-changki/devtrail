#!/usr/bin/env bash
# DevTrail — 전체 검사.
#
#   ./tests/run.sh          전부
#   ./tests/run.sh fast     느린 것(swift 빌드) 빼고
#
# CI 도 이 스크립트를 부른다. 로컬과 CI 가 같은 것을 돌려야
# "내 머신에서는 됐는데" 가 안 생긴다.
#
# ⚠️ macOS 기본 bash 3.2 에서 돌아야 한다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

FAST=0
[ "${1:-}" = "fast" ] && FAST=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'
else
  G=''; R=''; B=''; D=''; Z=''
fi

FAILED=""
run() {
  local name="$1"; shift
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

# ── 실행 ─────────────────────────────────────────────────────────────────────
run "셸 문법"        check_shell
run "파이썬"         check_python
run "JSON"          check_json
run "bash 3.2"      check_bash32
run "경로 하드코딩"   check_no_hardcoded_paths
run "파일 길이"      check_file_size
run "시크릿"         ./tests/scan-secrets.sh
run "스킬 규약"      ./tests/check-skills.sh
run "path"          ./tests/test-path.sh
run "augment"       ./tests/test-augment.sh
run "scan"          ./tests/test-scan.sh

if [ "$FAST" = 0 ] && command -v swift >/dev/null 2>&1; then
  run "swift 빌드" sh -c 'cd app && swift build -c release 2>&1 | tail -1'
fi

# ── 결과 ─────────────────────────────────────────────────────────────────────
echo
if [ -n "$FAILED" ]; then
  printf '%s실패:%s\n' "$R" "$Z"
  printf '%s' "$FAILED" | sed 's/^/  /'
  exit 1
fi
printf '%s전부 통과%s\n' "$G" "$Z"
