#!/usr/bin/env bash
# DevTrail — 시크릿·개인정보 스캐너
#
# 공개 저장소에 API 키나 개인 경로가 섞여 들어가는 것을 막는다.
# pre-commit 훅으로도 쓰고, CI에서도 쓴다.
#
#   ./tests/scan-secrets.sh            # 추적 대상 전체
#   ./tests/scan-secrets.sh --staged   # 스테이징된 것만 (pre-commit)
#
# ⚠️ macOS 기본 bash는 3.2다. mapfile/declare -A 등 bash 4 기능을 쓰면
#    스크립트가 깨지면서도 exit 0으로 "통과"해버린다(2026-08-20 실제 발생).
#    이 파일은 bash 3.2에서 동작해야 한다.
#
# ⚠️ 한글이 뒤따르는 변수는 반드시 중괄호로 감싼다: "${N}개"  (O)  "$N개" (X)
#    bash 3.2는 한글의 첫 바이트를 변수명에 흡수해 "unbound variable"로 죽는다.
#    스캔을 한 건도 못 한 채 종료하는데, 게이트가 도는 것처럼 보인다(실제 발생).

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

STAGED=0
[ "${1:-}" = "--staged" ] && STAGED=1

if [ "$STAGED" = 1 ]; then
  FILE_LIST=$(git diff --cached --name-only --diff-filter=ACM)
else
  FILE_LIST=$(git ls-files)
fi

# 자기 자신과 문서는 패턴 예시를 담고 있으므로 제외한다.
FILE_LIST=$(printf '%s\n' "$FILE_LIST" | grep -vE '^(tests/scan-secrets\.sh|\.gitignore|docs/)' || true)

if [ -z "$FILE_LIST" ]; then
  echo "검사할 파일 없음"
  exit 0
fi

FILE_COUNT=$(printf '%s\n' "$FILE_LIST" | wc -l | tr -d ' ')

# ── 패턴 ─────────────────────────────────────────────────────────────────────
# 실제 키 형식만 잡는다. 변수 참조(${VAR}, {{VAR}})는 정상이므로 제외한다.
#
# ⚠️ 직접 관리하는 정규식 목록은 반드시 뒤처진다. 실제로 초기 버전은
#    현행 OpenAI(sk-proj-)·fine-grained PAT(github_pat_)·AWS(AKIA)를
#    전부 놓쳤다. 규모가 커지면 gitleaks/trufflehog 룰셋 위임을 검토할 것.
SECRET_PATTERNS='
ctx7sk-[A-Za-z0-9_-]{8,}
gh[pousr]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{30,}
sk-[A-Za-z0-9]{20,}
sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}
sk-ant-[A-Za-z0-9_-]{20,}
AIza[0-9A-Za-z_-]{30,}
AKIA[0-9A-Z]{16}
ASIA[0-9A-Z]{16}
glpat-[A-Za-z0-9_-]{20,}
lin_api_[A-Za-z0-9]{20,}
xox[baprs]-[A-Za-z0-9-]{10,}
dop_v1_[a-f0-9]{64}
-----BEGIN [A-Z ]*PRIVATE KEY-----
'

# 개인정보: 이 저장소는 특정인의 세팅에서 추출됐으므로 잔재가 남기 쉽다.
#
# 'com~apple~CloudDocs'는 패턴에 넣지 않는다 — 이 도구가 iCloud 백엔드를
# 감지·제안하려면 정당하게 필요한 문자열이고, 실제 위험인 하드코딩된 홈 경로는
# 아래 /Users/<이름>/ 패턴이 이미 잡는다. 중복으로 넣으면 오탐만 늘어
# 스캐너를 무시하게 만든다.
PERSONAL_PATTERNS='
/Users/[a-z][a-z0-9._-]+/
'

fails=0

scan() {
  kind="$1"; pat="$2"
  hits=""
  # bash 3.2 호환: mapfile 대신 while-read
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    found=$(grep -HnE "$pat" "$f" 2>/dev/null) || true
    [ -n "$found" ] && hits="${hits}${found}
"
  done <<EOF
$FILE_LIST
EOF

  if [ -n "$hits" ]; then
    echo "❌ [$kind] $pat"
    printf '%s' "$hits" \
      | sed -E 's/(ctx7sk-|gh[pousr]_|sk-|AIza|lin_api_)[A-Za-z0-9_-]*/\1<REDACTED>/g' \
      | sed 's/^/     /'
    fails=$((fails + 1))
  fi
}

echo "▶ 시크릿 스캔 (${FILE_COUNT}개 파일)"
while IFS= read -r p; do
  [ -n "$p" ] && scan SECRET "$p"
done <<EOF
$SECRET_PATTERNS
EOF

echo "▶ 개인정보 스캔"
while IFS= read -r p; do
  [ -n "$p" ] && scan PERSONAL "$p"
done <<EOF
$PERSONAL_PATTERNS
EOF

if [ "$fails" -gt 0 ]; then
  echo
  echo "❌ ${fails}개 패턴 적중 — 커밋을 중단합니다."
  echo "   변수 참조(\${VAR} 또는 {{VAR}})로 바꾸거나 .gitignore에 추가하세요."
  exit 1
fi

echo "✅ 깨끗합니다 (${FILE_COUNT}개 파일 검사)"
