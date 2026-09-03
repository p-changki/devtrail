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
# ⚠️ Dataview 는 음수 인덱스를 지원하지 않는다. split(...)[-1] 은 에러 없이
#    null 이 되어 링크가 `_index` 로 표시됐다 — 실물 화면에서만 드러났다.
t_contains "분야 허브는 _index 대신 분야명으로 보인다" 'regexreplace(file.folder, ".*/", "")' "$(cat "$(webdir)/_index.md")"
t_not_contains "음수 인덱스를 쓰지 않는다" '[-1]' "$(cat "$(webdir)/_index.md")"
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

# ── 개발일지에 프로젝트를 붙인다 ────────────────────────────────────────────
#
# ⚠️ CLI 가 만드는 일지는 projects: [] 로 비어 있었다. 메뉴바 앱이 이 경로를
#    쓰므로 사용자는 프로젝트를 고를 방법이 아예 없었다 — Templater 경로에만
#    선택창이 있었다.
t_start "개발일지에 프로젝트를 붙인다"
rm -f "$DEVLOG"
mkdir -p "$V/notes/개발/프로젝트/alpha" "$V/notes/개발/프로젝트/beta"
run capture devlog --project alpha --project beta --apply >/dev/null 2>&1
t_contains "고른 프로젝트가 frontmatter 에 든다" "projects: [alpha, beta]" "$(cat "$DEVLOG")"
t_contains "alpha 태그가 붙는다" "  - project/alpha" "$(cat "$DEVLOG")"
t_contains "beta 태그가 붙는다" "  - project/beta" "$(cat "$DEVLOG")"
# ⚠️ frontmatter 만 채우면 본문에 쓸 자리가 없다. Templater 템플릿은 오전
#    아래에 프로젝트별 #### 소제목과 README 링크를 넣는다 — devtrail summary
#    가 PR 요약을 넣는 자리도 이 섹션이다. 없으면 요약이 조용히 건너뛴다.
t_contains "본문에 alpha 소제목이 생긴다" "#### alpha" "$(cat "$DEVLOG")"
t_contains "본문에 beta 소제목이 생긴다" "#### beta" "$(cat "$DEVLOG")"
# ⚠️ README 링크 줄은 넣지 않는다. 프로젝트마다 두 줄이 되어 읽기 나쁘고,
#    README 가 없는 폴더에서는 깨진 링크가 된다.
t_not_contains "README 링크는 넣지 않는다" "/README|" "$(cat "$DEVLOG")"
t_eq "빈 소제목은 남지 않는다" "0" "$(grep -c '^####$' "$DEVLOG" | tr -d ' ')"

t_start "모르는 프로젝트는 거절한다"
rm -f "$DEVLOG"
before=$(count)
out=$(run capture devlog --project nope --apply 2>&1)
t_ne "실패로 끝난다" "0" "$?"
t_no_file "일지를 만들지 않는다" "$DEVLOG"
t_contains "무엇이 문제인지 말한다" "nope" "$out"

t_start "프로젝트를 안 고르면 예전처럼 비운다"
rm -f "$DEVLOG"
run capture devlog --apply >/dev/null 2>&1
t_contains "빈 목록을 쓴다" "projects: []" "$(cat "$DEVLOG")"
t_not_contains "프로젝트 태그가 없다" "project/" "$(cat "$DEVLOG")"
# ⚠️ 안 골랐을 때는 예전처럼 빈 #### 를 남긴다. 사용자가 직접 적을 자리다.
t_eq "빈 소제목 자리는 그대로" "1" "$(grep -c '^####$' "$DEVLOG" | tr -d ' ')"

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
  run capture youtube --url "$AIURL" --purpose "디자인 판단 기준" --apply --ai >/dev/null 2>&1
