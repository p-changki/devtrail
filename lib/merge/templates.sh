#!/usr/bin/env bash
# DevTrail — 노트 템플릿 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── 노트 템플릿 ──────────────────────────────────────────────────────────────
#
# 없을 때만 만든다. 사용자가 고친 템플릿을 덮어쓰지 않는다.
#
# 템플릿에는 경로가 한 글자도 없다 — 실행 시점에 _devtrail-paths.md 를
# 파일명으로 찾아 읽는다. 그래서 여기서는 치환 없이 그대로 복사한다.
_ob_templates() {
  step "$(L "노트 템플릿" "Note templates")"
  local dest; dest="$(vault_root)/$(dt_dir templates)"
  local base="$DEVTRAIL_ROOT/preset/templates"
  local src="$base/$(dt_lang)"
  [ -d "$base/ko" ] || { warn "$(L "템플릿 없음" "Template missing"): $base"; return 0; }

  mkdir -p "$dest"
  local n=0 skipped=0 fb=0 f name

  # 선택한 언어의 템플릿을 먼저 깐다.
  if [ -d "$src" ]; then
    for f in "$src"/*.md; do
      [ -e "$f" ] || continue
      name=$(basename "$f")
      [ -f "$dest/$name" ] && { skipped=$((skipped + 1)); continue; }
      cp "$f" "$dest/$name" || { warn "$(L "복사 실패" "Copy failed"): $name"; continue; }
      n=$((n + 1))
    done
  fi

  # ⚠️ 번역이 없는 템플릿은 한국어로 채운다.
  #    번역이 늦었다고 템플릿이 통째로 없는 것보다, 한국어로라도 있는 편이 낫다.
  #    같은 이름이 이미 있으면 건드리지 않으므로 영어판이 언제나 이긴다.
  if [ "$(dt_lang)" != "ko" ]; then
    for f in "$base/ko"/*.md; do
      [ -e "$f" ] || continue
      name=$(basename "$f")
      # 영어판이 있으면 그쪽 이름으로 이미 깔렸다. 한국어 이름은 건너뛴다.
      _tpl_has_translation "$src" "$name" && continue
      [ -f "$dest/$name" ] && { skipped=$((skipped + 1)); continue; }
      cp "$f" "$dest/$name" || continue
      fb=$((fb + 1))
    done
  fi

  ok "$(L "템플릿 ${n}개 설치 (기존 유지 ${skipped}개)" \
          "${n} templates installed (${skipped} kept)") → $(dt_dir templates)"
  [ "$fb" -gt 0 ] && dim "     $(L "번역 대기 ${fb}개는 한국어로 설치했습니다" \
                "${fb} not translated yet — installed in Korean")"

  local sections
  sections=$(jq -r '(.github.project_groups // {}) | [.[]] | unique | .[]' "$CONFIG_FILE" 2>/dev/null)
  if [ -n "$sections" ]; then
    dim "     $(L "PR 요약 섹션" "PR summary sections"): $(printf '%s' "$sections" | tr '\n' ' ')"
    dim "     $(L "개발일지를 만들 때 선택창에서 고르면 #### 소제목이 생깁니다." \
                "Pick them when you create a devlog and the #### headings appear.")"
  else
    warn "     $(L "project_groups 가 비어 있어 PR 요약이 넣을 자리를 못 찾습니다" \
                 "project_groups is empty, so PR summaries have nowhere to go")"
    dim "     $(L "devtrail init 을 다시 돌리거나 설정의 github.project_groups 를 채우세요." \
                "Run devtrail init again, or fill in github.project_groups.")"
  fi
}

# ── Templater 폴더매핑 · 데일리노트 ─────────────────────────────────────────
#
# 이 둘이 있어야 "노트를 만들면 양식이 채워진다"가 성립한다.
# trigger_on_file_creation 이 꺼져 있으면 아무 일도 일어나지 않는다.

# 이 한국어 템플릿에 대응하는 번역이 있는가.
# 매핑은 preset/templates/<lang>/_map.tsv 에 둔다: <한국어 파일명><TAB><번역 파일명>
_tpl_has_translation() {
  # ⚠️ local a="$1" b="$a/x" 는 set -u 에서 죽는다.
  #    bash 가 이름을 먼저 전부 지역화(=unset)한 뒤 대입하기 때문이다.
  local dir="$1" ko_name="$2"
  local map="$dir/_map.tsv"
  [ -f "$map" ] || return 1
  grep -q "^$(printf '%s' "$ko_name" | sed 's/[[\.*^$/]/\\&/g')	" "$map"
}
