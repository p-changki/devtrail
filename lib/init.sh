#!/usr/bin/env bash
# DevTrail — `devtrail init`
#
# 대화형 셋업. 이 파일은 순서만 정하고 실제 작업은 lib/init/*.sh 가 한다.
#
#   prompts.sh    대화형 입력 프리미티브 (_init_ask · _init_pick)
#   detect.sh     볼트를 읽어 기본값을 정한다 (scan · 모드 · 루트 · 역할 매핑)
#   questions.sh  셋업 질문들
#   write.sh      설정 저장과 산출물 생성
#
# 설계 원칙:
#   - 기존 파일을 덮어쓰지 않는다. 항상 .bak 후 진행한다
#   - 볼트를 알아낸 직후 진단한다 — 이후의 기본값이 전부 거기서 나온다
#   - 탐지 결과가 비면 질문을 건너뛴다. 빈 볼트 사용자에게 매핑을 묻지 않는다

for _dt_part in prompts detect questions write; do
  # shellcheck disable=SC1090
  . "$DEVTRAIL_ROOT/lib/init/$_dt_part.sh"
done
unset _dt_part

init_run() {
  printf '%s\n' "${C_BOLD}DevTrail $(L "셋업" "setup")${C_RESET}"
  dim "$(L "언제든 Ctrl+C 로 중단할 수 있습니다. 기존 파일은 덮어쓰지 않습니다." \
          "Ctrl+C to stop at any point. Nothing existing is overwritten.")"
  echo

  require_bins jq

  if config_exists; then
    warn "$(L "설정이 이미 있습니다" "A config already exists"): $CONFIG_FILE"
    confirm "$(L "다시 설정할까요? (기존 설정은 백업합니다)" \
              "Set it up again? (the existing config is backed up)")" \
      || { info "$(L "취소했습니다." "Cancelled.")"; return 0; }
    jr_backup "$CONFIG_FILE" >/dev/null \
      || die "$(L "설정 백업 실패 — 중단합니다" "Config backup failed — stopping"): $CONFIG_FILE"
  fi

  mkdir -p "$DEVTRAIL_HOME"/{scripts,logs}

  # ⚠️ 언어가 먼저다. 폴더 이름과 이후 질문의 문구가 여기서 갈린다.
  DT_LANG=$(_init_lang); export DT_LANG
  DEVTRAIL_LANG="$DT_LANG"; export DEVTRAIL_LANG

  local backend vault root gh_user ai_provider
  backend=$(_init_backend)
  vault=$(_init_vault "$backend")

  # 볼트를 알아낸 직후 진단한다. 이후의 기본값이 전부 여기서 나온다.
  _init_scan "$vault"
  DT_MODE=$(_init_mode); export DT_MODE

  root=$(_init_root "$vault")
  DT_DIRS=$(_init_adopt "$root"); export DT_DIRS
  DT_MODULES=$(_init_modules); export DT_MODULES
  gh_user=$(_init_github)
  DT_SRC_ROOT=$(_init_src_root); export DT_SRC_ROOT
  DT_SYNC_REPOS=$(_init_sync_repos "$DT_SRC_ROOT"); export DT_SYNC_REPOS
  DT_PROJECTS=$(_init_projects "$gh_user"); export DT_PROJECTS
  ai_provider=$(_init_ai)

  _init_write_config "$backend" "$vault" "$root" "$gh_user" "$ai_provider"
  _init_render_scripts
  _init_scaffold
  _init_skills
  _init_next_steps "$vault"
}

# ── 진단 ─────────────────────────────────────────────────────────────────────
# scan 을 한 번 돌려 캐시한다. 모드 제안 · 루트명 기본값 · 충돌 안내가 이걸 쓴다.
