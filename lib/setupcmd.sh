#!/usr/bin/env bash
# DevTrail — `devtrail setup <apply|status>`
#
# 대화 없이 셋업할 수 있는 통로다. 앱·CI·테스트가 쓴다.
#
# 설계 원칙 하나:
#
#   대화형 init ──┐
#                 ├──→  setup_apply <스펙>  ──→  실제 변경
#   앱 / CI   ────┘
#
# 적용 로직은 여기 한 벌뿐이다. init 은 질문으로 스펙을 만든 다음 이걸
# 부른다. 그래야 "같은 입력이면 같은 결과" 가 설계상 보장된다.
#
# ⚠️ 두 벌로 나누면 언젠가 한쪽만 고쳐지고, 사용자는 "앱으로 하면 다르다" 를
#    만난다. 2026-08-22 실물 QA 에서 잡은 결함 9건 중 4건이 그 유형이었다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

. "$DEVTRAIL_ROOT/lib/setup/spec.sh"
. "$DEVTRAIL_ROOT/lib/setup/plan.sh"

# ── 적용 ─────────────────────────────────────────────────────────────────────
# setup_apply <스펙 JSON 문자열>
#
# 호출자가 저널을 열어둔 상태여야 한다 — 한 번의 셋업이 하나의 되돌림 단위다.
setup_apply() {
  local spec="$1"
  sp_export "$spec"

  # 쓴 스펙을 남긴다.
  #
  # 왜: 대화형으로 만든 볼트를 '같은 입력으로 다시' 만들 수 있어야 한다.
  #     지원 문의에서 "무엇을 골랐는지" 를 되짚을 때도, 앱이 현재 선택을
  #     읽어 화면을 채울 때도 이 파일이 근거다.
  # ⚠️ 이게 있어야 "대화형과 비대화형이 같은 결과" 를 기계로 확인할 수 있다.
  #     init 이 쓴 스펙을 그대로 setup apply 에 먹여 비교하면 된다.
  mkdir -p "$DEVTRAIL_HOME"
  printf '%s\n' "$spec" > "$DEVTRAIL_HOME/setup-spec.json" \
    || warn "$(L "스펙을 남기지 못했습니다" "Could not record the spec"): $DEVTRAIL_HOME/setup-spec.json"

  local backend vault root gh ai
  backend=$(printf '%s' "$spec" | jq -r '.vault.backend')
  vault=$(printf '%s' "$spec"   | jq -r '.vault.path')
  root=$(printf '%s' "$spec"    | jq -r '.vault.root')
  gh=$(printf '%s' "$spec"      | jq -r '.github.user')
  ai=$(printf '%s' "$spec"      | jq -r '.ai.provider')

  mkdir -p "$DEVTRAIL_HOME"/scripts "$DEVTRAIL_HOME"/logs
  [ -d "$vault" ] || mkdir -p "$vault" \
    || die "$(L "볼트 폴더를 만들지 못했습니다" "Could not create the vault folder"): $vault"

  . "$DEVTRAIL_ROOT/lib/init/prompts.sh"
  . "$DEVTRAIL_ROOT/lib/init/write.sh"

  _init_write_config "$backend" "$vault" "$root" "$gh" "$ai"
  _init_render_scripts
  _init_scaffold
  _init_skills
}

