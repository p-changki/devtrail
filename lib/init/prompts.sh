#!/usr/bin/env bash
# DevTrail — init: 대화형 입력 프리미티브.
#
# 프롬프트는 stderr 로, 결과는 stdout 으로 낸다.
# $(...) 로 값을 받으므로 둘이 섞이면 안 된다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── prompts ──────────────────────────────────────────────────────────────────
_init_ask() {
  local prompt="$1" default="${2-}" reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    printf '%s' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    printf '%s' "$reply"
  fi
}

# _init_pick <제목> <개행으로 구분된 항목> [기본값]  →  선택된 항목을 개행으로 출력
#
# 기본값 "a" 는 Enter 만 눌렀을 때 전체 선택, 빈 문자열이면 아무것도 고르지 않는다.
# 안내 문구는 반드시 실제 기본값과 일치해야 한다 — 어긋나면 사용자가 의도하지
# 않은 항목을 켜게 된다(요약 섹션이 레포 수만큼 생기는 식으로).
#
# ⚠️ bash 3.2다. 인덱스 배열은 되지만 `declare -A`·mapfile 은 안 된다.
#    또 set -u 에서 빈 배열의 "${arr[@]}" 는 unbound 로 죽으므로,
#    확장하기 전에 반드시 개수를 먼저 검사한다.
_init_pick() {
  local title="$1" items="$2" default="${3-}" reply sel i
  [ -n "$items" ] || return 0

  local list=() out=() oldifs="$IFS"
  IFS=$'\n'
  for i in $items; do [ -n "$i" ] && list+=("$i"); done
  IFS="$oldifs"
  [ ${#list[@]} -gt 0 ] || return 0

  {
    printf '%s\n' "$title"
    i=0
    while [ $i -lt ${#list[@]} ]; do
      printf '   %2d) %s\n' $((i + 1)) "${list[$i]}"
      i=$((i + 1))
    done
    local hint; hint=$(L "그냥 Enter=선택 안 함" "Enter = none")
    [ "$default" = "a" ] && hint=$(L "그냥 Enter=전체" "Enter = all")
    dim "   $(L "a=전체 · 개별 선택 예) 1,3" "a = all · pick some, e.g. 1,3") · $hint"
  } >&2

  reply=$(_init_ask "$(L "선택" "Choose")" "$default" 2>/dev/null)
  [ -n "$reply" ] || return 0

  case "$reply" in
    a|A) out=("${list[@]}") ;;
    *)
      IFS=','
      for sel in $reply; do
        IFS="$oldifs"
        sel="${sel// /}"
        case "$sel" in ''|*[!0-9]*) continue ;; esac
        [ "$sel" -ge 1 ] && [ "$sel" -le ${#list[@]} ] || continue
        out+=("${list[$((sel - 1))]}")
        IFS=','
      done
      IFS="$oldifs" ;;
  esac

  [ ${#out[@]} -gt 0 ] || return 0
  printf '%s\n' "${out[@]}"
}

# 어떤 레포의 docs/ 를 볼트로 가져올지. 비워두면 sync 는 매번 할 일 없이 끝난다.
