#!/usr/bin/env bash
# DevTrail — 링크 자료실 허브(_index.md)의 생성·갱신.
#
# 허브는 사용자가 실제로 보는 화면이다. 표 한 줄이 틀리면 노트는 멀쩡한데
# 화면만 조용히 비거나 엉뚱해진다 — 실제로 Dataview 음수 인덱스 버그가
# 그렇게 며칠을 버텼다. 그래서 표 문자열의 정본을 여기 한곳에 둔다.
# webcapture.sh 가 URL 안전 검사·저널 함수를 준비한 뒤 불러온다.

# 자료실 표 한 줄의 정본. 새로 만드는 표와 옛 표 갈아끼우기가 같은 문자열을
# 쓴다. 두 곳에 따로 적으면 마이그레이션이 자기가 만든 표를 못 알아본다.
#
# ⚠️ `왜`가 첫 컬럼인 이유: URL 만 쌓인 표는 나중에 본인도 어떤 사이트였는지
#    모른다. 저장 이유는 사람만 아는 정보라 기계가 채울 수 없다.
_cap_web_table_line() {
  local why ty tp sr pj de st
  why=$(L '왜' 'Why'); pj=$(L '프로젝트' 'Projects'); ty=$(L '형태' 'Type')
  tp=$(L '주제' 'Topic'); sr=$(L '출처' 'Source'); de=$(L '설명' 'What it is')
  st=$(_cap_web_status_expr)
  case "$1" in
    root) printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", topic AS "%s", link(url, source) AS "%s", %s' "$de" "$why" "$pj" "$tp" "$sr" "$st" ;;
    area) printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", topic AS "%s", type AS "%s", link(url, source) AS "%s"' "$de" "$why" "$pj" "$tp" "$ty" "$sr" ;;
    *)    printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", type AS "%s", link(url, source) AS "%s"' "$de" "$why" "$pj" "$ty" "$sr" ;;
  esac
}

# status 는 inbox|reviewed|applied|archived 다. 값을 그대로 보여주면 표에서
# 읽히지 않는다 — 사람이 읽는 말로 바꾼다.
_cap_web_status_expr() {
  printf 'choice(status = "inbox", "%s", choice(status = "reviewed", "%s", choice(status = "applied", "%s", "%s"))) AS "%s"' \
    "$(L '🆕 미정리' '🆕 New')" "$(L '👀 검토' '👀 Reviewed')" \
    "$(L '✅ 적용' '✅ Applied')" "$(L '📦 보관' '📦 Archived')" "$(L '상태' 'Status')"
}

# DevTrail 이 지금까지 만든 표들. 이 중 하나와 **정확히** 같을 때만
# 갈아끼운다 — 사용자가 손으로 고친 표를 조용히 지우지 않기 위해서다.
#
# ⚠️ "직전 버전만" 알아보면 한 버전 건너뛴 사용자는 영원히 옛 표를 본다.
#    표를 바꿀 때마다 이전 것을 여기에 남긴다. 지우지 않는다.
_cap_web_table_known() {
  local ty ar tp sr sv why pj de st
  ty=$(L '형태' 'Type'); ar=$(L '분야' 'Area'); tp=$(L '주제' 'Topic')
  sr=$(L '출처' 'Source'); sv=$(L '저장일' 'Saved'); de=$(L '설명' 'What it is')
  why=$(L '왜' 'Why'); pj=$(L '프로젝트' 'Projects'); st=$(_cap_web_status_expr)
  case "$1" in
    root)
      printf 'TABLE type AS "%s", area AS "%s", topic AS "%s", source AS "%s", saved AS "%s"\n' "$ty" "$ar" "$tp" "$sr" "$sv"
      printf 'TABLE why AS "%s", projects AS "%s", type AS "%s", area AS "%s", topic AS "%s", source AS "%s"\n' "$why" "$pj" "$ty" "$ar" "$tp" "$sr"
      printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", topic AS "%s", source AS "%s", %s\n' "$de" "$why" "$pj" "$tp" "$sr" "$st" ;;
    area)
      printf 'TABLE topic AS "%s", type AS "%s", source AS "%s", saved AS "%s"\n' "$tp" "$ty" "$sr" "$sv"
      printf 'TABLE why AS "%s", projects AS "%s", topic AS "%s", type AS "%s", source AS "%s"\n' "$why" "$pj" "$tp" "$ty" "$sr"
      printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", topic AS "%s", type AS "%s", source AS "%s"\n' "$de" "$why" "$pj" "$tp" "$ty" "$sr" ;;
    *)
      printf 'TABLE type AS "%s", source AS "%s", saved AS "%s"\n' "$ty" "$sr" "$sv"
      printf 'TABLE why AS "%s", projects AS "%s", type AS "%s", source AS "%s"\n' "$why" "$pj" "$ty" "$sr"
      printf 'TABLE description AS "%s", why AS "%s", projects AS "%s", type AS "%s", source AS "%s"\n' "$de" "$why" "$pj" "$ty" "$sr" ;;
  esac
}

