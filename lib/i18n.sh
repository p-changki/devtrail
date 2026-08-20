#!/usr/bin/env bash
# DevTrail — 언어.
#
# 한국어가 기본이고 영어를 함께 지원한다.
#
# ⚠️ 언어는 '표시'만 바꾼다. key 와 tag 는 절대 바뀌지 않는다.
#    라우팅·허브 쿼리·스킬이 전부 key/tag 로 동작하므로, 사용자가 언어를
#    바꿔도 자동 분류가 깨지지 않는다. 이게 이 설계의 전부다.
#
# ⚠️ bash 3.2 에는 연관배열이 없다. 메시지는 변수로 정의해 source 한다
#    (파일 한 번 읽기 · 호출당 비용 없음).
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"

DT_LANGS="ko en"

# 언어 결정 순서:
#   1) DEVTRAIL_LANG 환경변수   — 일회성 확인용
#   2) 설정의 lang
#   3) $LC_ALL / $LANG          — 처음 설치할 때 제안값
#   4) ko
dt_lang() {
  local l="${DEVTRAIL_LANG:-}"
  [ -z "$l" ] && [ -f "${CONFIG_FILE:-}" ] && l=$(cfg '.lang' '')
  [ -z "$l" ] && l=$(dt_lang_from_locale)
  case " $DT_LANGS " in *" $l "*) printf '%s' "$l" ;; *) printf 'ko' ;; esac
}

# 로케일에서 제안값을 뽑는다. 판단이 아니라 '제안'이다 — init 이 물어본다.
dt_lang_from_locale() {
  case "${LC_ALL:-${LANG:-}}" in
    ko*|*_KR*) printf 'ko' ;;
    '')        printf 'ko' ;;   # 로케일이 없으면 기본값
    *)         printf 'en' ;;
  esac
}

# tree.json 등에서 언어별 필드를 고른다.
#   dt_field <jq객체표현> <필드>   →  .<필드>_en 이 있으면 그것, 없으면 .<필드>
# jq 안에서 쓰기 위한 표현식을 낸다.
dt_jq_field() {
  local f="$1"
  if [ "$(dt_lang)" = "en" ]; then
    printf '(.%s_en // .%s)' "$f" "$f"
  else
    printf '.%s' "$f"
  fi
}

# 태그 네임스페이스.
#
# ⚠️ #type/* · #project/* · #area/* 는 언어와 무관하다 — 자동 이동 규칙이
#    이것들로 동작한다. 언어를 타는 것은 사용자가 손으로 붙이는 두 가지뿐이다.
#
# dt_ns <키>   topic | maturity
dt_ns() {
  if [ "$(dt_lang)" = "en" ]; then
    case "$1" in topic) printf 'topic' ;; maturity) printf 'maturity' ;; *) printf '%s' "$1" ;; esac
  else
    case "$1" in topic) printf '주제' ;; maturity) printf '상태' ;; *) printf '%s' "$1" ;; esac
  fi
}

# 메시지 카탈로그를 읽는다. 없는 언어는 ko 로 떨어진다.
dt_load_messages() {
  local l; l="$(dt_lang)"
  local f="$DEVTRAIL_ROOT/lib/i18n/${l}.sh"
  [ -f "$f" ] || f="$DEVTRAIL_ROOT/lib/i18n/ko.sh"
  [ -f "$f" ] && . "$f"
}

# msg <키> [인자...]  — 카탈로그에서 찾아 printf 로 낸다.
#
# 키가 없으면 키 이름을 그대로 낸다. 죽지 않는다 — 번역이 빠졌다고
# 명령이 실패하면 안 된다. 대신 눈에 띄게 [key] 로 감싼다.
msg() {
  local key="$1"; shift
  local var="M_$key" val
  eval "val=\${$var:-}"
  if [ -z "$val" ]; then printf '[%s]' "$key"; return 0; fi
  # shellcheck disable=SC2059
  printf "$val" "$@"
}