t_file "Claude가 호출됐다" "$T_TMP/claude.args"
t_contains "노트 읽기·쓰기를 허용한다" "Read,Edit,Write" "$(cat "$T_TMP/claude.args")"
t_contains "노트 폴더만 열어 준다" "--add-dir" "$(cat "$T_TMP/claude.args")"
t_contains "자막 언어를 하나씩만 요청한다" "--sub-langs 'ko,ja,en'" "$(cat "$ROOT/lib/captureai.sh")"
t_contains "VTT 자막도 읽는다" "-name '*.vtt'" "$(cat "$ROOT/lib/captureai.sh")"
t_contains "AI가 분야를 반드시 채운다" "분류는 반드시 채우세요" "$(cat "$ROOT/lib/captureai.sh")"
t_contains "사용자 목적을 Claude 프롬프트에 전달한다" "사용자 학습 목적: 디자인 판단 기준" "$(cat "$T_TMP/claude.args")"
t_contains "자막이 없어도 사용자 목적을 노트에 보존한다" "learning_goal: 디자인 판단 기준" "$(find "$V" -type f -name '*ddddddddddd*.md' -o -name '*DDDDDDDDDDD*.md' | head -1 | xargs cat 2>/dev/null)"
t_contains "판단 기준 형식으로 정리한다" "바로 쓰는 판단 기준" "$(cat "$ROOT/lib/captureai.sh")"
t_contains "AI 분류값을 검증한다" "DEVTRAIL_CAPTURE_AI=partial" "$(cat "$ROOT/lib/captureai.sh")"
t_contains "AI 종료 코드보다 실제 노트 저장을 우선 판정한다" "claude_rc" "$(cat "$ROOT/lib/captureai.sh")"
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

# ⚠️ AI 프롬프트가 요구하는 자리가 템플릿에 없으면 채울 곳이 없다.
#    프롬프트(captureai.sh)와 템플릿이 어긋나면 여기서 걸린다.
KO_TPL="$(cat "$ROOT/preset/templates/ko/유튜브 노트 템플릿.md")"
EN_TPL="$(cat "$ROOT/preset/templates/en/YouTube note.md")"
t_contains "ko 템플릿에 학습 목적 자리가 있다" "learning_goal:" "$KO_TPL"
t_contains "ko 템플릿에 판단 기준 자리가 있다" "## 바로 쓰는 판단 기준" "$KO_TPL"
t_contains "en 템플릿에 학습 목적 자리가 있다" "learning_goal:" "$EN_TPL"
t_contains "en 템플릿에 판단 기준 자리가 있다" "## Reusable decision criteria" "$EN_TPL"

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

# ── 링크 자료실: 분류 신호 + 맥락 필드 ────────────────────────────────
#
# ⚠️ 도메인 리터럴 목록만으로는 롱테일이 전부 `공통/미분류` 로 떨어진다.
#    실제로 17개 중 7개가 그랬다. 2차 신호 판정이 그 구멍을 메우되,
#    근거가 없으면 여전히 미분류로 남겨야 한다 — 억지 추측은 더 나쁘다.

t_start "분류 신호가 도메인 목록에 없는 링크도 분야를 고른다"
tax() {
  ( . "$ROOT/lib/taxonomy.sh"
    cap_taxonomy_web "$1" "$2" "$3" "${4:-}"
    printf '%s/%s/%s' "$CAP_TAX_TYPE" "$CAP_TAX_AREA" "$CAP_TAX_TOPIC" )
}
t_eq "landing.love — showcase 신호" "inspiration/design/landing-references" \
  "$(tax 'https://www.landing.love/' 'www.landing.love' 'Showcase of the best 2141 animation websites' '')"
t_eq "recent.design — .design TLD 신호" "inspiration/design/landing-references" \
  "$(tax 'https://recent.design/' 'recent.design' 'Recent design inspiration' '')"
t_eq "saaslandingpage.com — landing page 신호" "inspiration/design/landing-references" \
  "$(tax 'https://saaslandingpage.com/' 'saaslandingpage.com' 'SaaS Landing Page' '')"
