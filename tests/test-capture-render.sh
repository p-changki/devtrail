#!/usr/bin/env bash
# 캡처 노트 렌더 계약 (ADR 0006 D7-B).
#
# ⚠️ 왜 따로 있나
#
#    D7-B 에서 이 렌더를 python 에서 awk 로 옮겼다. 옮기는 것 자체보다
#    **같은 결과를 내는가** 가 중요하다 — 이 함수의 출력이 곧 사용자 볼트에
#    저장되는 노트다. 틀리면 노트가 거짓을 말한다.
#
# ⚠️ 형식을 여기서 만들지 않는다. 볼트의 템플릿을 읽어 Templater 문법만
#    치환한다 — 그래야 Obsidian 에서 만든 노트와 같은 모양이 된다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh" >/dev/null 2>&1
# shellcheck source=lib/capturecmd.sh
. "$ROOT/lib/capturecmd.sh" >/dev/null 2>&1

D="2026-08-24"
N="2026-08-24 14:30"
TPL="$ROOT/preset/templates/ko/유튜브 노트 템플릿.md"

t_start "전제 — 템플릿이 있다"
t_eq "ko 템플릿" "yes" "$([ -f "$TPL" ] && echo yes || echo no)"
t_eq "en 템플릿" "yes" \
  "$([ -f "$ROOT/preset/templates/en/YouTube note.md" ] && echo yes || echo no)"
[ -f "$TPL" ] || { t_end; exit 0; }

OUT=$(_cap_render "$TPL" "영상 제목" "https://y/x" "채널명" "$D" "$N")

t_start "⚠️ 형식에 HH 가 있으면 시각, 없으면 날짜"
# ⚠️ 여기가 뒤집히면 노트의 시각이 조용히 틀린다 — 에러가 안 난다.
#    "치환됐다" 만 보면 못 잡는다. **어느 값이 들어갔는지** 본다.
t_eq "created 는 시각까지 (HH 있음)" "created: $N" \
  "$(printf '%s\n' "$OUT" | grep '^created:' | head -1)"
t_eq "updated 는 시각까지 (HH 있음)" "updated: $N" \
  "$(printf '%s\n' "$OUT" | grep '^updated:' | head -1)"
t_eq "watched_at 은 날짜만 (HH 없음)" "watched_at: $D" \
  "$(printf '%s\n' "$OUT" | grep '^watched_at:' | head -1)"
t_eq "Templater 문법이 남지 않았다" "0" \
  "$(printf '%s\n' "$OUT" | grep -c 'tp\.date\.now' | tr -d ' ')"

t_start "제목·url·채널"
t_eq "제목이 들어갔다" "1" "$(printf '%s\n' "$OUT" | grep -c '^# 영상 제목$' | tr -d ' ')"
t_eq "url 이 채워졌다" "1" "$(printf '%s\n' "$OUT" | grep -c '^url: https://y/x$' | tr -d ' ')"
t_eq "채널이 채워졌다" "1" "$(printf '%s\n' "$OUT" | grep -c '^channel: 채널명$' | tr -d ' ')"

t_start "⚠️ 모르는 것은 비워 둔다"
# ⚠️ 빈 칸은 "아직 없다" 는 사실이고, 지어낸 값은 거짓이다.
EMPTY=$(_cap_render "$TPL" "제목만" "" "" "$D" "$N")
t_eq "url 이 빈 채로 남는다" "1" "$(printf '%s\n' "$EMPTY" | grep -c '^url:[[:space:]]*$' | tr -d ' ')"
t_eq "channel 이 빈 채로 남는다" "1" "$(printf '%s\n' "$EMPTY" | grep -c '^channel:[[:space:]]*$' | tr -d ' ')"

t_start "⚠️ 값을 문자 그대로 넣는다"
# ⚠️ 정규식 치환을 쓰면 치환문자열의 특수문자가 해석된다 — awk 는 `&`,
#    python 은 `\1`. 제목에 그게 들어 있으면 조용히 망가지거나 죽는다.
#    (python 판은 실제로 `\1` 에서 크래시했다.)
AMP=$(_cap_render "$TPL" 'A & B' 'https://y/z?a=1&b=2' 'C&D' "$D" "$N")
t_eq "제목의 & 가 그대로" "1" "$(printf '%s\n' "$AMP" | grep -c '^# A & B$' | tr -d ' ')"
t_eq "url 의 & 가 그대로" "1" \
  "$(printf '%s\n' "$AMP" | grep -c '^url: https://y/z?a=1&b=2$' | tr -d ' ')"
BSL=$(_cap_render "$TPL" 'A\1B' 'https://y/w' 'X\1Y' "$D" "$N")
t_eq "제목의 \\1 이 그대로" "1" "$(printf '%s\n' "$BSL" | grep -cF '# A\1B' | tr -d ' ')"

t_start "한글·이모지"
EMO=$(_cap_render "$TPL" "한글 제목 🎬" "https://y/e" "채널 📺" "$D" "$N")
t_eq "제목이 온전하다" "1" "$(printf '%s\n' "$EMO" | grep -c '^# 한글 제목 🎬$' | tr -d ' ')"
t_eq "채널이 온전하다" "1" "$(printf '%s\n' "$EMO" | grep -c '^channel: 채널 📺$' | tr -d ' ')"

t_start "⚠️ 모르는 문법이 남으면 실패한다 — 조용히 통과시키지 않는다"
# ⚠️ 모르는 Templater 문법을 그대로 둔 노트는 사용자 볼트에서 깨진 채로
#    보인다. 소리내어 실패하는 편이 낫다.
LEFT="$TMP/left.md"
cp "$TPL" "$LEFT"
printf '\n<%% tp.unknown() %%>\n' >> "$LEFT"
ERR="$TMP/err.txt"
LOUT=$(_cap_render "$LEFT" "t" "u" "c" "$D" "$N" 2>"$ERR"); LRC=$?
t_eq "실패로 끝난다" "1" "$([ "$LRC" -ne 0 ] && echo 1 || echo 0)"
t_eq "무엇이 문제인지 말한다" "1" "$(grep -c '템플릿 문법이 남았습니다' "$ERR" | tr -d ' ')"
# ⚠️ **반쯤 쓰인 노트를 남기지 않는다.** 호출부가 실패로 처리해도, 그 파일이
#    어딘가 남아 있으면 다음 사람이 그것을 진짜라고 읽는다.
t_eq "아무것도 출력하지 않는다" "" "$LOUT"

t_start "⚠️ 멈춘다 (무한 루프 방지)"
# ⚠️ 2026-08-24 에 while+match 가 진행하지 않아 CPU 한 코어를 물었다.
#    같은 템플릿을 반복 렌더해 시간이 폭발하지 않는지 본다.
S=$(date +%s)
i=0
while [ "$i" -lt 5 ]; do _cap_render "$TPL" "반복 $i" "u" "c" "$D" "$N" >/dev/null; i=$((i + 1)); done
E=$(date +%s)
t_eq "5회가 20초 안에 끝난다" "yes" \
  "$([ $((E - S)) -lt 20 ] && echo yes || echo "no ($((E - S))초)")"

t_end
