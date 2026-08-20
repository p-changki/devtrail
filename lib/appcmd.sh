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
    *) die "사용법: devtrail app <install|start|stop|restart|status|build>" ;;
  esac
}

_app_source() { printf '%s' "$DEVTRAIL_ROOT/app/build/$APP_NAME.app"; }

# 설치본을 우선 쓰고, 없으면 빌드 폴더의 것을 쓴다.
_app_path() {
  if [ -d "$APP_INSTALLED" ]; then printf '%s' "$APP_INSTALLED"
  else printf '%s' "$(_app_source)"; fi
}

_app_build() {
  [ -x "$DEVTRAIL_ROOT/app/build.sh" ] || die "빌드 스크립트 없음: $DEVTRAIL_ROOT/app/build.sh"
  command -v swift >/dev/null 2>&1 || die "swift 없음 — Xcode 또는 Command Line Tools 필요"
  step "앱 빌드"
  "$DEVTRAIL_ROOT/app/build.sh" >/dev/null || die "빌드 실패 — 직접 실행해 보세요: app/build.sh"
  ok "빌드 완료"
}

_app_install() {
  local src; src=$(_app_source)
  [ -d "$src" ] || die "빌드 산출물 없음: $src"
  # 실행 중이면 교체가 실패하거나 이상하게 동작한다.
  _app_stop >/dev/null 2>&1 || true
  rm -rf "$APP_INSTALLED"
  cp -R "$src" /Applications/ || die "설치 실패 — /Applications 쓰기 권한을 확인하세요"
  ok "설치 완료: $APP_INSTALLED"
  dim "     'devtrail app start' 로 실행하거나 Spotlight에서 DevTrail 검색"
}

_app_start() {
  local path; path=$(_app_path)
  [ -d "$path" ] || die "앱이 없습니다. 먼저: devtrail app install"
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    ok "이미 실행 중입니다"
    return 0
  fi
  open "$path" || die "실행 실패: $path"
  ok "실행했습니다 — 메뉴바를 확인하세요"
}

_app_stop() {
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" && ok "종료했습니다"
  else
    dim "   실행 중이 아닙니다"
  fi
}

_app_status() {
  step "메뉴바 앱"
  if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    ok "실행 중"
  else
    warn "실행 중이 아님 → devtrail app start"
  fi
  if [ -d "$APP_INSTALLED" ]; then ok "설치됨: $APP_INSTALLED"
  elif [ -d "$(_app_source)" ]; then warn "빌드만 됨: $(_app_source) → devtrail app install"
  else warn "빌드되지 않음 → devtrail app install"; fi
  dim "   로그인 시 자동 시작은 앱 패널의 '로그인 시 시작' 토글에서 켭니다"
}
