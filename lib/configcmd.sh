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
# 값이 정해진 문자열 키. "키:값1,값2" 형식.
DT_SETTABLE_ENUM="lang:ko,en"

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
      [ -n "${2:-}" ] || die "$(L "사용법" "Usage"): devtrail config get <key>"
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
      [ -n "${2:-}" ] && [ $# -ge 3 ] || die "$(L "사용법" "Usage"): devtrail config set <key> <value>"
      _config_set "$2" "$3" ;;
    keys)
      echo "boolean: $DT_SETTABLE_BOOL"
      echo "number:  $DT_SETTABLE_NUM"
      echo "enum:    $DT_SETTABLE_ENUM" ;;
    migrate)
      # 스키마만 따로 올린다. devtrail update 도 같은 함수를 부른다.
      . "$DEVTRAIL_ROOT/lib/migrate.sh"
      if mg_status; then ok "$(L "설정 스키마" "Config schema") v${DT_SCHEMA} — $(L "최신입니다" "up to date")"; return 0; fi
      shift
      mg_run "$@" ;;
    *) die "$(L "알 수 없는 하위 명령" "Unknown subcommand"): $1  (show|get|set|keys|migrate)" ;;
  esac
}

_config_set() {
  local key="$1" val="$2" typed

  if _dt_in_list "$key" "$DT_SETTABLE_BOOL"; then
    case "$val" in
      true|false) typed="$val" ;;
      *) die "$(L "boolean 키에는 true/false 만 허용합니다" "Boolean keys take true or false"): $key=$val" ;;
    esac
  elif _dt_in_list "$key" "$DT_SETTABLE_NUM"; then
    case "$val" in
      ''|*[!0-9]*) die "$(L "숫자 키에는 정수만 허용합니다" "Numeric keys take integers"): $key=$val" ;;
      *) typed="$val" ;;
    esac
  elif _config_enum_values "$key" >/dev/null; then
    local allowed; allowed=$(_config_enum_values "$key")
    case ",$allowed," in
      *",$val,"*) typed="\"$val\"" ;;
      *) die "$(L "허용되지 않는 값입니다" "Not an allowed value"): $key=$val
   $(L "가능한 값" "Allowed"): $(printf '%s' "$allowed" | tr ',' ' ')" ;;
    esac
    [ "$key" = "lang" ] && { _config_lang_guard "$val" || return 1; }
  else
    die "$(L "변경할 수 없는 키입니다" "That key cannot be changed here"): $key
   $(L "변경 가능" "Changeable"): devtrail config keys
   $(L "경로·계정 등은 'devtrail init' 으로 다시 설정하세요." \
       "Paths and accounts are set again with 'devtrail init'.")"
  fi

  # 백업 실패 시 진행하지 않는다 — 원본이 유일본이면 잃는다.
  local backup
  backup=$(jr_backup "$CONFIG_FILE") || die "$(L "백업 실패 — 설정을 건드리지 않습니다" "Backup failed — leaving the config alone")"

  local tmp; tmp=$(mktemp "$(dirname "$CONFIG_FILE")/.devtrail-cfg.XXXXXX")
  if ! jq --argjson v "$typed" "setpath([$(_dt_jq_path "$key")]; \$v)" \
        "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; die "$(L "설정 변경 실패 — 원본 유지" "Could not change the config — original kept")"
  fi
  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; die "$(L "결과가 유효한 JSON 이 아님 — 원본 유지" "The result is not valid JSON — original kept")"
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

# 열거형 키의 허용값을 낸다. 열거형이 아니면 종료코드 1.
_config_enum_values() {
  local key="$1" e
  for e in $DT_SETTABLE_ENUM; do
    case "$e" in "$key:"*) printf '%s' "${e#*:}"; return 0 ;; esac
  done
  return 1
}

# 언어를 바꾸면 폴더 이름 규칙이 바뀐다.
#
# ⚠️ 이미 만들어진 폴더는 이름이 바뀌지 않는다. 그대로 두면 DevTrail 이
#    새 언어의 폴더를 따로 만들어 '평행 구조'가 생긴다 — 사용자가 노트를
#    어디에 뒀는지 잃어버리는 가장 흔한 방식이다.
#
# 막지는 않는다. 다만 무슨 일이 일어나는지 먼저 말하고, 되돌리는 법을 준다.
_config_lang_guard() {
  local new="$1" cur; cur=$(cfg '.lang' 'ko')
  [ "$new" != "$cur" ] || return 0

  local root; root="$(vault_root 2>/dev/null)"
  local existing=0
  if [ -n "$root" ] && [ -d "$root" ]; then
    existing=$(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi

  warn "$(L "언어를 ${cur} → ${new} 로 바꿉니다" "Changing the language ${cur} → ${new}")"
  if [ "${existing:-0}" -gt 0 ]; then
    echo
    dim "   $(L "이미 만들어진 폴더 ${existing}개는 이름이 바뀌지 않습니다." \
            "The ${existing} folders that already exist keep their names.")"
    dim "   $(L "그대로 두면 DevTrail 이 새 이름의 폴더를 따로 만듭니다(평행 구조)." \
            "Left as is, DevTrail creates a second set under the new names.")"
    echo
    dim "   $(L "기존 폴더를 계속 쓰려면 매핑하세요:" "To keep using your folders, map them:")"
    dim "     devtrail scan          — $(L "지금 구조를 봅니다" "see the current structure")"
    dim "     devtrail init          — $(L "기존 폴더에 매핑합니다 (노트는 움직이지 않습니다)" \
                                          "map onto your folders (nothing is moved)")"
    echo
  fi
  confirm "$(L "계속할까요?" "Continue?")" || { info "$(L "취소했습니다." "Cancelled.")"; return 1; }
  return 0
}
