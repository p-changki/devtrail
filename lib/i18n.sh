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
    ko*|*_KR*)          printf 'ko' ;;
    # ⚠️ C · C.UTF-8 · POSIX 는 '영어'가 아니라 '로케일 정보 없음' 이다.
    #    서버 · Docker · cron · CI 에서 흔한 값이고, 이걸 영어로 읽으면
    #    한국어 사용자의 볼트에 영어 폴더가 생긴다. 실제로 CI 가 잡았다.
    ''|C|C.*|POSIX)     printf 'ko' ;;
    *)                  printf 'en' ;;
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

# ── 문구 ─────────────────────────────────────────────────────────────────────
#
# L <한국어> <English>
#
# 키 카탈로그를 두지 않는 이유:
#   이 CLI 의 메시지는 대부분 '왜 그런지'를 설명하는 산문이다. 키로 빼면
#   호출부에서 무슨 말을 하는지 안 보이고, 키와 문구가 어긋나는 새로운
#   버그 종류가 생긴다. 언어가 둘뿐이라 그 값을 하지 않는다.
#
# ⚠️ 두 인자를 반드시 다 준다. 하나만 주면 영어에서 한국어가 그대로 나온다.
#    tests/run.sh 가 검사한다.
L() {
  if [ "$(dt_lang)" = "en" ]; then printf '%s' "${2:-$1}"; else printf '%s' "$1"; fi
}