# ── 상태 ─────────────────────────────────────────────────────────────────────
# 앱이 "지금 어떤 상태인가" 를 물을 때 쓴다.
#
# ⚠️ 설정이 없어도 성공으로 답한다. 앱 입장에서 '아직 셋업 안 함' 은 오류가
#    아니라 상태다. 여기서 죽으면 앱은 그 사실을 화면에 못 띄운다.
setup_status() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  if [ ! -f "$CONFIG_FILE" ]; then
    if [ "$json" = 1 ]; then
      jq -n --argjson v "$DT_SPEC_VERSION" \
        '{configured: false, spec_version: $v, config_path: env.DEVTRAIL_CONFIG}'
    else
      step "$(L "셋업 상태" "Setup status")"
      warn "$(L "아직 셋업하지 않았습니다" "Not set up yet"): $CONFIG_FILE"
      dim "   devtrail init"
    fi
    return 0
  fi

  if [ "$json" = 1 ]; then
    jq --argjson v "$DT_SPEC_VERSION" --arg cfg "$CONFIG_FILE" '{
      configured: true,
      spec_version: $v,
      config_path: $cfg,
      schema: .version,
      lang: (.lang // "ko"),
      vault: { backend: .vault.backend, path: .vault.path, root: .vault.root },
      mode: (.install.mode // "existing"),
      modules: (.install.modules // []),
      github: { user: (.github.user // "") },
      projects: (.github.project_groups | keys),
      ai: { provider: (.ai.provider // "none"),
            summary_enabled: (.ai.summary_enabled // false) }
    }' "$CONFIG_FILE"
    return 0
  fi

  step "$(L "셋업 상태" "Setup status")"
  info "  $(L "볼트" "Vault"): $(cfg '.vault.path')"
  info "  $(L "루트" "Root"): $(cfg '.vault.root')"
  info "  $(L "언어" "Language"): $(cfg '.lang' 'ko')"
  info "  $(L "설치 방식" "Mode"): $(cfg '.install.mode' 'existing')"
}

# ── 라우터 ───────────────────────────────────────────────────────────────────
setup_cmd() {
  local sub="${1:-status}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    plan)   _setup_plan_cmd "$@" ;;
    apply)  _setup_apply_cmd "$@" ;;
    status) setup_status "$@" ;;
    *) die "$(L "알 수 없는 하위 명령" "Unknown subcommand"): $sub  (plan|apply|status)" ;;
  esac
}

_setup_plan_cmd() {
  require_bins jq
  local input="" json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --input) shift; input="${1:-}" ;;
      --json)  json=1 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  sp_validate "$input"
  setup_plan "$(sp_normalize "$input")" "$json"
}

_setup_apply_cmd() {
  require_bins jq
  local input="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --input) shift; input="${1:-}" ;;
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      --json) ;;   # 지금은 사람이 읽는 출력만 낸다. plan(1b)에서 쓴다.
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  # ⚠️ 검증을 먼저, 치환 밖에서. $(...) 안에서 die 하면 오류 메시지가
  #    치환에 갇혀 사용자에게 아무것도 보이지 않는다.
  sp_validate "$input"
  local spec; spec=$(sp_normalize "$input")

  local vault mode root
  vault=$(printf '%s' "$spec" | jq -r '.vault.path')
  mode=$(printf '%s' "$spec"  | jq -r '.vault.mode')
  root=$(printf '%s' "$spec"  | jq -r '.vault.root')

  # ⚠️ dry-run 화면을 여기서 따로 만들지 않는다. plan 과 두 벌이 되면
  #    "미리 본 것" 과 "실제로 되는 것" 이 갈린다.
  if [ "$apply" != 1 ]; then
    setup_plan "$spec" 0
    echo
    dim "   $(L "적용" "Apply"): devtrail setup apply --input <file> --apply"
    return 0
  fi

  step "$(L "셋업 적용" "Apply setup")"

  # ⚠️ 기존 설정을 덮어쓰기 전에 반드시 백업한다. 비대화형이라 사용자에게
  #    물을 수 없으므로, 되돌릴 수 있게 만드는 것이 유일한 안전장치다.
  jr_begin setup-apply
  if [ -f "$CONFIG_FILE" ]; then
    jr_backup "$CONFIG_FILE" >/dev/null \
      || { jr_end; die "$(L "설정 백업 실패 — 중단합니다" "Config backup failed — stopping"): $CONFIG_FILE"; }
  fi

  setup_apply "$spec"

  if [ "$(printf '%s' "$spec" | jq -r '.bootstrap_plugins')" = "true" ]; then
    . "$DEVTRAIL_ROOT/lib/init/bootstrap.sh"
    init_bootstrap "$vault"
  fi
  jr_end

  echo
  ok "$(L "적용 완료" "Applied")"
  dim "   $(L "진단" "Check"): devtrail doctor"
}
