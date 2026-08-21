#!/usr/bin/env bash
# DevTrail — `devtrail init`
#
# 대화형 셋업. 이 파일은 순서만 정하고 실제 작업은 lib/init/*.sh 가 한다.
#
#   prompts.sh    대화형 입력 프리미티브 (_init_ask · _init_pick)
#   detect.sh     볼트를 읽어 기본값을 정한다 (scan · 모드 · 루트 · 역할 매핑)
#   questions.sh  셋업 질문들
#   write.sh      설정 저장과 산출물 생성
#   bootstrap.sh  Obsidian 을 쓸 수 있는 상태로 만든다(폴더·플러그인·등록·열기)
#
# 설계 원칙:
#   - 기존 파일을 덮어쓰지 않는다. 항상 .bak 후 진행한다
#   - 볼트를 알아낸 직후 진단한다 — 이후의 기본값이 전부 거기서 나온다
#   - 탐지 결과가 비면 질문을 건너뛴다. 빈 볼트 사용자에게 매핑을 묻지 않는다

for _dt_part in prompts detect questions write bootstrap; do
  # shellcheck disable=SC1090
  . "$DEVTRAIL_ROOT/lib/init/$_dt_part.sh"
done
unset _dt_part

init_run() {
  # --no-bootstrap: 설정만 만들고 Obsidian 은 건드리지 않는다.
  # 자동화·테스트, 그리고 "내 볼트는 내가 만진다" 는 사용자를 위한 탈출구다.
  DT_BOOTSTRAP=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-bootstrap) DT_BOOTSTRAP=0 ;;
      -*) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  # ⚠️ 이 두 줄은 언어를 묻기 '전'에 나온다. 그 시점의 dt_lang 은 설정도
  #    사용자의 답도 없어 로케일로 떨어지므로, L 을 쓰면 환경에 따라 문구가
  #    달라진다. 언어 선택 화면과 같은 원칙으로 양쪽을 병기한다.
  printf '%s\n' "${C_BOLD}DevTrail setup / 셋업${C_RESET}"
  dim "Ctrl+C to stop at any point. Nothing existing is overwritten."
  dim "언제든 Ctrl+C 로 중단할 수 있습니다. 기존 파일은 덮어쓰지 않습니다."
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

  # ⚠️ 여기서 직접 적용하지 않는다. 질문의 결과를 스펙으로 만들어
  #    setup_apply 에 넘긴다 — 앱·CI 가 타는 길과 같은 길이다.
  #    적용 로직이 두 벌이면 언젠가 한쪽만 고쳐지고, 사용자는
  #    "앱으로 하면 다르다" 를 만난다.
  . "$DEVTRAIL_ROOT/lib/setupcmd.sh"
  local spec; spec=$(sp_from_init "$backend" "$vault" "$root" "$gh_user" "$ai_provider")
  setup_apply "$spec"

  # 여기서 끝내면 사용자는 다시 GUI 로 나가야 한다. 끝까지 데려다준다.
  if [ "$DT_BOOTSTRAP" = 1 ]; then
    init_bootstrap "$vault"
    init_bootstrap_apply "$vault"
  fi

  _init_next_steps "$vault"
}

# ── 진단 ─────────────────────────────────────────────────────────────────────
# scan 을 한 번 돌려 캐시한다. 모드 제안 · 루트명 기본값 · 충돌 안내가 이걸 쓴다.
