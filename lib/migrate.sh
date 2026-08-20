#!/usr/bin/env bash
# DevTrail — 설정 스키마 마이그레이션.
#
# 설정 파일은 사용자 것이다. 코드가 새 키를 읽기 시작했다고 해서
# 남의 설정을 조용히 갈아엎으면 안 된다.
#
# 규칙:
#   1. 마이그레이션은 '없는 것을 채우는' 방향만 한다. 있는 값은 건드리지 않는다.
#      → 두 번 돌려도 결과가 같다.
#   2. 순차 적용한다. 1→3 은 없다. 1→2→3 이다.
#   3. 저널에 남긴다. devtrail undo 로 되돌아갈 수 있어야 한다.
#
# ⚠️ 스키마 번호를 올릴 때는 반드시 lib/migrations/NNN-*.sh 를 함께 추가한다.
#    번호만 올리면 '마이그레이션 필요'라고 말해놓고 아무것도 안 한다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# 코드가 기대하는 스키마. 단일 출처.
DT_SCHEMA=3

DT_MIGRATIONS_DIR="$DEVTRAIL_ROOT/lib/migrations"

# 설정 파일의 스키마 번호. 없으면 1 로 본다(초기 배포에 version 이 없었다).
mg_current() {
  [ -f "$CONFIG_FILE" ] || { printf '0'; return; }
  local v; v=$(jq -r '.version // 1' "$CONFIG_FILE" 2>/dev/null)
  case "$v" in ''|null|*[!0-9]*) printf '1' ;; *) printf '%s' "$v" ;; esac
}

# 0 = 최신 · 1 = 올려야 함 · 2 = 코드가 낡음(설정이 미래에서 왔다)
mg_status() {
  local cur; cur=$(mg_current)
  [ "$cur" = "0" ] && return 0                 # 설정 없음 — init 이 할 일
  [ "$cur" -eq "$DT_SCHEMA" ] && return 0
  [ "$cur" -lt "$DT_SCHEMA" ] && return 1
  return 2
}

_mg_file() { ls "$DT_MIGRATIONS_DIR"/"$(printf '%03d' "$1")"-*.sh 2>/dev/null | head -1; }

# 적용할 마이그레이션을 한 줄씩 낸다: 번호<TAB>설명
mg_pending() {
  local cur n f
  cur=$(mg_current)
  [ "$cur" = "0" ] && return 0
  n=$((cur + 1))
  while [ "$n" -le "$DT_SCHEMA" ]; do
    f=$(_mg_file "$n")
    if [ -n "$f" ]; then
      . "$f"
      printf '%s\t%s\n' "$n" "$(eval "printf '%s' \"\${_mg_$(printf '%03d' "$n")_why:-설명 없음}\"")"
    else
      printf '%s\t%s\n' "$n" "⚠️ 마이그레이션 파일이 없습니다"
    fi
    n=$((n + 1))
  done
}

# mg_run [--apply]
mg_run() {
  local apply=0
  [ "${1:-}" = "--apply" ] && apply=1

  mg_status
  case $? in
    0) return 0 ;;
    2) die "$(L "설정이 이 버전보다 새롭습니다" "Your config is newer than this code") ($(L "설정" "config") v$(mg_current) · $(L "코드" "code") v$DT_SCHEMA)
   $(L "devtrail update 로 코드를 올리세요. 설정을 강제로 낮추지 않습니다." \
       "Update with devtrail update. We will not downgrade your config.")" ;;
  esac

  step "$(L "설정 스키마" "Config schema") $(mg_current) → $DT_SCHEMA"
  mg_pending | while IFS=$'\t' read -r n why; do
    printf '   v%-3s %s\n' "$n" "$why"
  done
  echo

  if [ "$apply" = 0 ]; then
    dim "   $(L "적용" "Apply"): devtrail update --apply   ($(L "또는" "or") devtrail config migrate --apply)"
    return 0
  fi

  # update 가 이미 작업을 열었으면 그 안에 들어간다. 아니면 새로 연다.
  # 이걸 빠뜨리면 백업이 파일 옆 .bak 으로 흩어져 undo 가 찾지 못한다.
  local own=0
  if ! _jr_active; then jr_begin migrate; own=1; fi

  jr_backup "$CONFIG_FILE" >/dev/null || die "$(L "설정을 백업할 수 없습니다 — 중단합니다" "Cannot back up the config — stopping")"

  local n f tmp
  n=$(( $(mg_current) + 1 ))
  while [ "$n" -le "$DT_SCHEMA" ]; do
    f=$(_mg_file "$n")
    [ -n "$f" ] || die "$(L "마이그레이션 파일이 없습니다" "No migration file"): v${n}
   $(L "코드가 잘못 배포됐습니다. 설정을 건드리지 않았습니다." \
       "This build is broken. Your config was not touched.")"
    . "$f"

    tmp=$(mktemp)
    if ! "_mg_$(printf '%03d' "$n")" "$CONFIG_FILE" > "$tmp"; then
      rm -f "$tmp"; die "$(L "마이그레이션 v${n} 실패 — 설정은 그대로입니다" \
          "Migration v${n} failed — your config is unchanged")"
    fi
    # 결과가 JSON 이 아니면 절대 덮어쓰지 않는다.
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "$(L "마이그레이션 v${n} 이 깨진 JSON 을 냈습니다 — 설정은 그대로입니다" \
          "Migration v${n} produced invalid JSON — your config is unchanged")"; }

    jq --argjson v "$n" '.version = $v' "$tmp" > "$CONFIG_FILE"
    rm -f "$tmp"
    ok "v${n} $(L "적용" "applied")"
    n=$((n + 1))
  done

  ok "$(L "설정 스키마" "Config schema") v${DT_SCHEMA}"
  [ "$own" = 1 ] && jr_end
  return 0
}
