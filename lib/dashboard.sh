#!/usr/bin/env bash
# DevTrail — `devtrail dashboard`
#
# 로컬 전용 웹 대시보드를 띄운다.
#
# 이 서버는 셸 스크립트를 실행하므로 기본값을 잠가둔다:
#   - 127.0.0.1 바인딩 (외부에서 접근 불가)
#   - 실행마다 랜덤 토큰 발급 (브라우저 주소에 포함)
#   - 실행 가능한 명령은 서버 화이트리스트로 고정
# 자세한 내용은 templates/dashboard/server.py 상단 주석 참고.

dashboard_run() {
  # ⚠️ 인자를 보지 않으면 `devtrail dashboard --help` 가 도움말 대신 서버를
  #    띄운다. install-schedule 에서 같은 실수를 잡았다(2026-08-22 실물 QA).
  local port="${DEVTRAIL_PORT:-7823}"
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--port) shift; port="${1:-$port}" ;;
      -h|--help)
        info "$(L "사용법" "Usage"): devtrail dashboard [--port PORT]"
        dim "   $(L "기본 포트" "Default port"): 7823"
        dim "   $(L "환경변수로도 됩니다" "The environment variable works too"): DEVTRAIL_PORT"
        return 0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  require_config
  require_bins python3

  local src="$DEVTRAIL_ROOT/templates/dashboard"
  [ -f "$src/server.py" ] || die "$(L "대시보드 파일 없음" "Dashboard files missing"): $src/server.py"

  case "$port" in ''|*[!0-9]*) die "$(L "포트는 숫자여야 합니다" "The port must be a number"): $port" ;; esac

  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    # ⚠️ 다음 포트를 제안한다. 예전에는 7824 를 문자열로 박아놔서, 사용자가
    #    이미 --port 로 다른 값을 줬어도 엉뚱한 번호를 안내했다.
    die "$(L "포트 ${port} 를 이미 누가 쓰고 있습니다." "Port ${port} is already in use.")
   $(L "다른 포트로" "Try another port"): devtrail dashboard --port $((port + 1))"
  fi

  DEVTRAIL_CONFIG="$CONFIG_FILE" \
  DEVTRAIL_SCRIPTS="$DEVTRAIL_HOME/scripts" \
  DEVTRAIL_BIN="$DEVTRAIL_ROOT/bin/devtrail" \
  DEVTRAIL_PORT="$port" \
    exec python3 "$src/server.py"
}
