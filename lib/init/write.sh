#!/usr/bin/env bash
# DevTrail — init: 설정 저장과 산출물 생성.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── write ────────────────────────────────────────────────────────────────────
# 개행 목록 → JSON 배열. 빈 입력은 [] 가 된다.
_dt_json_array() {
  printf '%s' "${1-}" | jq -R -s 'split("\n") | map(select(length > 0))'
}

# 개행 목록 → { "이름": "이름", ... } 항등 매핑.
# project_groups 는 '레포명 → 개발일지 섹션명' 이다. 기본은 레포명 그대로 쓰고,
# fe/be 로 나뉜 레포를 한 섹션에 모으고 싶으면 나중에 값만 바꾸면 된다.

# 개행 목록 → { "이름": "이름", ... } 항등 매핑.
# project_groups 는 '레포명 → 개발일지 섹션명' 이다. 기본은 레포명 그대로 쓰고,
# fe/be 로 나뉜 레포를 한 섹션에 모으고 싶으면 나중에 값만 바꾸면 된다.
_dt_json_identity() {
  printf '%s' "${1-}" \
    | jq -R -s 'split("\n") | map(select(length > 0)) | map({key: ., value: .}) | from_entries'
}


_init_write_config() {
  local backend="$1" vault="$2" root="$3" gh_user="$4" ai="$5"
  local enabled=true; [ "$ai" = none ] && { enabled=false; ai=claude; }

  jq -n \
    --arg backend "$backend" --arg vault "$vault" --arg root "$root" \
    --arg gh "$gh_user" --arg ai "$ai" --argjson enabled "$enabled" \
    --argjson syncrepos "$(_dt_json_array "${DT_SYNC_REPOS:-}")" \
    --argjson projects "$(_dt_json_array "${DT_PROJECTS:-}")" \
    --argjson groups "$(_dt_json_identity "${DT_PROJECTS:-}")" \
    --arg lang "${DT_LANG:-ko}" \
    --arg mode "${DT_MODE:-existing}" \
    --argjson adopted "${DT_DIRS:-\{\}}" \
    --argjson modules "$(_dt_json_array "${DT_MODULES:-devlog}")" \
    --arg python "$(command -v python3 || echo /usr/bin/python3)" \
    --arg brew "$(brew --prefix 2>/dev/null || echo /opt/homebrew)" \
    --arg src "${DT_SRC_ROOT:-$HOME/Desktop}" \
    --arg backup "$DEVTRAIL_HOME/vault-backup" \
    -f /dev/stdin > "$CONFIG_FILE" <<'JQ'
{
  version: 3,
  lang: $lang,
  install: { mode: $mode, modules: $modules },
  vault:   { backend: $backend, path: $vault, root: $root },
  dirs:    $adopted,
  naming:  { devlog_file: "{{DATE}} devlog.md", weekly_file: "{{ISOWEEK}} weekly.md",
             date_format: "%Y-%m-%d" },
  headings:{ issues_pr: "## Issues / PRs", worklog: "## Work log",
             morning: "### Morning", youtube: "## YouTube" },
  github:  { user: $gh, repos: $projects, project_groups: $groups },
  sync:    { source_root: $src, repos: $syncrepos, exclude: [
             "node_modules","dist","build",".next",".git",".DS_Store",
             "*.log","*.ts","*.tsx","*.js","*.jsx","*.mjs","*.py","*.pyc",
             "__pycache__","*.sh" ] },
  linear:  { enabled: false, keychain_service: "devtrail-linear-api-key" },
  ai:      { provider: $ai, summary_enabled: $enabled },
  backup:  { enabled: true, repo_path: $backup },
  schedule:{ daily_hour: 10, repodocs_interval_sec: 600 },
  bin:     { python: $python, brew_prefix: $brew }
}
JQ
  ok "설정 저장: $CONFIG_FILE"
}

# 템플릿의 {{VAR}}를 설정값으로 치환해 ~/.devtrail/scripts/ 에 생성한다.

