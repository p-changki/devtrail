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
    *) die "$(L "사용법" "Usage"): devtrail app <install|start|stop|restart|status|build>" ;;
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