t_eq "unicorn.studio — motion/graphics 신호" "tool/design/design-tools" \
  "$(tax 'https://www.unicorn.studio/' 'www.unicorn.studio' 'Unicorn Studio interactive motion & real-time graphics' '')"
t_eq "saasframe.io — saas+ui design 신호" "inspiration/design/landing-references" \
  "$(tax 'https://www.saasframe.io/' 'www.saasframe.io' '1 SaaS checklist UI design examples in 2026' '')"

t_start "근거가 없으면 억지로 분류하지 않는다"
# ⚠️ 이 검사가 빠지면 신호 규칙이 아무 링크나 design 으로 빨아들이는 것을
#    아무도 못 잡는다. 미분류로 남는 것이 틀리게 분류되는 것보다 낫다.
t_eq "google.com 은 미분류로 남는다" "reference/common/uncategorized" \
  "$(tax 'https://www.google.com/' 'www.google.com' 'Google' '')"
t_eq "정밀 규칙은 그대로다 (react.dev)" "docs/frontend/official-docs" \
  "$(tax 'https://react.dev/reference' 'react.dev' 'React reference' '')"
t_eq "정밀 규칙은 그대로다 (lucide)" "asset/design/icons" \
  "$(tax 'https://lucide.dev/icons' 'lucide.dev' 'Lucide Icons' '')"

t_start "URL 쿼리스트링이 분류를 결정하지 않는다"
# ⚠️ 실제로 겪었다: Google Fonts 를 저장했더니 URL 의 미리보기 파라미터
#    `icon.size=24&icon.color=…` 때문에 폰트 사이트가 아이콘 폴더로 갔다.
#    쿼리는 화면 상태·트래킹이지 그 페이지가 무엇인지가 아니다.
t_eq "폰트 사이트는 쿼리에 icon 이 있어도 타이포그래피" "asset/design/typography" \
  "$(tax 'https://fonts.google.com/?preview.layout=grid&icon.size=24&icon.color=%23e3e3e3' \
        'fonts.google.com' 'Browse Fonts - Google Fonts' \
        'Making the web more beautiful, fast, and open through great typography')"
t_eq "쿼리에만 있는 단어로 분류하지 않는다" "reference/common/uncategorized" \
  "$(tax 'https://example.test/?ref=design-system-inspiration' 'example.test' 'Example' '')"
# ⚠️ 경로는 여전히 봐야 한다. 쿼리만 버린다.
t_eq "경로 기반 정밀 규칙은 살아 있다" "docs/frontend/official-docs" \
  "$(tax 'https://nextjs.org/docs/app?foo=bar' 'nextjs.org' 'Next.js Docs' '')"

t_start "링크에 저장 이유와 프로젝트를 남긴다"
# ⚠️ 표에 URL 만 쌓이면 나중에 어떤 사이트였는지 사용자도 모른다. 저장
#    이유는 사람만 아는 정보다 — 비워둘 수는 있어도 지어낼 수는 없다.
VW=$(_vault vw); HW="$T_TMP/hw"; _cfg "$VW" "$HW"
jq '.github.project_groups = {"devtrail":"DevTrail","gyoan":"교안메이커"}' \
  "$HW/devtrail.config.json" > "$HW/c.tmp" && mv "$HW/c.tmp" "$HW/devtrail.config.json"
