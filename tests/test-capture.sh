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
  cp "$ROOT/preset/templates/ko/웹 링크 노트 템플릿.md" "$v/notes/템플릿/" 2>/dev/null
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
webdir() {
  local inbox library
  inbox=$(run path inbox --rel 2>/dev/null)
  library=${inbox%/*}; [ "$library" = "$inbox" ] && library=""
  printf '%s/%s' "$V/${library:+$library/}" "$( [ "$(jq -r '.lang' "$H/devtrail.config.json")" = en ] && echo Links || echo 링크 )"
}
webcount() { find "$(webdir)" -name '*.md' ! -name '_index.md' 2>/dev/null | wc -l | tr -d ' '; }

URL="https://www.youtube.com/watch?v=dQw4w9WgXcQ"

t_start "일반 웹 링크는 안전하게 메타데이터를 저장한다"
cat > "$T_TMP/web-og.html" <<'EOF'
<!doctype html><html><head>
<title>Fallback title</title>
<meta name="description" content="Fallback description">
<meta property="og:title" content="MDN Web Docs">
<meta property="og:description" content="Documentation for web developers">
<meta property="og:image" content="https://cdn.example.test/card.png">
<meta property="og:site_name" content="MDN">
<meta property="og:type" content="website">
<link rel="canonical" href="https://docs.example.test/guide">
</head><body></body></html>
EOF
cat > "$T_TMP/web-title.html" <<'EOF'
<html><head><title>Only a title page</title></head><body>hello</body></html>
EOF

t_start "웹 분류는 개발 분야와 세부 용도를 함께 고른다"
TAXONOMY="$({ . "$ROOT/lib/taxonomy.sh"; cap_taxonomy_web 'https://lucide.dev/icons' 'lucide.dev' 'Lucide Icons' ''; printf '%s/%s/%s' "$CAP_TAX_TYPE" "$CAP_TAX_AREA" "$CAP_TAX_TOPIC"; })"
t_eq "아이콘은 디자인 아이콘으로 분류한다" "asset/design/icons" "$TAXONOMY"
TAXONOMY="$({ . "$ROOT/lib/taxonomy.sh"; cap_taxonomy_web 'https://react.dev/reference' 'react.dev' 'React reference' ''; printf '%s/%s/%s' "$CAP_TAX_TYPE" "$CAP_TAX_AREA" "$CAP_TAX_TOPIC"; })"
t_eq "React 문서는 프론트엔드 공식문서로 분류한다" "docs/frontend/official-docs" "$TAXONOMY"
TAXONOMY="$({ . "$ROOT/lib/taxonomy.sh"; cap_taxonomy_web 'https://seed-design.io/' 'seed-design.io' 'SEED Design System' ''; printf '%s/%s/%s' "$CAP_TAX_TYPE" "$CAP_TAX_AREA" "$CAP_TAX_TOPIC"; })"
t_eq "디자인 시스템은 디자인 시스템 자료실로 분류한다" "reference/design/color-design-systems" "$TAXONOMY"
TAXONOMY="$({ . "$ROOT/lib/taxonomy.sh"; cap_taxonomy_web 'https://school.programmers.co.kr/learn/courses/30' 'school.programmers.co.kr' '코딩테스트 연습' ''; printf '%s/%s/%s' "$CAP_TAX_TYPE" "$CAP_TAX_AREA" "$CAP_TAX_TOPIC"; })"
t_eq "코딩테스트는 연습 자료실로 분류한다" "reference/common/coding-practice" "$TAXONOMY"
WEBURL="https://docs.example.test/guide?from=test"
for bad in "" "not a url" "ftp://example.com/x" "http://127.0.0.1/" \
           "http://localhost/" "https://example.com:8443/"; do
  DT_WEB_FETCH_FILE="$T_TMP/web-og.html" run capture web --url "$bad" >/dev/null 2>&1
  t_ne "웹 URL 거절: ${bad:-(빈 값)}" "0" "$?"
done
before=$(webcount)
out=$(DT_WEB_FETCH_FILE="$T_TMP/web-og.html" run capture web --url "$WEBURL" 2>&1)
t_eq "웹 dry-run 성공" "0" "$?"
t_eq "웹 dry-run은 파일을 만들지 않는다" "$before" "$(webcount)"
t_contains "추출 제목을 말한다" "MDN Web Docs" "$out"
t_contains "분류를 말한다" "type: docs" "$out"
t_contains "저장 위치를 말한다" "만들 노트" "$out"
DT_WEB_FETCH_FILE="$T_TMP/web-og.html" run capture web --url "$WEBURL" --apply >/dev/null
t_eq "웹 노트가 하나 생긴다" "1" "$(webcount)"
WEBNOTE=$(grep -rlF -- "$WEBURL" "$(webdir)" | head -1)
WEBBODY="$(cat "$WEBNOTE")"
t_contains "OG 제목을 쓴다" 'title: "MDN Web Docs"' "$WEBBODY"
t_contains "OG 설명을 쓴다" 'description: "Documentation for web developers"' "$WEBBODY"
t_contains "OG 이미지도 쓴다" 'image: "https://cdn.example.test/card.png"' "$WEBBODY"
t_contains "canonical URL을 쓴다" 'canonical_url: "https://docs.example.test/guide"' "$WEBBODY"
t_contains "작은 고정 type" 'type: docs' "$WEBBODY"
t_contains "도메인 태그" 'source/docs.example.test' "$WEBBODY"
t_contains "Inbox 상태" 'status: inbox' "$WEBBODY"
t_contains "개발 분야도 쓴다" 'area: common' "$WEBBODY"
t_contains "세부 주제도 쓴다" 'topic: documentation' "$WEBBODY"
t_eq "웹 토큰이 남지 않는다" "0" "$(grep -c '{{WEB_' "$WEBNOTE")"
t_file "링크 자료실 허브가 생긴다" "$(webdir)/_index.md"
t_contains "링크 자료실은 분야별 허브도 보여준다" "devtrail:link-library:areas:start" "$(cat "$(webdir)/_index.md")"
t_file "분야 허브가 생긴다" "$(webdir)/공통/_index.md"
t_file "세부 분류 허브가 생긴다" "$(webdir)/공통/문서-레퍼런스/_index.md"

t_start "웹 링크는 title만 있어도 저장하고 메타 실패도 폴백한다"
TITLEURL="https://example.test/only-title"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" run capture web --url "$TITLEURL" --apply >/dev/null
t_eq "title만인 노트도 생긴다" "2" "$(webcount)"
TITLE_NOTE=$(grep -rlF -- "$TITLEURL" "$(webdir)" | head -1)
t_contains "title fallback을 쓴다" 'title: "Only a title page"' "$(cat "$TITLE_NOTE")"
FAILURL="https://reference.example.test/unavailable"
out=$(DT_WEB_FETCH_FAIL=1 run capture web --url "$FAILURL" --apply 2>&1)
t_eq "메타 실패도 링크 저장은 성공" "0" "$?"
t_eq "메타 실패 노트가 생긴다" "3" "$(webcount)"
FAIL_NOTE=$(grep -rlF -- "$FAILURL" "$(webdir)" | head -1)
t_contains "메타 실패는 reference" 'type: reference' "$(cat "$FAIL_NOTE")"
t_contains "메타 실패를 알린다" "메타데이터" "$out"

t_start "같은 URL 또는 canonical URL은 중복 저장하지 않는다"
n=$(webcount)
out=$(DT_WEB_FETCH_FILE="$T_TMP/web-og.html" run capture web --url "$WEBURL" --apply 2>&1)
t_eq "같은 URL은 성공으로 안내" "0" "$?"
t_eq "같은 URL로 노트가 늘지 않는다" "$n" "$(webcount)"
t_contains "중복 경로 표식이 있다" "DEVTRAIL_CAPTURE_DUPLICATE=" "$out"
CANONURL="https://other.example.test/same-page"
out=$(DT_WEB_FETCH_FILE="$T_TMP/web-og.html" run capture web --url "$CANONURL" --apply 2>&1)
t_eq "canonical 중복도 성공으로 안내" "0" "$?"
t_eq "canonical 중복은 노트를 늘리지 않는다" "$n" "$(webcount)"
t_contains "canonical 중복 표식이 있다" "DEVTRAIL_CAPTURE_DUPLICATE=" "$out"

t_start "제목만 같은 다른 링크는 덮어쓰지 않는다"
n=$(webcount)
COLLISIONURL="https://another.example.test/only-title"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" run capture web --url "$COLLISIONURL" --apply >/dev/null
t_eq "다른 URL은 새 노트가 된다" "$((n + 1))" "$(webcount)"
COLLISION_NOTE="$(webdir)/공통/미분류/$(date +%F)-only-a-title-page-2.md"
t_file "이름 충돌 노트가 있다" "$COLLISION_NOTE"
t_contains "새 URL을 보존한다" "$COLLISIONURL" "$(cat "$COLLISION_NOTE")"

t_start "기존 미분류 링크도 다시 저장하지 않고 분야별로 정리한다"
LEGACY_DIR="$(webdir)/공통/미분류"; mkdir -p "$LEGACY_DIR"
LEGACY_NOTE="$LEGACY_DIR/legacy-seed.md"
cat > "$LEGACY_NOTE" <<'EOF'
---
tags: ["type/reference", "area/common", "topic/uncategorized", "source/seed-design.io"]
type: reference
area: common
topic: uncategorized
source_kind: site
status: inbox
source: "seed-design.io"
url: "https://seed-design.io/library"
title: "SEED Design System"
description: "A design system"
saved: 2026-08-25
---

# SEED Design System
EOF
out=$(run capture web --organize 2>&1)
t_eq "기존 링크 분류 dry-run 성공" "0" "$?"
t_file "dry-run은 기존 미분류 링크를 보존한다" "$LEGACY_NOTE"
t_contains "dry-run은 분류 계획을 보인다" "design / color-design-systems" "$out"
run capture web --organize --apply >/dev/null
MIGRATED_NOTE="$(webdir)/디자인/컬러-디자인시스템/legacy-seed.md"
t_file "기존 링크를 디자인 자료실로 옮긴다" "$MIGRATED_NOTE"
t_eq "원래 미분류 파일은 이동된다" "no" "$( [ -e "$LEGACY_NOTE" ] && echo yes || echo no )"
t_contains "기존 링크의 분야도 바꾼다" 'area: design' "$(cat "$MIGRATED_NOTE")"
job=$(ls -1 "$H/journal" | tail -1)
run undo "$job" --apply >/dev/null
t_file "기존 링크 재분류도 undo로 되돌린다" "$LEGACY_NOTE"
t_eq "undo는 옮긴 분류 파일을 지운다" "no" "$( [ -e "$MIGRATED_NOTE" ] && echo yes || echo no )"

t_start "웹 링크 생성도 undo로 되돌린다"
UNDOURL="https://assets.example.test/icon"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" run capture web --url "$UNDOURL" --apply >/dev/null
n=$(webcount); job=$(ls -1 "$H/journal" | tail -1)
t_contains "웹 저널 이름이 분명하다" "capture-web" "$(jq -r '.command' "$H/journal/$job/meta.json")"
run undo "$job" --apply >/dev/null
t_eq "undo가 웹 노트를 지운다" "$((n - 1))" "$(webcount)"

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

t_start "개발일지는 빈 파일로 만들지 않는다"
DEVLOG="$V/notes/개발/개발일지/$(date +%F) devlog.md"
out=$(run capture devlog 2>&1)
t_eq "개발일지 기본은 dry-run" "0" "$?"
t_no_file "dry-run은 일지를 만들지 않는다" "$DEVLOG"
t_contains "만들 위치를 말한다" "만들 노트" "$out"
run capture devlog --apply >/dev/null 2>&1
t_file "개발일지가 생긴다" "$DEVLOG"
t_contains "개발일지 type" "type: devlog" "$(cat "$DEVLOG")"
t_contains "활동 삽입 헤딩이 있다" "## Issues / PRs" "$(cat "$DEVLOG")"
t_contains "오늘 할 일 골격이 있다" "Top 3" "$(cat "$DEVLOG")"
t_contains "유튜브 자동 집계가 있다" "오늘 본 유튜브" "$(cat "$DEVLOG")"
t_contains "오늘 만든 노트 집계가 있다" "오늘 만든 노트" "$(cat "$DEVLOG")"
t_ne "빈 파일이 아니다" "0" "$(wc -c < "$DEVLOG" | tr -d ' ')"
work_line=$(grep -n '^## Work log$' "$DEVLOG" | cut -d: -f1)
issues_line=$(grep -n '^## Issues / PRs$' "$DEVLOG" | cut -d: -f1)
t_eq "작업 로그가 이슈/PR보다 먼저다" "yes" \
  "$([ "$work_line" -lt "$issues_line" ] && echo yes || echo no)"
out=$(run capture devlog --apply 2>&1)
t_contains "같은 날에는 기존 일지를 쓴다" "이미 있습니다" "$out"
job=$(ls -1 "$H/journal" | tail -1)
run undo "$job" --apply >/dev/null 2>&1
t_no_file "되돌리면 개발일지도 사라진다" "$DEVLOG"

t_start "기존 개발일지도 작업 로그를 먼저 보이게 정리한다"
mkdir -p "$(dirname "$DEVLOG")"
cat > "$DEVLOG" <<'EOF'
# old devlog

## Issues / PRs

old issues

## Work log

old work

## 📺 Today

rest
EOF
run capture devlog --repair-order --apply >/dev/null 2>&1
work_line=$(grep -n '^## Work log$' "$DEVLOG" | cut -d: -f1)
issues_line=$(grep -n '^## Issues / PRs$' "$DEVLOG" | cut -d: -f1)
t_eq "기존 파일도 작업 로그가 먼저다" "yes" \
  "$([ "$work_line" -lt "$issues_line" ] && echo yes || echo no)"
job=$(ls -1 "$H/journal" | tail -1)
run undo "$job" --apply >/dev/null 2>&1
t_contains "되돌리면 원래 순서로 복구된다" "## Issues / PRs" "$(head -5 "$DEVLOG")"
# 위 파일은 테스트가 직접 심은 임시 볼트 노트다. 다음 '사용자 노트' 보호
# 검사는 실제 캡처가 만든 파일만 보도록 명시적으로 제거한다.
rm -f "$DEVLOG"

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

t_start "--ai 는 Claude 유튜브 스킬을 요청한다"
# 실제 API·자막 다운로드 없이 호출 계약만 검증한다. 가짜 Claude가 받은
# 인자를 기록하므로, 앱의 한 번 클릭이 스킬까지 이어지는지를 확인할 수 있다.
FAKE="$T_TMP/fake-bin"; mkdir -p "$FAKE"
cat > "$FAKE/claude" <<'SHEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$DT_FAKE_CLAUDE_ARGS"
echo "AI done"
SHEOF
chmod +x "$FAKE/claude"
mkdir -p "$T_TMP/home/.claude/skills/devtrail-youtube"
AIURL="https://youtu.be/DDDDDDDDDDD"
DT_CAPTURE_TRANSCRIPT="00:00 test transcript" DT_FAKE_CLAUDE_ARGS="$T_TMP/claude.args" HOME="$T_TMP/home" PATH="$FAKE:$PATH" \
  run capture youtube --url "$AIURL" --apply --ai >/dev/null 2>&1
t_file "Claude가 호출됐다" "$T_TMP/claude.args"
t_contains "노트 읽기·쓰기를 허용한다" "Read,Edit,Write" "$(cat "$T_TMP/claude.args")"
t_contains "노트 폴더만 열어 준다" "--add-dir" "$(cat "$T_TMP/claude.args")"
t_contains "자막 언어를 하나씩만 요청한다" "--sub-langs 'ko,ja,en'" "$(cat "$ROOT/lib/capturecmd.sh")"
t_contains "VTT 자막도 읽는다" "-name '*.vtt'" "$(cat "$ROOT/lib/capturecmd.sh")"
t_contains "AI가 분야를 반드시 채운다" "분류는 반드시 채우세요" "$(cat "$ROOT/lib/capturecmd.sh")"
t_contains "AI 분류값을 검증한다" "DEVTRAIL_CAPTURE_AI=partial" "$(cat "$ROOT/lib/capturecmd.sh")"
t_contains "기존 유튜브 템플릿에도 분야 필드를 보완한다" "DT_Y_ADD_AREA" "$(cat "$ROOT/lib/capturecmd.sh")"
t_contains "기존 웹 템플릿에도 분야 필드를 보완한다" "DT_W_ADD_AREA" "$(cat "$ROOT/lib/webcapture.sh")"

t_start "AI 분석 불가는 링크 저장 실패가 아니다"
FAILURL="https://youtu.be/EEEEEEEEEEE"
cat > "$FAKE/claude" <<'SHEOF'
#!/usr/bin/env bash
echo "Video unavailable"
SHEOF
chmod +x "$FAKE/claude"
out=$(DT_CAPTURE_TRANSCRIPT="00:00 test transcript" DT_FAKE_CLAUDE_ARGS="$T_TMP/claude.args" HOME="$T_TMP/home" PATH="$FAKE:$PATH" \
  run capture youtube --url "$FAILURL" --apply --ai 2>&1)
t_eq "자막이 없어도 링크 저장은 성공" "0" "$?"
t_contains "저장한 노트 경로 표식이 있다" "DEVTRAIL_CAPTURE_PATH=" "$out"
t_contains "AI 분석 불가 표식이 있다" "DEVTRAIL_CAPTURE_AI=unavailable" "$out"

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
t_contains "기존 노트 경로 표식이 있다" "DEVTRAIL_CAPTURE_DUPLICATE=" "$out"
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
     -not -path "*유튜브*" -not -path "*자료실/00_Inbox*" -not -path "*자료실/링크*" -not -path "*템플릿*" 2>/dev/null | wc -l | tr -d ' ')"

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