# ⚠️ _index.md 는 이미 있으면 다시 쓰지 않는다(_cap_web_write_index). 그래서
#    이 함수가 없으면 새 컬럼은 새 볼트에만 생기고, 쓰던 사람의 화면은 영원히
#    그대로다. Dataview 음수 인덱스 버그가 실제로 그렇게 조용히 남아 있었다.
_cap_web_ensure_link_table() {
  local file="$1" kind="$2" new known tmp
  [ -f "$file" ] || return 0
  new=$(_cap_web_table_line "$kind")
  known=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-known.XXXXXX") || return 1
  _cap_web_table_known "$kind" > "$known" || { rm -f "$known"; return 1; }
  tmp=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-table.XXXXXX") || { rm -f "$known"; return 1; }
  awk -v new="$new" '
    NR == FNR { k[$0] = 1; next }
    ($0 in k) { print new; next }
    { print }
  ' "$known" "$file" > "$tmp" || { rm -f "$known" "$tmp"; return 1; }
  rm -f "$known"
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  cmp -s "$file" "$tmp" && { rm -f "$tmp"; return 0; }
  jr_backup "$file" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# 분야별 집계. 폴더를 열지 않고도 "어느 분야에 얼마나 쌓였는지"가 한눈에
# 보인다. 마커로 감싸서 나중에 통째로 갈아끼울 수 있게 한다.
# 자료실에 실제로 링크가 있는 분야만 골라낸다. 정본 순서를 먼저 따르고,
# 목록에 없는 분야(사용자가 직접 적은 값)는 뒤에 붙인다 — 모르는 값이라고
# 화면에서 지워 버리면 저장은 됐는데 어디에도 안 보이는 링크가 생긴다.
_cap_web_areas_present() {
  local dir="$1" found known a
  [ -d "$dir" ] || return 0
  found=$(find "$dir" -type f -name '*.md' ! -name '_index.md' -exec grep -h '^area:' {} + 2>/dev/null \
    | sed 's/^area:[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u)
  [ -n "$found" ] || return 0
  known=""
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    printf '%s\n' "$found" | grep -qxF "$a" && { printf '%s\n' "$a"; known="$known$a
"; }
  done <<AREAEOF
$(cap_taxonomy_areas)
AREAEOF
  printf '%s\n' "$found" | while IFS= read -r a; do
    [ -n "$a" ] || continue
    printf '%s' "$known" | grep -qxF "$a" || printf '%s\n' "$a"
  done
}

# ⚠️ 빈 분야까지 그리면 "No results to show" 가 화면 절반을 먹는다. Dataview
#    는 제목을 숨길 수 없으니 — 제목은 그냥 마크다운이다 — 만들 때 거른다.
#    그 대가로 링크가 생기면 표도 따라 생겨야 한다. 이 블록은 저장·정리
#    때마다 통째로 다시 만들어지므로 그 조건이 지켜진다.
_cap_web_rollup_block() {
  local from="$1" dir="$2" a n=0
  printf '<!-- devtrail:link-library:rollup:start -->\n'
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    n=$((n + 1))
    printf '\n### %s (area: %s)\n\n' "$(cap_taxonomy_area_label "$a")" "$a"
    cat <<EOF
\`\`\`dataview
TABLE WITHOUT ID
  key AS "$(L '주제' 'Topic')",
  length(rows.file.link) AS "$(L '링크 수' 'Links')",
  map(rows, (r) => link(r.url, r.title)) AS "$(L '바로 열기' 'Open')"
FROM "$from"
WHERE url AND area = "$a"
GROUP BY topic
SORT key ASC
\`\`\`
EOF
  done <<PRESENTEOF
$(_cap_web_areas_present "$dir")
PRESENTEOF
  [ "$n" -gt 0 ] || printf '\n%s\n' "$(L '아직 저장한 링크가 없습니다.' 'No links saved yet.')"
  printf '<!-- devtrail:link-library:rollup:end -->\n'
}

# 집계 블록을 자료실 맨 위 — 첫 `## ` 제목 앞 — 에 둔다.
#
# ⚠️ "마커가 있으면 건너뛴다" 로 두면 안 된다. 이전 버전은 집계를 링크 표
#    **아래**에 끼워 넣었고, 그 사용자는 영원히 아래에 있는 집계를 본다.
#    스크롤해야 보이는 것은 안 보는 것과 같다. 그래서 있으면 걷어내고
#    맨 위에 다시 놓는다 — 내용이 같고 자리도 같으면 파일을 건드리지 않는다.
_cap_web_ensure_rollup() {
  local file="$1" from="$2" tmp stripped block heading dir
  [ -f "$file" ] || return 0
  dir=$(dirname "$file")
  heading="## $(L '분야별 집계' 'By area')"
  block=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-rollup.XXXXXX") || return 1
  { printf '%s\n\n' "$heading"; _cap_web_rollup_block "$from" "$dir"; printf '\n'; } > "$block" \
    || { rm -f "$block"; return 1; }

  # 1단계 — 우리가 만든 제목과 마커 블록을 걷어낸다. 사용자가 제목을 바꿨으면
  #          제목은 남는다. 남의 글을 지우느니 제목 하나가 남는 편이 낫다.
  stripped=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-rollup1.XXXXXX") || { rm -f "$block"; return 1; }
  awk -v heading="$heading" '
    $0 == heading { pending_blank = 1; next }
    /devtrail:link-library:rollup:start/ { skip = 1; next }
    skip && /devtrail:link-library:rollup:end/ { skip = 0; pending_blank = 1; next }
    skip { next }
    pending_blank && $0 == "" { pending_blank = 0; next }
    { pending_blank = 0; print }
  ' "$file" > "$stripped" || { rm -f "$block" "$stripped"; return 1; }

  # 2단계 — 첫 `## ` 제목 앞에 다시 넣는다. 제목이 없으면 끝에 붙인다.
  tmp=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-rollup2.XXXXXX") || { rm -f "$block" "$stripped"; return 1; }
  awk -v bfile="$block" '
    function emit(   line) { while ((getline line < bfile) > 0) print line; close(bfile) }
    !done && /^## / { emit(); done = 1 }
    { print }
    END { if (!done) emit() }
  ' "$stripped" > "$tmp" || { rm -f "$block" "$stripped" "$tmp"; return 1; }
  rm -f "$block" "$stripped"
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  cmp -s "$file" "$tmp" && { rm -f "$tmp"; return 0; }
  jr_backup "$file" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# 링크 자료실의 허브는 새 링크를 저장할 때만, 없는 파일에만 만든다. 기존
# 사용자가 직접 정리한 _index는 절대 덮어쓰지 않는다.
_cap_web_index_body() {
  local kind="$1" title="$2" from="$3" area="${4:-}" topic="${5:-}" dir="${6:-}"
  case "$kind" in
    root)
      cat <<EOF
---
type: moc
scope: library-links
library_level: root
---

# 🔗 $(L '링크 자료실' 'Link library')

$(L 'URL만 저장하면 분야와 용도별로 정리됩니다. 아래 표와 폴더에서 바로 찾으세요.' 'Saved URLs are organized by area and purpose. Browse the folders or use the table below.')

## $(L '분야별 집계' 'By area')

$(_cap_web_rollup_block "$from" "$dir")

## $(L '최근 저장한 링크' 'Recently saved links')

## $(L '분야별 자료실' 'Browse by area')

<!-- devtrail:link-library:areas:start -->

\`\`\`dataview
TABLE WITHOUT ID link(file.path, regexreplace(file.folder, ".*/", "")) AS "$(L '분야' 'Area')"
FROM "$from"
WHERE scope = "library-links" AND library_level = "area"
SORT file.folder ASC
\`\`\`

<!-- devtrail:link-library:areas:end -->

\`\`\`dataview
$(_cap_web_table_line root)
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
    area)
      cat <<EOF
---
type: moc
scope: library-links
library_level: area
library_area: $area
---

# 🔗 $title

$(L '세부 용도 폴더를 열거나, 아래 표에서 자료를 바로 찾으세요.' 'Open a purpose folder or find a link directly in the table below.')

\`\`\`dataview
$(_cap_web_table_line area)
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
    *)
      cat <<EOF
---
type: moc
scope: library-links
library_level: topic
library_area: $area
library_topic: $topic
---

# 🔗 $title

\`\`\`dataview
$(_cap_web_table_line topic)
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
  esac
}

# 이전 버전에서 만들어진 루트 자료실에는 분야별 허브 목록이 없다. 사용자가
# 직접 쓴 본문은 건드리지 않고, 전용 마커가 없을 때에만 목록 블록을 끝에
# 한 번 덧붙인다. 호출 시점은 항상 jr_begin 뒤라 undo로 원래 파일로 돌아간다.
_cap_web_ensure_root_navigation() {
  local file="$1" from="$2" tmp
  [ -f "$file" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-root.XXXXXX") || return 1

  if grep -qF '<!-- devtrail:link-library:areas:start -->' "$file"; then
    # 기존 인덱스도 같은 마커 안의 Dataview 블록만 교체한다. 사용자가 쓴
    # 나머지 본문은 건드리지 않는다. `_index` 대신 실제 분야명이 보이게 한다.
    # ⚠️ 폴더의 마지막 조각을 `split(...)[-1]` 로 뽑지 않는다 — Dataview 는
    #    음수 인덱스를 지원하지 않아 null 을 돌려주고, 링크가 파일명(`_index`)
    #    으로 표시된다. 에러가 나지 않아 조용히 틀린다. 실제로 그랬다.
    awk -v from="$from" -v label="$(L '분야' 'Area')" '
      /<!-- devtrail:link-library:areas:start -->/ {
        print
        print "```dataview"
        print "TABLE WITHOUT ID link(file.path, regexreplace(file.folder, \".*/\", \"\")) AS \"" label "\""
        print "FROM \"" from "\""
        print "WHERE scope = \"library-links\" AND library_level = \"area\""
        print "SORT file.folder ASC"
        print "```"
        skipping = 1
        next
      }
      skipping && /<!-- devtrail:link-library:areas:end -->/ { print; skipping = 0; next }
      !skipping { print }
    ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    cp "$file" "$tmp" || { rm -f "$tmp"; return 1; }
    cat >> "$tmp" <<EOF

## $(L '분야별 자료실' 'Browse by area')

<!-- devtrail:link-library:areas:start -->
\`\`\`dataview
TABLE WITHOUT ID link(file.path, regexreplace(file.folder, ".*/", "")) AS "$(L '분야' 'Area')"
FROM "$from"
WHERE scope = "library-links" AND library_level = "area"
SORT file.folder ASC
\`\`\`
<!-- devtrail:link-library:areas:end -->
EOF
  fi
  cmp -s "$file" "$tmp" && { rm -f "$tmp"; return 0; }
  jr_backup "$file" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

_cap_web_write_index() {
  local abs="$1" rel="$2" kind="$3" title="$4" area="${5:-}" topic="${6:-}" file stage tmp
  file="$abs/_index.md"
  [ -f "$file" ] && return 0
  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-index.XXXXXX") || return 1
  _cap_web_index_body "$kind" "$title" "$(vault_rel "$rel")" "$area" "$topic" "$abs" > "$stage" || { rm -f "$stage"; return 1; }
  tmp="$abs/.devtrail-index-$$.tmp"
  cp "$stage" "$tmp" && mv "$tmp" "$file" || { rm -f "$stage" "$tmp"; return 1; }
  rm -f "$stage"; jr_created "$file"
}

# frontmatter 의 `projects: [a, b]` 를 JSON 배열로 읽는다. 없으면 [].
#
# ⚠️ --organize 는 tags 를 통째로 다시 쓴다. 여기서 기존 프로젝트를 읽어
#    되돌려 놓지 않으면, 재분류 한 번에 사용자가 붙인 project/<키> 태그가
#    조용히 사라진다. projects 줄만 남고 태그는 없어져 검색이 어긋난다.
_cap_web_fm_projects() {
  local raw
  raw=$(_cap_web_fm_value "$1" projects)
  case "$raw" in ''|'[]') printf '[]'; return 0 ;; esac
  printf '%s' "$raw" | sed 's/^\[//; s/\]$//' | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' \
    | jq -Rsc 'split("\n") | map(select(length > 0)) | unique' 2>/dev/null \
    || printf '[]'
}

# 기존 링크에 비어 있는 맥락 칸을 만들어 둔다. **값은 채우지 않는다** —
# 저장 이유는 사람만 아는 정보라 기계가 지어내면 그 노트를 못 믿게 된다.
#
# ⚠️ 칸이 없으면 Obsidian 속성 패널에 줄 자체가 안 보인다. 그러면 "표에서
#    비어 보이니 채우세요" 라는 안내가 성립하지 않는다 — 노트마다 「속성
#    추가」를 눌러야 하고, 그러면 아무도 안 채운다.
# 반환값: 0 바꿨음 · 2 바꿀 것 없음 · 1 실패
_cap_web_ensure_context_fields() {
  local file="$1" add_why=0 add_pj=0 tmp
  grep -qE '^why:' "$file" || add_why=1
  grep -qE '^projects:' "$file" || add_pj=1
  [ "$add_why" = 1 ] || [ "$add_pj" = 1 ] || return 2
  tmp=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-ctx.XXXXXX") || return 1
  DT_C_WHY="$add_why" DT_C_PJ="$add_pj" awk '
    function emit() {
      if (ENVIRON["DT_C_WHY"] == "1") print "why: \"\""
      if (ENVIRON["DT_C_PJ"] == "1") print "projects: []"
    }
    NR == 1 && $0 == "---" { infront = 1; print; next }
    infront && $0 == "---" { if (!done) { emit(); done = 1 } print; infront = 0; next }
    infront { print; if (!done && /^source_kind:/) { emit(); done = 1 } next }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  jr_backup "$file" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}