wrun() { DEVTRAIL_HOME="$HW" DEVTRAIL_CONFIG="$HW/devtrail.config.json" "$DT" "$@"; }
wdir() {
  local inbox library
  inbox=$(wrun path inbox --rel 2>/dev/null)
  library=${inbox%/*}; [ "$library" = "$inbox" ] && library=""
  printf '%s/%s' "$VW/${library:+$library/}" "링크"
}
CTXURL="https://developer.mozilla.org/en-US/docs/Web/CSS"
DT_WEB_FETCH_FILE="$T_TMP/web-og.html" wrun capture web --url "$CTXURL" \
  --why "랜딩 CSS 그리드 다시 볼 때" --project devtrail --project gyoan --apply >/dev/null
CTXNOTE=$(grep -rlF -- "$CTXURL" "$(wdir)" | head -1)
t_ne "맥락을 붙인 노트가 생긴다" "" "$CTXNOTE"
CTXBODY=$(cat "$CTXNOTE" 2>/dev/null)
t_contains "저장 이유가 프론트매터에 남는다" 'why: "랜딩 CSS 그리드 다시 볼 때"' "$CTXBODY"
t_contains "프로젝트가 배열로 남는다" 'projects: [devtrail, gyoan]' "$CTXBODY"
t_contains "프로젝트 태그가 붙는다" '"project/devtrail"' "$CTXBODY"
t_contains "두 번째 프로젝트 태그도 붙는다" '"project/gyoan"' "$CTXBODY"
t_eq "프론트매터에 why 는 한 줄뿐이다" "1" "$(grep -c '^why:' "$CTXNOTE")"
t_eq "프론트매터에 projects 는 한 줄뿐이다" "1" "$(grep -c '^projects:' "$CTXNOTE")"
t_eq "웹 토큰이 남지 않는다" "0" "$(grep -c '{{WEB_' "$CTXNOTE")"

t_start "모르는 프로젝트 키는 노트를 만들기 전에 거절한다"
before=$(find "$(wdir)" -name '*.md' ! -name '_index.md' | wc -l | tr -d ' ')
out=$(DT_WEB_FETCH_FILE="$T_TMP/web-og.html" wrun capture web --url "https://react.dev/learn" \
  --project 없는프로젝트 --apply 2>&1)
t_ne "모르는 키는 실패한다" "0" "$?"
t_eq "실패하면 노트가 늘지 않는다" "$before" \
  "$(find "$(wdir)" -name '*.md' ! -name '_index.md' | wc -l | tr -d ' ')"

t_start "맥락을 안 적어도 저장은 된다"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://svelte.dev/docs" --apply >/dev/null
PLAIN=$(grep -rlF -- "https://svelte.dev/docs" "$(wdir)" | head -1)
t_ne "맥락 없는 노트도 생긴다" "" "$PLAIN"
t_contains "why 는 빈 값으로 남는다" 'why: ""' "$(cat "$PLAIN")"
t_contains "projects 는 빈 배열로 남는다" 'projects: []' "$(cat "$PLAIN")"

t_start "자료실 표가 저장 이유와 프로젝트를 보여준다"
HUB=$(cat "$(wdir)/_index.md")
t_contains "루트 표에 왜 컬럼이 있다" 'why AS "왜"' "$HUB"
t_contains "루트 표에 프로젝트 컬럼이 있다" 'projects AS "프로젝트"' "$HUB"
t_eq "루트에 링크 표는 하나뿐이다" "1" "$(grep -c '^TABLE description' "$(wdir)/_index.md")"
AREAHUB="$(wdir)/개발/_index.md"
t_file "분야 허브가 있다" "$AREAHUB"
t_contains "분야 표에도 왜 컬럼이 있다" 'why AS "왜"' "$(cat "$AREAHUB")"

# ⚠️ description 은 저장할 때 이미 잡아 둔다. 표에 안 보여주면 "어떤 사이트
#    였는지 모르겠다" 는 불만이 그대로 남는다 — 실제로 그랬다. 사용자가
#    직접 채워야 하는 why 보다 먼저 보여줄 것은 이미 가진 데이터다.
t_contains "루트 표가 설명을 보여준다" 'description AS "설명"' "$HUB"
t_contains "루트 표가 상태를 보여준다" '"상태"' "$HUB"
t_contains "상태는 읽을 수 있는 말로 보여준다" '미정리' "$HUB"
t_contains "분야 허브도 설명을 보여준다" 'description AS "설명"' "$(cat "$AREAHUB")"

t_start "자료실이 분야별 집계를 보여준다"
t_contains "집계 블록이 있다" "devtrail:link-library:rollup:start" "$HUB"
# ⚠️ 한 표에 전부 넣으면 "분야별"이라는 말이 무색하다. 분야마다 표를 따로
#    둬야 그 분야만 보고 싶을 때 그 표만 본다 — 유튜브 인덱스가 그렇다.
t_contains "링크가 있는 분야는 표가 있다" 'area = "frontend"' "$HUB"
t_contains "표 안은 주제로 묶는다" "GROUP BY topic" "$HUB"
# ⚠️ 빈 분야까지 그리면 "No results to show" 가 화면 절반을 먹는다. 없는
#    것을 보여주는 것은 정보가 아니라 소음이다.
t_not_contains "링크가 없는 분야는 안 그린다 (백엔드)" 'area = "backend"' "$HUB"
t_not_contains "링크가 없는 분야는 안 그린다 (인프라)" 'area = "infra"' "$HUB"
# 개수를 못 박지 않는다 — 앞의 테스트가 링크를 더 저장하면 바로 깨진다.
# 지켜야 하는 것은 "그린 분야 = 실제 있는 분야" 라는 관계다.
_areas_in_notes() {
  grep -rh '^area:' "$(wdir)" --include='*.md' 2>/dev/null \
    | sed 's/^area:[[:space:]]*//' | sort -u | grep -c .
}
t_eq "그린 분야 수가 실제 있는 분야 수와 같다" "$(_areas_in_notes)" \
  "$(grep -c '^### ' "$(wdir)/_index.md")"
t_not_contains "한 표에 몰아넣지 않는다" 'GROUP BY area + " / " + topic' "$HUB"
t_contains "링크 수를 센다" 'length(rows.file.link)' "$HUB"
t_eq "집계 블록은 하나뿐이다" "1" "$(grep -c 'rollup:start' "$(wdir)/_index.md")"
# ⚠️ 자료실은 유튜브와 다르다. 유튜브는 노트를 읽으러 가지만, 링크는
#    "그 사이트로 가려고" 저장한다. 노트를 한 번 더 거치면 그만큼 안 간다.
t_contains "집계에서 원문으로 바로 간다" "link(r.url" "$HUB"
t_contains "루트 표의 출처가 원문 링크다" "link(url, source)" "$HUB"
t_contains "분야 허브의 출처도 원문 링크다" "link(url, source)" "$(cat "$AREAHUB")"
# 노트로 가는 길도 남아 있어야 한다 — 메모와 why 는 노트에 있다.
t_contains "노트로 가는 File 컬럼은 남는다" "TABLE description" "$HUB"
# ⚠️ 집계는 자료실을 열자마자 보여야 한다. 표 아래로 밀리면 스크롤해야
#    보이고, 스크롤해야 보이는 것은 안 보는 것과 같다.
t_eq "집계가 최근 목록보다 위에 있다" "ok" \
  "$(awk '/rollup:start/ { r = NR } /^## .*최근/ { t = NR } END { print (r > 0 && t > 0 && r < t) ? "ok" : "no" }' "$(wdir)/_index.md")"

t_start "옛 형식 자료실 표를 새 표로 갈아끼운다"
# 주의: _index.md 는 이미 있으면 다시 쓰지 않는다. 마이그레이션이 없으면
#       새 컬럼은 새 볼트에만 생기고, 쓰던 사람의 화면은 그대로다 - 실제로
#       Dataview 음수 인덱스 버그가 그렇게 조용히 남아 있었다.
OLDHUB="$(wdir)/_index.md"
# 주의: 픽스처 web-og.html 은 canonical 이 고정이라 두 번째 저장부터 전부
#       중복으로 조기 반환된다 - 그러면 마이그레이션이 아예 실행되지 않는다.
# 주의: `^TABLE ` 전체를 바꾸면 분야 목록·집계 블록의 `TABLE WITHOUT ID`
#       까지 링크 표로 만들어 버린다. 링크 표 줄만 정확히 바꾼다.
# 주의: 구분자로 | 를 쓰면 대안 그룹의 | 가 s 명령을 끊는다.
_hub_table() { sed -i.bak -E "s@^TABLE (description|why|type|topic|source) .*@$1@" "$OLDHUB" && rm -f "$OLDHUB.bak"; }
_hub_table 'TABLE type AS "형태", area AS "분야", topic AS "주제", source AS "출처", saved AS "저장일"'
t_contains "옛 표로 되돌렸다(v0.8)" 'TABLE type AS "형태", area AS "분야"' "$(cat "$OLDHUB")"
t_contains "옛 표로 되돌렸다" 'TABLE type AS "형태", area AS "분야"' "$(cat "$OLDHUB")"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://vuejs.org/guide" --apply >/dev/null
t_contains "옛 표가 새 표로 바뀐다" 'why AS "왜"' "$(cat "$OLDHUB")"
t_eq "표가 두 개로 늘지 않는다" "1" "$(grep -c '^TABLE description' "$OLDHUB")"

t_start "사용자가 고친 표는 건드리지 않는다"
# 주의: 마이그레이션이 WHERE url 이 있는 블록을 다 갈아엎으면 사용자가 손으로
#       만든 표가 조용히 사라진다. 우리가 만든 그대로일 때만 바꾼다.
_hub_table 'TABLE source AS "내가 고친 컬럼"'
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://angular.dev/guide" --apply >/dev/null
t_contains "손으로 고친 표는 그대로다" '내가 고친 컬럼' "$(cat "$OLDHUB")"

t_start "아래에 있던 집계를 맨 위로 옮긴다"
# ⚠️ 이전 버전은 집계를 링크 표 **아래**에 끼워 넣었다. 마커만 보고 건너뛰면
#    그 사용자는 영원히 아래에 있는 집계를 본다 — 위치도 갱신 대상이다.
_hub_table 'TABLE description AS "설명", why AS "왜", projects AS "프로젝트", topic AS "주제", source AS "출처"'
awk '/rollup:start/ { skip = 1 } skip { buf = buf $0 "\n" } /rollup:end/ { skip = 0; next } !skip { print } END { printf "%s", buf }' \
  "$OLDHUB" > "$OLDHUB.moved" && mv "$OLDHUB.moved" "$OLDHUB"
t_eq "집계를 맨 아래로 밀어 놨다" "no" \
  "$(awk '/rollup:start/ { r = NR } /^## .*최근/ { t = NR } END { print (r > 0 && t > 0 && r < t) ? "ok" : "no" }' "$OLDHUB")"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://qwik.dev/docs" --apply >/dev/null
t_eq "집계가 맨 위로 올라온다" "ok" \
  "$(awk '/rollup:start/ { r = NR } /^## .*최근/ { t = NR } END { print (r > 0 && t > 0 && r < t) ? "ok" : "no" }' "$OLDHUB")"
t_eq "집계가 두 개로 늘지 않는다" "1" "$(grep -c 'rollup:start' "$OLDHUB")"

t_start "분야가 새로 생기면 그 표도 생긴다"
# ⚠️ 빈 분야를 숨기는 대가로, 링크가 생겼을 때 섹션이 따라 생겨야 한다.
#    안 그러면 저장은 됐는데 집계에 안 보이는 링크가 남는다.
t_not_contains "아직 백엔드 표는 없다" 'area = "backend"' "$(cat "$OLDHUB")"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://www.postgresql.org/docs/" --apply >/dev/null
t_contains "백엔드 표가 생긴다" 'area = "backend"' "$(cat "$OLDHUB")"
t_eq "그린 분야 수가 실제 있는 분야 수와 같다" "$(_areas_in_notes)" \
  "$(grep -c '^### ' "$OLDHUB")"

t_start "DevTrail 이 만들었던 표는 버전마다 전부 알아본다"
# ⚠️ 버전을 하나씩 검사로 적으면 다음 표 변경 때 빠뜨린다 — 실제로 변이가
#    살아남아서 알았다. 정본 목록을 그대로 돌려서 전부 확인한다.
kn() { ( L() { printf '%s' "$1"; }; . "$ROOT/lib/webindex.sh"; _cap_web_table_known "$1" ); }
# ⚠️ 이 숫자는 **줄어들면 안 된다**. 표를 바꿀 때마다 이전 것을 목록에 남기고
#    여기를 1 올린다. 목록에서 지우면 그 버전을 쓰던 사용자는 영원히 옛 표를
#    본다 — 개수를 안 박아 두면 "지워도 테스트는 통과"가 된다. 실제로 그랬다.
t_eq "구버전 root 표를 지우지 않았다" "3" "$(kn root | wc -l | tr -d ' ')"
t_eq "구버전 area 표를 지우지 않았다" "3" "$(kn area | wc -l | tr -d ' ')"
t_eq "구버전 topic 표를 지우지 않았다" "3" "$(kn topic | wc -l | tr -d ' ')"
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n=$((n + 1))
  _hub_table "$line"
  wrun capture web --organize --apply >/dev/null 2>&1
  t_contains "구버전 표 #$n 이 새 표가 된다" 'link(url, source)' "$(cat "$OLDHUB")"
  t_eq "구버전 표 #$n — 표가 늘지 않는다" "1" "$(grep -c '^TABLE description' "$OLDHUB")"
done < <(kn root)

t_start "직전 버전 표도 알아보고 갈아끼운다"
# ⚠️ 표는 앞으로도 바뀐다. "직전 것만" 알아보면 한 버전 건너뛴 사용자는
#    영원히 옛 표를 본다. 우리가 만든 표는 전부 알아봐야 한다.
_hub_table 'TABLE why AS "왜", projects AS "프로젝트", type AS "형태", area AS "분야", topic AS "주제", source AS "출처"'
t_contains "v0.9 표로 되돌렸다" 'topic AS "주제", source AS "출처"' "$(cat "$OLDHUB")"
DT_WEB_FETCH_FILE="$T_TMP/web-title.html" wrun capture web --url "https://solidjs.com/docs" --apply >/dev/null
t_contains "v0.9 표도 새 표가 된다" 'description AS "설명"' "$(cat "$OLDHUB")"
t_eq "표가 두 개로 늘지 않는다" "1" "$(grep -c '^TABLE description' "$OLDHUB")"

t_start "재분류해도 사용자가 붙인 프로젝트는 지킨다"
# ⚠️ --organize 는 tags 를 통째로 다시 쓴다. 분류는 기계가 다시 계산해도
#    되지만 프로젝트는 사람이 붙인 것이라 다시 계산할 수 없다. 여기서
#    안 지키면 재분류 한 번에 조용히 사라진다.
UNSORTED="$(wdir)/공통/미분류"
mkdir -p "$UNSORTED"
cat > "$UNSORTED/2026-08-29-saas-landing-page.md" <<'ORGEOF'
---
tags: ["type/reference", "area/common", "topic/uncategorized", "source/saaslandingpage.com", "project/devtrail"]
type: reference
area: common
topic: uncategorized
source_kind: site
why: "랜딩 히어로 카피 볼 때"
projects: [devtrail]
status: inbox
source: "saaslandingpage.com"
url: "https://saaslandingpage.com/"
title: "SaaS Landing Page"
description: ""
saved: 2026-08-29
---

# SaaS Landing Page
ORGEOF
wrun capture web --organize --apply >/dev/null 2>&1
MOVED=$(grep -rlF 'https://saaslandingpage.com/' "$(wdir)" | head -1)
t_ne "재분류된 노트를 찾는다" "" "$MOVED"
t_contains "미분류에서 벗어난다" "랜딩페이지-레퍼런스" "$MOVED"
t_contains "프로젝트 태그가 살아남는다" '"project/devtrail"' "$(cat "$MOVED")"
t_contains "why 프론트매터가 살아남는다" 'why: "랜딩 히어로 카피 볼 때"' "$(cat "$MOVED")"
t_contains "projects 프론트매터가 살아남는다" 'projects: [devtrail]' "$(cat "$MOVED")"

t_start "정리 한 번으로 자료실 표 전체를 같은 형식으로 맞춘다"
# ⚠️ 링크가 지나간 폴더만 고치면 폴더마다 표가 달라진다. 자료실을 열어 본
#    사람에게 그것은 "덜 바뀐 것"이 아니라 "고장난 것"으로 보인다.
STALE="$(wdir)/개발/데이터-AI/데이터소스"
mkdir -p "$STALE"
cat > "$STALE/_index.md" <<'STALEEOF'
---
type: moc
scope: library-links
library_level: topic
library_area: data-ai
library_topic: data-sources
---

# 🔗 데이터소스

```dataview
TABLE type AS "형태", source AS "출처", saved AS "저장일"
FROM "x"
WHERE url
SORT saved DESC
```
STALEEOF
_hub_table 'TABLE type AS "형태", area AS "분야", topic AS "주제", source AS "출처", saved AS "저장일"'
wrun capture web --organize --apply >/dev/null 2>&1
t_contains "루트 표가 맞춰진다" 'why AS "왜"' "$(cat "$OLDHUB")"
t_contains "링크가 지나가지 않은 허브도 맞춰진다" 'why AS "왜"' "$(cat "$STALE/_index.md")"
t_eq "허브마다 링크 표는 하나뿐이다" "1" "$(grep -c '^TABLE description' "$STALE/_index.md")"

t_start "기존 링크에 맥락 칸을 만들되 값은 지어내지 않는다"
# ⚠️ 칸이 없으면 Obsidian 속성 패널에 줄이 안 보인다. "표에서 비어 보이니
#    채우세요" 는 채울 자리가 있을 때만 성립하는 안내다.
OLDNOTE="$(wdir)/공통/미분류/2026-08-25-google.md"
mkdir -p "$(dirname "$OLDNOTE")"
cat > "$OLDNOTE" <<'CTXEOF'
---
tags: ["type/reference", "area/common", "topic/uncategorized", "source/www.google.com"]
type: reference
area: common
topic: uncategorized
source_kind: site
status: inbox
source: "www.google.com"
url: "https://www.google.com/"
title: "Google"
saved: 2026-08-25
---

# Google
CTXEOF
wrun capture web --organize --apply >/dev/null 2>&1
CTXBODY=$(cat "$OLDNOTE")
t_contains "why 칸이 생긴다" 'why: ""' "$CTXBODY"
t_contains "projects 칸이 생긴다" 'projects: []' "$CTXBODY"
# ⚠️ 값을 지어내면 그 노트를 믿을 수 없게 된다. 비어 있어야 한다.
t_eq "why 값은 비어 있다" "1" "$(grep -cx 'why: ""' "$OLDNOTE")"
t_eq "projects 값은 비어 있다" "1" "$(grep -cx 'projects: \[\]' "$OLDNOTE")"
t_contains "기존 필드는 그대로다" 'source_kind: site' "$CTXBODY"
t_contains "본문은 그대로다" '# Google' "$CTXBODY"
# 두 번 돌려도 칸이 두 개가 되지 않는다.
wrun capture web --organize --apply >/dev/null 2>&1
t_eq "다시 돌려도 why 는 한 줄뿐이다" "1" "$(grep -c '^why:' "$OLDNOTE")"
t_eq "다시 돌려도 projects 는 한 줄뿐이다" "1" "$(grep -c '^projects:' "$OLDNOTE")"

t_end
