#!/usr/bin/env bash
# v2 — install 블록을 채운다.
#
# 왜 필요한가:
#   0.2.0 부터 `devtrail augment` 가 install.modules 를 읽어 '사용자가 고른
#   모듈만' 만든다. 이 키가 없는 0.1.x 설정은 tree.json 기본값으로 떨어져,
#   사용자가 고르지 않은 폴더까지 생긴다.
#
#   install.mode 도 같이 채운다. 코드에는 'existing' 폴백이 있어 당장 깨지진
#   않지만, 설정 파일만 보고는 자기가 어떤 모드인지 알 수 없다.
#
# 안전 기본값:
#   mode    = existing   — 이미 쓰던 볼트를 건드리지 않는 쪽
#   modules = devlog     — 0.1.x 가 실제로 하던 일
#   dirs    = {}         — 매핑 없음 = 프리셋 기본 경로

_mg_002_why="install.mode · install.modules · dirs 를 채운다 (없는 것만)"

_mg_002() {
  local cfg="$1"
  # `//` 를 쓰지 않는다 — false 나 0 을 기본값으로 덮어쓴다.
  # 키가 '없을 때'만 채우려면 has() 로 봐야 한다.
  jq '
    if (.install | not) then .install = {} else . end
    | if (.install | has("mode") | not)    then .install.mode = "existing"    else . end
    | if (.install | has("modules") | not) then .install.modules = ["devlog"] else . end
    | if (has("dirs") | not)               then .dirs = {}                    else . end
  ' "$cfg"
}
