#!/usr/bin/env bash
# DevTrail — `devtrail config [get|set]`
#
# 설정 읽기/쓰기의 단일 창구다. UI(메뉴바 앱·웹 대시보드)는 이 명령만 호출하고
# 직접 JSON을 건드리지 않는다. 검증·백업·원자적 쓰기가 한 곳에만 있어야
# UI가 늘어나도 규칙이 갈라지지 않는다.

# 변경을 허용하는 키. 임의 경로 쓰기를 막는다.
# (경로·계정 같은 값은 init에서 다룬다 — UI에서 실수로 바꾸면 복구가 어렵다)
DT_SETTABLE_BOOL="ai.summary_enabled backup.enabled linear.enabled"
DT_SETTABLE_NUM="schedule.daily_hour schedule.repodocs_interval_sec"

# 🔑 기본값의 단일 출처.
#
# 설정에 키가 없을 때 어떻게 동작하는지는 '한 곳'에만 적혀 있어야 한다.
# 예전에는 셸 스크립트(`cfg '.backup.enabled' 'true'`)와 대시보드
# (`dig(cfg, k, False)`)가 서로 다른 기본값을 갖고 있어서, 화면에는
# "백업 꺼짐"이라고 나오는데 실제로는 매일 백업이 도는 상태가 됐다.
# UI는 반드시 `devtrail config effective` 를 통해 이 값을 읽어야 한다.
DT_DEFAULTS='{
  "ai.summary_enabled": true,
  "backup.enabled": true,
  "linear.enabled": false,
  "schedule.daily_hour": 10,
  "schedule.repodocs_interval_sec": 600
}'

config_cmd() {
  require_config
  require_bins jq

  case "${1:-show}" in
    show|"") jq . "$CONFIG_FILE" ;;
    get)
      [ -n "${2:-}" ] || die "사용법: devtrail config get <key>"
      # 설정에 없으면 기본값을 돌려준다 — 실제 동작과 같은 값이어야 한다.
      cfg ".$2" "$(printf '%s' "$DT_DEFAULTS" | jq -r --arg k "$2" '.[$k] // empty')" ;;
    effective)
      # UI 전용: 설정값 + 기본값을 합쳐 '실제로 적용되는 값'을 낸다.
      printf '%s' "$DT_DEFAULTS" | jq --slurpfile c "$CONFIG_FILE" '
        . as $d
        | ($c[0] // {}) as $cfg
        | reduce keys_unsorted[] as $k ({};
            . + { ($k): (
              ($k | split(".")) as $p
              | ($cfg | getpath($p)) as $v
              | if $v == null then $d[$k] else $v end
            )})' ;;
    set)
      [ -n "${2:-}" ] && [ $# -ge 3 ] || die "사용법: devtrail config set <key> <value>"
      _config_set "$2" "$3" ;;
    keys)
      echo "boolean: $DT_SETTABLE_BOOL"
      echo "number:  $DT_SETTABLE_NUM" ;;
    migrate)
      # 스키마만 따로 올린다. devtrail update 도 같은 함수를 부른다.
      . "$DEVTRAIL_ROOT/lib/migrate.sh"
      if mg_status; then ok "설정 스키마 v${DT_SCHEMA} — 최신입니다"; return 0; fi
      shift
      mg_run "$@" ;;
    *) die "알 수 없는 하위 명령: $1  (show|get|set|keys|migrate)" ;;
  esac
}

_config_set() {
  local key="$1" val="$2" typed

  if _dt_in_list "$key" "$DT_SETTABLE_BOOL"; then
    case "$val" in
      true|false) typed="$val" ;;
      *) die "boolean 키에는 true/false 만 허용합니다: $key=$val" ;;
    esac
  elif _dt_in_list "$key" "$DT_SETTABLE_NUM"; then
    case "$val" in
      ''|*[!0-9]*) die "숫자 키에는 정수만 허용합니다: $key=$val" ;;
      *) typed="$val" ;;
    esac
  else
    die "변경할 수 없는 키입니다: $key
   변경 가능: devtrail config keys
   경로·계정 등은 'devtrail init' 으로 다시 설정하세요."
  fi

  # 백업 실패 시 진행하지 않는다 — 원본이 유일본이면 잃는다.
  local backup
  backup=$(jr_backup "$CONFIG_FILE") || die "백업 실패 — 설정을 건드리지 않습니다"

  local tmp; tmp=$(mktemp "$(dirname "$CONFIG_FILE")/.devtrail-cfg.XXXXXX")
  if ! jq --argjson v "$typed" "setpath([$(_dt_jq_path "$key")]; \$v)" \
        "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; die "설정 변경 실패 — 원본 유지"
  fi
  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; die "결과가 유효한 JSON이 아님 — 원본 유지"
  fi

  mv "$tmp" "$CONFIG_FILE"
  printf '%s=%s\n' "$key" "$typed"
}

_dt_in_list() {
  local needle="$1" item
  for item in $2; do [ "$item" = "$needle" ] && return 0; done
  return 1
}

# a.b.c → "a","b","c"  (jq setpath 인자용)
_dt_jq_path() {
  printf '%s' "$1" | awk -F. '{for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i}}'
}