# 템플릿의 {{VAR}}를 설정값으로 치환해 ~/.devtrail/scripts/ 에 생성한다.
_init_render_scripts() {
  local src="$DEVTRAIL_ROOT/templates/scripts" dst="$DEVTRAIL_HOME/scripts"
  [ -d "$src" ] || { warn "스크립트 템플릿 없음: $src"; return; }
  mkdir -p "$dst"

  local n=0
  for t in "$src"/*.sh.tmpl; do
    [ -e "$t" ] || continue
    local name; name=$(basename "$t" .tmpl)
    sed \
      -e "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" \
      -e "s|{{CONFIG_FILE}}|$CONFIG_FILE|g" \
      "$t" > "$dst/$name"
    chmod +x "$dst/$name"
    n=$((n+1))
  done
  ok "스크립트 생성: ${n}개 → $dst"
  dim "   설정값은 실행 시점에 $CONFIG_FILE 에서 읽습니다(하드코딩 없음)"
}

# Obsidian 설정은 여기서 건드리지 않는다.
#
# 예전에는 templates/obsidian/ 을 볼트의 .obsidian/ 으로 통째로 복사했다.
# 셋 다 틀렸다: 셸커맨드는 .obsidian/plugins/obsidian-shellcommands/data.json
# 에 있어야 하고, 노트 템플릿은 .obsidian/ 이 아니라 볼트 안 templates 폴더에
# 들어가야 하며, {{DEVTRAIL_HOME}} 치환도 하지 않아 플레이스홀더가 그대로
# 남았다. 게다가 '.obsidian 이 없을 때만' 돌았는데, .obsidian 이 없다는 건
# 볼트를 한 번도 안 열었다는 뜻이라 플러그인도 없는 상태였다.
#
# 그 일은 `devtrail obsidian` 이 제대로 한다(병합·치환·백업). 여기서는
# 그 명령을 부르기 위한 선행 조건만 안내한다.

# ── 스캐폴딩 ─────────────────────────────────────────────────────────────────
_init_scaffold() {
  echo
  printf '%s\n' "${C_BOLD}볼트 구조${C_RESET}"
  local mods; mods=$(printf '%s' "${DT_MODULES:-devlog}" | tr '\n' ' ')
  dim "   모듈: $mods"
  # augment 는 없는 것만 만든다. 기존 폴더는 그대로 둔다.
  . "$DEVTRAIL_ROOT/lib/augmentcmd.sh"
  # shellcheck disable=SC2086
  augment_cmd $mods --apply
}

# ── prompts ──────────────────────────────────────────────────────────────────

# ── AI 스킬 ──────────────────────────────────────────────────────────────────
# Claude Code 가 있을 때만. 없어도 DevTrail 은 그대로 동작한다.
_init_skills() {
  [ -d "$HOME/.claude" ] || {
    echo
    dim "   Claude Code 를 설치하면 AI 스킬 8종을 함께 쓸 수 있습니다"
    dim "   설치 후: devtrail skills install"
    return 0
  }
  echo
  . "$DEVTRAIL_ROOT/lib/skillcmd.sh"
  skills_cmd install
}

# ── 스캐폴딩 ─────────────────────────────────────────────────────────────────

# Obsidian 설정은 여기서 건드리지 않는다.
#
# 예전에는 templates/obsidian/ 을 볼트의 .obsidian/ 으로 통째로 복사했다.
# 셋 다 틀렸다: 셸커맨드는 .obsidian/plugins/obsidian-shellcommands/data.json
# 에 있어야 하고, 노트 템플릿은 .obsidian/ 이 아니라 볼트 안 templates 폴더에
# 들어가야 하며, {{DEVTRAIL_HOME}} 치환도 하지 않아 플레이스홀더가 그대로
# 남았다. 게다가 '.obsidian 이 없을 때만' 돌았는데, .obsidian 이 없다는 건
# 볼트를 한 번도 안 열었다는 뜻이라 플러그인도 없는 상태였다.
#
# 그 일은 `devtrail obsidian` 이 제대로 한다(병합·치환·백업). 여기서는
# 그 명령을 부르기 위한 선행 조건만 안내한다.
_init_next_steps() {
  local vault="$1"
  echo
  ok "셋업 완료"
  echo
  printf '%s\n' "${C_BOLD}다음 단계${C_RESET}"
  info "  1) Obsidian에서 볼트를 엽니다: $vault"
  dim "     처음 열어야 .obsidian/ 폴더가 생깁니다."
  info "  2) 플러그인 4개를 설치·활성화하고 Obsidian을 재시작합니다"
  dim "     Shell commands · Templater · Dataview · Auto Note Mover"
  info "  3) devtrail obsidian             # 셸커맨드 병합 · 노트 템플릿 설치"
  dim "     2번을 마치기 전에 실행하면 셸커맨드 병합을 건너뜁니다."
  info "  4) devtrail doctor               # 진단 — 여기서 ❌가 없어야 합니다"
  info "  5) devtrail install-schedule     # 자동 실행 등록"
  if [ "${DT_MODE:-existing}" != new ]; then
    echo
    dim "   기존 볼트이므로 자동 이동은 수동(Manual)으로 시작합니다."
    dim "   무엇이 달라지는지 먼저 보려면: devtrail scan"
  fi
  echo
  dim "설정: $CONFIG_FILE"
  dim "스크립트: $DEVTRAIL_HOME/scripts/"
}
