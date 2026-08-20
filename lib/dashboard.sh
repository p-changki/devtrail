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
  require_config
  require_bins python3

  local src="$DEVTRAIL_ROOT/templates/dashboard"
  [ -f "$src/server.py" ] || die "대시보드 파일 없음: $src/server.py"

  local port="${DEVTRAIL_PORT:-7823}"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    die "포트 $port 를 이미 누가 쓰고 있습니다.
   다른 포트로: DEVTRAIL_PORT=7824 devtrail dashboard"
  fi

  DEVTRAIL_CONFIG="$CONFIG_FILE" \
  DEVTRAIL_SCRIPTS="$DEVTRAIL_HOME/scripts" \
  DEVTRAIL_BIN="$DEVTRAIL_ROOT/bin/devtrail" \
  DEVTRAIL_PORT="$port" \
    exec python3 "$src/server.py"
}
