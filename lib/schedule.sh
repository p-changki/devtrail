#!/usr/bin/env bash
# DevTrail — launchd 스케줄 설치/제거 (macOS 전용)
#
# MVP는 macOS만 지원한다. Linux(systemd)·Windows는 어댑터 자리만 두고
# 지원한다고 말하지 않는다 — 어설픈 3플랫폼 지원보다 명시적 미지원이 낫다.

_sched_guard() {
  [ "$(uname -s)" = "Darwin" ] || die "현재 macOS만 지원합니다 (감지: $(uname -s))"
}

schedule_install() {
  _sched_guard
  require_config
  require_bins jq

  local agents="$HOME/Library/LaunchAgents"
  local tmpl="$DEVTRAIL_ROOT/templates/launchd"
  mkdir -p "$agents" "$DEVTRAIL_HOME/logs"

  local hour interval
  hour=$(cfg '.schedule.daily_hour' '10')
  interval=$(cfg '.schedule.repodocs_interval_sec' '600')

  _sched_render "com.devtrail.daily"    "$tmpl/daily.plist.tmpl"    "$agents" \
    "HOUR=$hour"
  _sched_render "com.devtrail.repodocs" "$tmpl/repodocs.plist.tmpl" "$agents" \
    "INTERVAL=$interval"

  echo
  ok "스케줄 등록 완료"
  dim "   확인: devtrail doctor"
  dim "   로그: $DEVTRAIL_HOME/logs/"
}

schedule_uninstall() {
  _sched_guard
  local agents="$HOME/Library/LaunchAgents"
  for label in com.devtrail.daily com.devtrail.repodocs; do
    local plist="$agents/$label.plist"
    if [ -f "$plist" ]; then
      launchctl unload -w "$plist" 2>/dev/null || true
      rm -f "$plist"
      ok "제거: $label"
    else
      dim "   없음: $label"
    fi
  done
  echo
  ok "자동화를 제거했습니다"
  dim "   볼트 데이터와 설정($CONFIG_FILE)은 그대로 둡니다."
  dim "   완전 삭제하려면: rm -rf $DEVTRAIL_HOME"
}

# _sched_render <label> <template> <dest-dir> [KEY=VAL ...]
_sched_render() {
  local label="$1" tmpl="$2" dest="$3"; shift 3
  [ -f "$tmpl" ] || { warn "템플릿 없음: $tmpl — 건너뜀"; return 0; }

  local plist="$dest/$label.plist"
  if [ -f "$plist" ]; then
    jr_backup "$plist" >/dev/null \
      || die "plist 백업 실패 — 기존 스케줄을 건드리지 않습니다: $plist"
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
    die "생성된 plist가 유효하지 않습니다: $label (템플릿 확인 필요)"
  fi

  launchctl load -w "$plist" 2>/dev/null \
    && ok "$label 등록" \
    || { fail "$label 로드 실패 — 수동: launchctl load -w '$plist'"; return 1; }
}
