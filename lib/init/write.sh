#!/usr/bin/env bash
# DevTrail — init: 설정 저장과 산출물 생성.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── write ────────────────────────────────────────────────────────────────────


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
  ok "$(L "설정 저장" "Config saved"): $CONFIG_FILE"
}

# 템플릿의 {{VAR}}를 설정값으로 치환해 ~/.devtrail/scripts/ 에 생성한다.

# 템플릿의 {{VAR}}를 설정값으로 치환해 ~/.devtrail/scripts/ 에 생성한다.
_init_render_scripts() {
  local src="$DEVTRAIL_ROOT/templates/scripts" dst="$DEVTRAIL_HOME/scripts"
  [ -d "$src" ] || { warn "$(L "스크립트 템플릿 없음" "Script templates missing"): $src"; return; }
  mkdir -p "$dst"

  local n=0
  for t in "$src"/*.sh.tmpl; do
    [ -e "$t" ] || continue
    local name; name=$(basename "$t" .tmpl)
    sed \
      -e "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" \
      -e "s|{{CONFIG_FILE}}|$CONFIG_FILE|g" \
      -e "s|{{DEVTRAIL_BIN}}|$DEVTRAIL_ROOT/bin/devtrail|g" \
      "$t" > "$dst/$name"
    chmod +x "$dst/$name"
    n=$((n+1))
  done
  ok "$(L "스크립트 생성" "Scripts created"): ${n} → $dst"
  dim "   $(L "설정값은 실행 시점에 읽습니다(하드코딩 없음)" \
            "Values are read at run time, not baked in"): $CONFIG_FILE"
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
  printf '%s\n' "${C_BOLD}$(L "볼트 구조" "Vault structure")${C_RESET}"
  local mods; mods=$(printf '%s' "${DT_MODULES:-devlog}" | tr '\n' ' ')
  dim "   $(L "모듈" "Modules"): $mods"
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
    dim "   $(L "Claude Code 를 설치하면 AI 스킬 12종을 함께 쓸 수 있습니다" \
            "Install Claude Code to use the 12 AI skills as well")"
    dim "   $(L "설치 후" "Then"): devtrail skills install"
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
# 완료 안내.
#
# ⚠️ 여기는 '무엇을 했는지'가 아니라 '사용자가 아직 해야 할 것'만 적는다.
#    bootstrap 이 이미 한 일을 다시 시키면 사용자는 두 번 한다 —
#    예전 문구가 그랬다("플러그인 4개를 설치하고 재시작하세요").
_init_next_steps() {
  local vault="$1"
  echo
  ok "$(L "셋업 완료" "Setup complete")"
  echo

  local n=0
  printf '%s\n' "${C_BOLD}$(L "다음 단계" "Next steps")${C_RESET}"

  # bootstrap 이 꺼졌거나 Obsidian 이 없으면 예전 안내가 여전히 맞다.
  if [ "${DT_BOOTSTRAP:-1}" != 1 ]; then
    n=$((n + 1)); info "  ${n}) devtrail obsidian             # $(L "Obsidian 설정 적용" "apply Obsidian settings")"
  else
    case "${DT_BOOT_PLUGINS:-skip}" in
      ok)
        n=$((n + 1))
        info "  ${n}) $(L "Obsidian 이 플러그인을 신뢰할지 물으면 허용합니다" \
                        "When Obsidian asks whether to trust the plugins, allow them")"
        dim "     $(L "커뮤니티 플러그인에 대한 Obsidian 의 보안 확인입니다. 한 번만 묻습니다." \
                    "That is Obsidian's security check for community plugins. It asks once.")" ;;
      failed)
        n=$((n + 1))
        info "  ${n}) devtrail plugins install      # $(L "플러그인 설치 재시도" "retry plugin install")" ;;
      *)
        n=$((n + 1))
        info "  ${n}) devtrail obsidian             # $(L "Obsidian 설정 적용" "apply Obsidian settings")" ;;
    esac
    if [ "${DT_BOOT_OPENED:-0}" != 1 ]; then
      n=$((n + 1))
      info "  ${n}) $(L "Obsidian 에서 볼트를 엽니다" "Open the vault in Obsidian"): $vault"
    fi
  fi

  n=$((n + 1)); info "  ${n}) devtrail doctor               # $(L "진단 — 여기서 ❌ 가 없어야 합니다" \
                                                                "diagnose — you want no ❌ here")"
  n=$((n + 1)); info "  ${n}) devtrail install-schedule     # $(L "자동 실행 등록" "register automatic runs")"

  if [ "${DT_MODE:-existing}" != new ]; then
    echo
    dim "   $(L "기존 볼트이므로 자동 이동은 수동(Manual)으로 시작합니다." \
            "This is an existing vault, so auto-move starts on Manual.")"
    dim "   $(L "무엇이 달라지는지 먼저 보려면" "To see what would change first"): devtrail scan"
  fi
  echo
  dim "$(L "설정" "Config"): $CONFIG_FILE"
  dim "$(L "스크립트" "Scripts"): $DEVTRAIL_HOME/scripts/"
  dim "$(L "되돌리기" "Undo"): devtrail undo"
}
