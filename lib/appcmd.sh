#!/usr/bin/env bash
# DevTrail — `devtrail app <install|start|stop|status|build>`
#
# 메뉴바 앱을 터미널에서 다루기 위한 명령.
# 앱은 GUI라 "한 번 끄면 다시 켜기 어렵다"는 문제가 생기기 쉬워서,
# 켜고 끄는 수단을 CLI에도 둔다.

APP_NAME="DevTrail"
APP_INSTALLED="/Applications/$APP_NAME.app"

app_cmd() {
  case "${1:-status}" in
    build)   _app_build ;;
    install) _app_build && _app_install ;;
    start)   _app_start ;;
    stop)    _app_stop ;;
    restart) _app_stop; sleep 1; _app_start ;;
    status)  _app_status ;;
    uninstall) shift; _app_uninstall "$@" ;;
    *) die "$(L "사용법" "Usage"): devtrail app <install|start|stop|restart|status|build|uninstall>" ;;
  esac
}

_app_source() { printf '%s' "$DEVTRAIL_ROOT/app/build/$APP_NAME.app"; }

# 설치본을 우선 쓰고, 없으면 빌드 폴더의 것을 쓴다.
_app_path() {
  if [ -d "$APP_INSTALLED" ]; then printf '%s' "$APP_INSTALLED"
  else printf '%s' "$(_app_source)"; fi
}

_app_build() {
  [ -x "$DEVTRAIL_ROOT/app/build.sh" ] || die "$(L "빌드 스크립트 없음" "Build script missing"): $DEVTRAIL_ROOT/app/build.sh"
  command -v swift >/dev/null 2>&1 || die "$(L "swift 없음 — Xcode 또는 Command Line Tools 필요" "No swift — Xcode or Command Line Tools required")"
  step "$(L "앱 빌드" "Building the app")"
  "$DEVTRAIL_ROOT/app/build.sh" >/dev/null || die "$(L "빌드 실패 — 직접 실행해 보세요" "Build failed — try running it yourself"): app/build.sh"
  ok "$(L "빌드 완료" "Built")"
}

_app_install() {
  local src; src=$(_app_source)
  [ -d "$src" ] || die "$(L "빌드 산출물 없음" "No build output"): $src"
  # 실행 중이면 교체가 실패하거나 이상하게 동작한다.
  _app_stop >/dev/null 2>&1 || true
  rm -rf "$APP_INSTALLED"
  cp -R "$src" /Applications/ || die "$(L "설치 실패 — /Applications 쓰기 권한을 확인하세요" "Install failed — check write access to /Applications")"
  ok "$(L "설치 완료" "Installed"): $APP_INSTALLED"
  dim "     $(L "'devtrail app start' 로 실행하거나 Spotlight 에서 DevTrail 검색" \
                "Run 'devtrail app start', or find DevTrail in Spotlight")"
}

# 앱을 /Applications 에서 지운다.
#
# ⚠️ 설치는 되는데 제거할 방법이 없었다. devtrail uninstall 은 자동화(plist)만
#    지우고 앱은 남긴다 — 남의 /Applications 에 우리 것을 두고 나가는 셈이다.
# ⚠️ 볼트와 설정은 건드리지 않는다. 앱만 지운다.
_app_uninstall() {
  local apply=0
  [ "${1:-}" = "--apply" ] && apply=1

  step "$(L "메뉴바 앱 제거" "Remove menu bar app")"
  if [ ! -d "$APP_INSTALLED" ]; then
    dim "   $(L "설치되어 있지 않습니다" "Not installed"): $APP_INSTALLED"
    return 0
  fi

  local v
  v=$(plutil -p "$APP_INSTALLED/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*CFBundleShortVersionString" => "([^"]*)".*/\1/p')
  info "  $APP_INSTALLED  (v${v:-?})"

  if [ "$apply" = 0 ]; then
    dim "   $(L "볼트와 설정은 건드리지 않습니다. 앱만 지웁니다." \
               "Your vault and config are untouched. Only the app is removed.")"
    echo
    dim "   $(L "적용" "Apply"): devtrail app uninstall --apply"
    return 0
  fi

  _app_stop >/dev/null 2>&1 || true
  rm -rf "$APP_INSTALLED" \
    || die "$(L "삭제 실패 — /Applications 쓰기 권한을 확인하세요" \
               "Removal failed — check write access to /Applications")"
  ok "$(L "제거 완료" "Removed"): $APP_INSTALLED"
}

_app_start() {
  local path; path=$(_app_path)
  [ -d "$path" ] || die "$(L "앱이 없습니다. 먼저" "The app is not there. First"): devtrail app install"
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    ok "$(L "이미 실행 중입니다" "Already running")"
    return 0
  fi
  open "$path" || die "$(L "실행 실패" "Could not start it"): $path"
  ok "$(L "실행했습니다 — 메뉴바를 확인하세요" "Started — check your menu bar")"
}

_app_stop() {
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" && ok "$(L "종료했습니다" "Stopped")"
  else
    dim "   $(L "실행 중이 아닙니다" "Not running")"
  fi
}

_app_status() {
  step "$(L "메뉴바 앱" "Menu bar app")"
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    ok "$(L "실행 중" "Running")"
  else
    warn "$(L "실행 중이 아님" "Not running") → devtrail app start"
  fi
  if [ -d "$APP_INSTALLED" ]; then ok "$(L "설치됨" "Installed"): $APP_INSTALLED"
  elif [ -d "$(_app_source)" ]; then warn "$(L "빌드만 됨" "Built but not installed"): $(_app_source) → devtrail app install"
  else warn "$(L "빌드되지 않음" "Not built") → devtrail app install"; fi
  dim "   $(L "로그인 시 자동 시작은 앱 패널의 '로그인 시 시작' 토글에서 켭니다" \
            "Turn on 'Start at login' in the app panel to launch it automatically")"
}
