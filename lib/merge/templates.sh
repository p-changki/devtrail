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
  step "노트 템플릿"
  local dest; dest="$(vault_root)/$(dt_dir templates)"
  local src="$DEVTRAIL_ROOT/preset/templates"
  [ -d "$src" ] || { warn "템플릿 없음: $src"; return 0; }

  mkdir -p "$dest"
  local n=0 skipped=0 f name
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if [ -f "$dest/$name" ]; then
      skipped=$((skipped + 1)); continue
    fi
    cp "$f" "$dest/$name" || { warn "복사 실패: $name"; continue; }
    n=$((n + 1))
  done
  ok "템플릿 ${n}개 설치 (기존 유지 ${skipped}개) → $(dt_dir templates)"

  local sections
  sections=$(jq -r '(.github.project_groups // {}) | [.[]] | unique | .[]' "$CONFIG_FILE" 2>/dev/null)
  if [ -n "$sections" ]; then
    dim "     PR 요약 섹션: $(printf '%s' "$sections" | tr '\n' ' ')"
    dim "     개발일지를 만들 때 선택창에서 고르면 #### 소제목이 생깁니다."
  else
    warn "     project_groups 가 비어 있어 PR 요약이 넣을 자리를 못 찾습니다"
    dim "     devtrail init 을 다시 돌리거나 설정의 github.project_groups 를 채우세요."
  fi
}

# ── Templater 폴더매핑 · 데일리노트 ─────────────────────────────────────────
#
# 이 둘이 있어야 "노트를 만들면 양식이 채워진다"가 성립한다.
# trigger_on_file_creation 이 꺼져 있으면 아무 일도 일어나지 않는다.
