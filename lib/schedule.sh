#!/usr/bin/env bash
# DevTrail — launchd 스케줄 설치/제거 (macOS 전용)
#
# MVP는 macOS만 지원한다. Linux(systemd)·Windows는 어댑터 자리만 두고
# 지원한다고 말하지 않는다 — 어설픈 3플랫폼 지원보다 명시적 미지원이 낫다.

_sched_guard() {
  [ "$(uname -s)" = "Darwin" ] || die "$(L "현재 macOS 만 지원합니다" "macOS only for now") ($(uname -s))"
}

# ⚠️ 이 명령은 사용자 머신에 백그라운드 작업을 등록한다. 저장소의 다른
#    쓰기 명령(augment · project add · template update · update)은 전부
#    dry-run 이 기본인데 여기만 즉시 적용이었다. 게다가 인자를 아예 보지
#    않아서 `install-schedule --help` 가 도움말 대신 등록을 해버렸다
#    (2026-08-22 실물 QA 에서 실제로 발생).
schedule_install() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -h|--help)
        info "$(L "사용법" "Usage"): devtrail install-schedule [--apply]"
        dim "   $(L "인자가 없으면 무엇을 등록할지 보여주기만 합니다." \
                   "Without arguments it only shows what would be registered.")"
        return 0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  _sched_guard
  require_config
  require_bins jq

  local agents="$HOME/Library/LaunchAgents"
  local tmpl="$DEVTRAIL_ROOT/templates/launchd"

  local hour interval
  hour=$(cfg '.schedule.daily_hour' '10')
  interval=$(cfg '.schedule.repodocs_interval_sec' '600')

  if [ "$apply" != 1 ]; then
    step "$(L "자동 실행 등록" "Register automatic runs")"
    dim "   $(L "(dry-run — 실제로 등록하려면 --apply)" "(dry run — pass --apply to register)")"
    echo
    info "  com.devtrail.daily      $(L "매일 ${hour}시" "daily at ${hour}:00")"
    info "  com.devtrail.repodocs   $(L "${interval}초 간격" "every ${interval}s")"
    dim "   $(L "등록 위치" "Registered in"): $agents"
    echo
    dim "   $(L "적용" "Apply"): devtrail install-schedule --apply"
    dim "   $(L "되돌리기" "Undo"): devtrail uninstall"
    return 0
  fi

  mkdir -p "$agents" "$DEVTRAIL_HOME/logs"

  _sched_render "com.devtrail.daily"    "$tmpl/daily.plist.tmpl"    "$agents" \
    "HOUR=$hour"
  _sched_render "com.devtrail.repodocs" "$tmpl/repodocs.plist.tmpl" "$agents" \
    "INTERVAL=$interval"

  echo
  ok "$(L "스케줄 등록 완료" "Schedule registered")"
  dim "   $(L "확인" "Check"): devtrail doctor"
  dim "   $(L "로그" "Logs"): $DEVTRAIL_HOME/logs/"
  dim "   $(L "되돌리기" "Undo"): devtrail uninstall"
}

schedule_uninstall() {
  _sched_guard
  local agents="$HOME/Library/LaunchAgents"
  for label in com.devtrail.daily com.devtrail.repodocs; do
    local plist="$agents/$label.plist"
    if [ -f "$plist" ]; then
      launchctl unload -w "$plist" 2>/dev/null || true
      rm -f "$plist"
      ok "$(L "제거" "Removed"): $label"
    else
      dim "   $(L "없음" "Not present"): $label"
    fi
  done
  echo
  ok "$(L "자동화를 제거했습니다" "Automation removed")"
  dim "   $(L "볼트 데이터와 설정은 그대로 둡니다." "Your notes and config are left alone.") ($CONFIG_FILE)"
  dim "   $(L "완전 삭제하려면" "To remove everything"): rm -rf $DEVTRAIL_HOME"
}

# _sched_render <label> <template> <dest-dir> [KEY=VAL ...]
_sched_render() {
  local label="$1" tmpl="$2" dest="$3"; shift 3
  [ -f "$tmpl" ] || { warn "$(L "템플릿 없음" "Template missing"): $tmpl — $(L "건너뜀" "skipped")"; return 0; }

  local plist="$dest/$label.plist"
  if [ -f "$plist" ]; then
    jr_backup "$plist" >/dev/null \
      || die "$(L "plist 백업 실패 — 기존 스케줄을 건드리지 않습니다" \
          "plist backup failed — leaving your schedule alone"): $plist"
    launchctl unload -w "$plist" 2>/dev/null || true
  fi

  local sed_args=(-e "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" -e "s|{{LABEL}}|$label|g")
  local kv
  for kv in "$@"; do
    sed_args+=(-e "s|{{${kv%%=*}}}|${kv#*=}|g")
  done

  sed "${sed_args[@]}" "$tmpl" > "$plist"

  if ! plutil -lint "$plist" >/dev/null 2>&1; then
    rm -f "$plist"
    die "$(L "생성된 plist 가 유효하지 않습니다" "The generated plist is not valid"): $label"
  fi

  launchctl load -w "$plist" 2>/dev/null \
    && ok "$label $(L "등록" "registered")" \
    || { fail "$label $(L "로드 실패 — 수동" "failed to load — do it manually"): launchctl load -w '$plist'"; return 1; }
}
