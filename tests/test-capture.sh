#!/usr/bin/env bash
# devtrail capture — Obsidian 없이 여는 좁은 쓰기 통로 (ADR 0003)
#
# ⚠️ 이 통로가 안전한 이유는 네 가지다: dry-run 기본 · 저널 · 원자적 · 템플릿
#    단일 출처. 아래 테스트가 그 넷을 지킨다. 하나라도 빠지면 두 번째 쓰기
#    출처가 되고, 그때부터 노트 형식은 아무도 모르게 갈린다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
DT="$ROOT/bin/devtrail"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT
export DEVTRAIL_OBSIDIAN_REGISTRY="$T_TMP/reg.json"

_vault() {
  local v="$T_TMP/$1"
  mkdir -p "$v/.obsidian" "$v/notes/개발/유튜브" "$v/notes/템플릿"
  cp "$ROOT/preset/templates/ko/유튜브 노트 템플릿.md" "$v/notes/템플릿/" 2>/dev/null
  printf '%s' "$v"
}
_cfg() {
  local v="$1" h="$2"; mkdir -p "$h"
  jq -n --arg v "$v" '{version:3, lang:"ko",
    vault:{backend:"local", path:$v, root:"notes"}, dirs:{},
    github:{user:"t", repos:[], project_groups:{}},
    install:{mode:"new", modules:["devlog"]}}' > "$h/devtrail.config.json"
}
V=$(_vault v); H="$T_TMP/h"; _cfg "$V" "$H"
run() { DEVTRAIL_HOME="$H" DEVTRAIL_CONFIG="$H/devtrail.config.json" "$DT" "$@"; }
ydir() { printf '%s' "$V/$(run path youtube --rel 2>/dev/null)"; }
count() { find "$(ydir)" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

URL="https://www.youtube.com/watch?v=dQw4w9WgXcQ"

t_start "URL 을 가려 받는다"
# ⚠️ 무엇을 받고 무엇을 거절하는지가 분명해야 한다. 애매하면 거절한다 —
#    잘못 만든 노트보다 안 만든 게 낫다.
for bad in "" "not a url" "https://example.com/watch?v=x" \
           "https://www.youtube.com/" "https://www.youtube.com/@channel"; do
  run capture youtube --url "$bad" >/dev/null 2>&1
  t_ne "거절: ${bad:-(빈 값)}" "0" "$?"
done
for good in "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
            "https://youtu.be/dQw4w9WgXcQ" \
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42" \
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ"; do
  out=$(run capture youtube --url "$good" 2>&1)
  t_eq "받음: $good" "0" "$?"
  # 같은 영상이면 같은 id 로 읽어야 중복을 알아본다.
  t_contains "id 를 뽑는다" "dQw4w9WgXcQ" "$out"
done

t_start "기본은 dry-run 이다"
before=$(count)
out=$(run capture youtube --url "$URL" 2>&1)
t_eq "파일을 만들지 않는다" "$before" "$(count)"
t_contains "무엇이 생길지 말한다" "dry-run" "$out"
t_contains "적용 방법을 알려준다" "--apply" "$out"

t_start "--apply 만 노트를 만든다"
run capture youtube --url "$URL" --apply >/dev/null 2>&1
t_eq "노트가 하나 생겼다" "1" "$(count)"
NOTE=$(find "$(ydir)" -name '*.md' | head -1)
t_contains "URL 이 들어 있다" "$URL" "$(cat "$NOTE")"
t_contains "type 이 youtube" "type: youtube" "$(cat "$NOTE")"
# ⚠️ 캡처는 '받아둔 것' 이다. 분석은 아직 안 했다 — status 가 그렇게 말해야 한다.
t_contains "아직 정리 전이다" "status: inbox" "$(cat "$NOTE")"
# ⚠️ 지어낸 요약을 넣지 않는다. 빈 칸은 '아직 안 했다' 는 사실이고,
#    그럴듯한 문장은 거짓이다.
t_contains "분석 칸이 비어 있다" "tl_dr_oneline:" "$(cat "$NOTE")"
t_eq "요약을 지어내지 않았다" "" \
  "$(grep '^tl_dr_oneline:' "$NOTE" | sed 's/^tl_dr_oneline: *//')"

t_start "템플릿이 단일 출처다"
# ⚠️ CLI 가 자기 형식을 따로 만들면 Templater 가 만든 노트와 어긋난다.
TPL="$V/notes/템플릿/유튜브 노트 템플릿.md"
for k in $(grep -oE '^[a-z_]+:' "$TPL" | tr -d ':'); do
  t_contains "프런트매터 $k" "$k:" "$(cat "$NOTE")"
done
# ⚠️ 따옴표로 감싸면 세 줄이 한 덩어리 바늘이 되어, 노트에 그 세 줄이
#    연달아 있어야만 통과한다 — 실제로는 사이에 내용이 있다. 줄마다 본다.
NOTE_BODY="$(cat "$NOTE")"
grep -oE '^## .*' "$TPL" | head -3 | while IFS= read -r h; do
  t_contains "본문 골격: $h" "$h" "$NOTE_BODY"
done
# 템플릿 문법이 그대로 새어 나가지 않는다.
t_eq "Templater 문법이 남지 않았다" "0" "$(grep -c '<%' "$NOTE")"

t_start "같은 영상을 두 번 만들지 않는다"
n=$(count)
out=$(run capture youtube --url "https://youtu.be/dQw4w9WgXcQ" --apply 2>&1)
t_eq "노트가 늘지 않는다" "$n" "$(count)"
t_contains "이미 있다고 말한다" "이미" "$out"
t_contains "어디 있는지 알려준다" "$(basename "$NOTE")" "$out"

t_start "실패하면 아무것도 남기지 않는다"
# ⚠️ 절반만 쓴 노트가 최악이다 — frontmatter 는 있는데 본문이 없으면
#    Obsidian 이 그것을 정상 노트로 읽는다.
n=$(count)
DT_CAPTURE_FAIL=1 run capture youtube --url "https://youtu.be/AAAAAAAAAAA" --apply >/dev/null 2>&1
t_ne "실패로 끝난다" "0" "$?"
t_eq "노트가 늘지 않았다" "$n" "$(count)"
t_eq "임시 파일이 남지 않았다" "0" \
  "$(find "$(ydir)" -name '*.tmp*' -o -name '.*.swp' 2>/dev/null | wc -l | tr -d ' ')"

t_start "undo 가 노트를 지운다"
run capture youtube --url "https://youtu.be/BBBBBBBBBBB" --apply >/dev/null 2>&1
n=$(count)
job=$(ls -1 "$H/journal" | tail -1)
t_contains "저널 이름이 분명하다" "capture-youtube" \
  "$(jq -r '.command' "$H/journal/$job/meta.json")"
run undo "$job" --apply >/dev/null 2>&1
t_eq "노트가 사라졌다" "$((n - 1))" "$(count)"

t_start "사용자 것을 건드리지 않는다"
t_eq "설정이 그대로" "1" "$(ls -1 "$H/devtrail.config.json" | wc -l | tr -d ' ')"
t_eq "사용자 노트가 그대로" "0" \
  "$(find "$V/notes" -name '*.md' -newer "$H/devtrail.config.json" \
     -not -path "*유튜브*" -not -path "*템플릿*" 2>/dev/null | wc -l | tr -d ' ')"

t_start "메타데이터를 제대로 갈라 읽는다"
# ⚠️ yt-dlp 출력 파싱을 테스트가 안 타면 네트워크가 켜진 실제 실행에서만
#    드러난다 — 2026-08-22 에 제목과 채널이 한 덩어리로 들어갔다.
#    (--print '%(title)s\t%(channel)s' 의 \t 가 문자 그대로 나왔다)
cat > "$T_TMP/meta.sh" <<'SHEOF'
. "$1/lib/common.sh" >/dev/null 2>&1 || true
. "$1/lib/capturecmd.sh"
bad=0
chk() {
  got=$(printf '%s' "$1" | cap_parse_meta "$2")
  [ "$got" = "$3" ] || { echo "MISMATCH [$2] want [$3] got [$got]"; bad=1; }
}
two="$(printf 'Never Gonna Give You Up\nRick Astley')"
chk "$two" title "Never Gonna Give You Up"
chk "$two" channel "Rick Astley"
# 제목에 탭이나 특수문자가 있어도 줄이 기준이다.
tricky="$(printf 'A\tB | C\nChannel X')"
chk "$tricky" title "A	B | C"
chk "$tricky" channel "Channel X"
# 채널을 못 얻으면 빈 값이다 — 제목을 채널로 쓰지 않는다.
chk "$(printf 'Only Title')" channel ""
chk "$(printf 'Only Title')" title "Only Title"
chk "" title ""
[ $bad = 0 ] && echo OK || echo FAIL
SHEOF
t_eq "제목과 채널이 갈린다" "OK" "$(bash "$T_TMP/meta.sh" "$ROOT" 2>&1 | tail -1)"

t_start "빈 템플릿으로 빈 노트를 만들지 않는다"
# ⚠️ 템플릿이 비었거나 망가지면 렌더 결과도 빈다. 그것을 그대로 저장하면
#    Obsidian 은 내용 없는 노트를 정상으로 읽고, 사용자는 왜 빈지 모른다.
VE=$(_vault ve); HE="$T_TMP/he"; _cfg "$VE" "$HE"
: > "$VE/notes/템플릿/유튜브 노트 템플릿.md"   # 0 바이트
erun() { DEVTRAIL_HOME="$HE" DEVTRAIL_CONFIG="$HE/devtrail.config.json" "$DT" "$@"; }
edir="$VE/notes/개발/유튜브"
erun capture youtube --url "https://youtu.be/CCCCCCCCCCC" --apply >/dev/null 2>&1
t_ne "실패로 끝난다" "0" "$?"
t_eq "노트를 만들지 않았다" "0" \
  "$(find "$edir" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"

t_end
