#!/usr/bin/env bash
# DevTrail — 스킬 규약 검사.
#
# 스킬은 문서라 문법 검사가 없다. 대신 규약을 기계로 확인한다.
#   1) name 이 devtrail-<폴더명> 과 일치
#   2) description 존재
#   3) devtrail path 로 경로를 조회
#   4) 경로 하드코딩 없음 — 단, '쓰지 마세요' 같은 금지 설명은 제외
#
# ⚠️ 한글이 뒤따르는 변수는 반드시 중괄호로 감싼다: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

SRC="skills"
[ -d "$SRC" ] || { echo "스킬 폴더 없음: $SRC"; exit 0; }

fails=0
count=0

for d in "$SRC"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  f="$d/SKILL.md"
  count=$((count + 1))

  if [ ! -f "$f" ]; then
    echo "❌ ${name}: SKILL.md 없음"
    fails=$((fails + 1))
    continue
  fi

  grep -q "^name: devtrail-${name}\$" "$f" \
    || { echo "❌ ${name}: name 이 'devtrail-${name}' 이 아님"; fails=$((fails + 1)); }

  grep -q '^description: ' "$f" \
    || { echo "❌ ${name}: description 없음"; fails=$((fails + 1)); }

  grep -q 'devtrail path' "$f" \
    || { echo "❌ ${name}: devtrail path 조회가 없음"; fails=$((fails + 1)); }

  # 하드코딩 검사 — 금지를 설명하는 줄은 뺀다.
  # "~/Desktop/worklogs 에 쓰지 마세요" 처럼 나쁜 예시를 드는 건 정상이다.
  bad=$(grep -nE '창기/|"notes/|/Users/[a-z]|Desktop/worklogs' "$f" \
        | grep -vE '마세요|말 것|안 된다|아니다|예전|원본은|하지 마' || true)
  if [ -n "$bad" ]; then
    echo "❌ ${name}: 경로 하드코딩"
    printf '%s\n' "$bad" | sed 's/^/      /'
    fails=$((fails + 1))
  fi
done

echo
if [ "$fails" -gt 0 ]; then
  echo "❌ ${fails}건 — 스킬 ${count}종 검사"
  exit 1
fi
echo "✅ 스킬 ${count}종 규약 준수"
