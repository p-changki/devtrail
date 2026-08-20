#!/usr/bin/env bash
# DevTrail — `devtrail path [key]`
#
# 경로 해석의 단일 창구다. 스킬·템플릿·Dataview 쿼리·스크립트가 전부 이걸 쓴다.
#
# ⚠️ 경로를 어디에도 박지 말 것.
#    박아두면 사용자가 폴더명을 바꾸는 순간 전부 깨진다. 실제로 원본 볼트의
#    Dataview 쿼리들이 FROM "창기/개발/개발메모/Frontend" 로 박혀 있어
#    루트 폴더명을 바꾸면 그대로 죽는다.
#
# 해석 순서:
#   1) config 의 dirs.<key>          — 사용자가 명시한 경로가 최우선
#   2) preset/tree.json 의 path      — 프리셋 기본값
#   위 둘 다 없으면 알 수 없는 키다.
#
#   devtrail path                    전체 목록 (key<TAB>절대경로)
#   devtrail path devlog             하나만
#   devtrail path --rel devlog       볼트 기준 상대경로 (Dataview FROM 용)
#   devtrail path --json             전체를 JSON 으로

DT_TREE="${DEVTRAIL_TREE:-$DEVTRAIL_ROOT/preset/tree.json}"

path_cmd() {
  require_config
  require_bins jq
  [ -f "$DT_TREE" ] || die "$(L "트리 정의 없음" "Tree definition missing"): $DT_TREE"

  local mode=abs key=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rel)  mode=rel ;;
      --json) mode=json ;;
      --abs)  mode=abs ;;
      -*)     die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)      key="$1" ;;
    esac
    shift
  done

  case "$mode" in
    json) _path_all json ;;
    *)
      if [ -n "$key" ]; then
        _path_one "$key" "$mode"
      else
        _path_all "$mode"
      fi ;;
  esac
}

# 해석은 common.sh 의 dt_dir 한 곳에만 둔다 — 두 벌이면 반드시 갈라진다.
_path_rel() { dt_dir "$1"; }

_path_one() {
  local key="$1" mode="$2" rel
  rel=$(_path_rel "$key")
  [ -n "$rel" ] || die "$(L "알 수 없는 경로 키" "Unknown path key"): $key
   $(L "전체 목록" "Full list"): devtrail path"
  if [ "$mode" = rel ]; then
    # Dataview FROM 은 볼트 기준 경로를 쓴다 (루트 폴더 포함, 없으면 생략)
    printf '%s\n' "$(vault_rel "$rel")"
  else
    printf '%s/%s\n' "$(vault_root)" "$rel"
  fi
}

_path_all() {
  local mode="$1" keys k
  keys=$(jq -r '
    [ .folders[] | . as $p | $p.key, (($p.children // [])[] | .key) ] | .[]
  ' "$DT_TREE")

  if [ "$mode" = json ]; then
    local first=1
    printf '{\n'
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      [ "$first" = 1 ] || printf ',\n'
      first=0
      printf '  "%s": { "abs": %s, "rel": %s }' "$k" \
        "$(printf '%s/%s' "$(vault_root)" "$(_path_rel "$k")" | jq -R .)" \
        "$(vault_rel "$(_path_rel "$k")" | jq -R .)"
    done <<EOF
$keys
EOF
    printf '\n}\n'
  else
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      printf '%s\t%s\n' "$k" "$(_path_one "$k" "$mode")"
    done <<EOF
$keys
EOF
  fi
}
