#!/usr/bin/env bash
# 셸이 생성기를 부르는 **통로**가 하나인가, 그리고 두 경로가 같은 답을 내는가.
#
# ⚠️ 왜 필요한가 (ADR 0006 M3)
#
#    헬퍼가 있으면 헬퍼, 없으면 python3 로 떨어진다. 그 두 갈래가 다른 답을
#    내면 "내 기계에서는 되는데" 가 생긴다 — 개발자는 헬퍼를 빌드해 두고
#    사용자는 python 폴백을 쓰기 때문이다.
#
#    그리고 호출부가 다시 python3 를 직접 부르기 시작하면 이관이 조용히
#    풀린다. 그것도 여기서 막는다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

HELPER="$ROOT/app/.build/debug/DevTrailHelper"

t_start "생성기를 부르는 곳이 하나다"
# ⚠️ lib/ 안에서 python3 로 생성기를 **직접** 부르는 자리가 없어야 한다.
#    통로(dt_gen)만 부른다. 주석은 세지 않는다.
DIRECT=$(grep -rnE '^[^#]*python3 "\$(DEVTRAIL_ROOT|DT_SCAN_PY)' "$ROOT/lib" 2>/dev/null \
         | grep -v '_dt_gen_script\|dt_gen()' | wc -l | tr -d ' ')
t_eq "lib 안에 직접 호출이 없다" "0" "$DIRECT"
t_contains "통로 함수가 있다" "dt_gen()" "$(cat "$ROOT/lib/common.sh")"
t_contains "헬퍼 해석 함수가 있다" "dt_helper()" "$(cat "$ROOT/lib/common.sh")"

t_start "폴백 표가 실제 스크립트를 가리킨다"
# ⚠️ 표에 적힌 경로가 없으면 폴백이 조용히 죽는다.
MISS=""
while IFS= read -r rel; do
  [ -f "$ROOT/$rel" ] || MISS="$MISS $rel"
done <<EOF
$(grep -oE 'lib/(gen/)?[a-z]+\.py' "$ROOT/lib/common.sh" | sort -u)
EOF
t_eq "표의 스크립트가 전부 있다" "" "$(printf '%s' "$MISS" | sed 's/ *$//')"

t_start "헬퍼가 없으면 python3 로 떨어진다"
NOHELP=$(DT_HELPER_OVERRIDE=/nonexistent /bin/bash -c '
  . "$1/lib/common.sh" >/dev/null 2>&1
  dt_helper >/dev/null 2>&1 && echo helper || echo fallback
' _ "$ROOT" 2>/dev/null)
# ⚠️ 저장소에 빌드 산출물이 있으면 3순위에서 잡힌다. 그 경우는 helper 가 맞다.
if [ -x "$HELPER" ]; then
  t_eq "빌드가 있으면 헬퍼를 쓴다" "helper" "$NOHELP"
else
  t_eq "빌드가 없으면 python3 로 떨어진다" "fallback" "$NOHELP"
fi

t_start "⚠️ 두 경로가 **같은 답**을 낸다"
if [ ! -x "$HELPER" ]; then
  dim "   헬퍼 빌드 없음 — 건너뜀 (⚠️ 두 갈래가 갈려도 모른다)"
else
  CFG="$T_TMP/config.json"
  cat > "$CFG" <<'JSON'
{
  "version": 3, "lang": "ko",
  "vault": { "backend": "local", "path": "/tmp/x", "root": "notes" },
  "dirs": {}, "headings": {}, "github": { "project_groups": {} },
  "ai": {}, "install": {}
}
JSON
  PATHS="$T_TMP/paths.json"
  printf '%s' '{"paths":{"templates":"notes/템플릿","devlog":"notes/d","inbox":"notes/i"}}' > "$PATHS"

  # run_gen <헬퍼경로 또는 빈문자열> <하위명령> [인자…]
  run_gen() {
    local h="$1"; shift
    if [ -n "$h" ]; then
      DT_HELPER_OVERRIDE="$h" DEVTRAIL_LANG=ko LC_ALL=C.UTF-8 /bin/bash -c '
        . "$1/lib/common.sh" >/dev/null 2>&1; shift; dt_gen "$@"
      ' _ "$ROOT" "$@" 2>/dev/null
    else
      # ⚠️ 헬퍼를 못 찾게 만든다. 저장소 빌드까지 가려야 하므로
      #    DEVTRAIL_ROOT 를 빈 사본으로 돌린다.
      DT_HELPER_OVERRIDE=/nonexistent DEVTRAIL_LANG=ko LC_ALL=C.UTF-8 \
      DT_FORCE_PYTHON=1 /bin/bash -c '
        . "$1/lib/common.sh" >/dev/null 2>&1; shift
        script=$(_dt_gen_script "$1") || exit 2; sub="$1"; shift
        python3 "$script" "$@"
      ' _ "$ROOT" "$@" 2>/dev/null
    fi
  }

  same() {   # same <설명> <하위명령> [인자…]
    local label="$1"; shift
    local a b
    a=$(run_gen "$HELPER" "$@")
    b=$(run_gen "" "$@")
    if [ "$a" = "$b" ]; then
      # ⚠️ 둘 다 빈 답이면 같다고 말하면 안 된다 — 아무것도 안 한 것이다.
      if [ -z "$a" ]; then
        _t_bad "$label" "두 경로가 **둘 다 빈 답**을 냈습니다" "$*"
        FAILED=1
      else
        _t_ok "$label"
      fi
    else
      _t_bad "$label" "헬퍼와 python 이 다릅니다" "$(diff <(printf '%s' "$a") <(printf '%s' "$b") | head -6)"
      FAILED=1
    fi
  }

  FAILED=0
  same "smartenv 가 같다" gen-smartenv "$ROOT/preset/tree.json" "$CFG" "notes/템플릿" ""
  same "anm 이 같다"      gen-anm "$ROOT/preset/tree.json" "$CFG" "$ROOT/preset/profiles/new.json" ""
  same "hotkeys 가 같다"  gen-hotkeys hotkeys "$ROOT/preset/obsidian/hotkeys.tmpl.json" "$PATHS" "" ""
  same "daily 가 같다"    gen-hotkeys daily "$ROOT/preset/obsidian/hotkeys.tmpl.json" "$PATHS" ""
fi

t_start "doctor 가 어느 경로를 쓰는지 말한다"
# ⚠️ 주석이 아니라 **실행되는 줄**을 본다. 처음엔 파일 전체에서 문자열만
#    찾았는데, 경고 줄을 지워도 주석 속 "폴백" 이 걸려 변이가 살아남았다
#    (2026-08-24). 적혀 있다 ≠ 한다.
LIVE=$(grep -vE '^\s*#' "$ROOT/lib/doctor.sh")
t_eq "헬퍼일 때 알린다" "1" \
  "$(printf '%s' "$LIVE" | grep -cE 'ok .*생성기' | tr -d ' ')"
t_eq "폴백일 때 **경고**한다" "1" \
  "$(printf '%s' "$LIVE" | grep -cE 'warn .*생성기' | tr -d ' ')"
t_eq "빌드 방법을 알려준다" "1" \
  "$(printf '%s' "$LIVE" | grep -c 'swift build' | tr -d ' ')"
t_eq "dt_helper 로 판정한다" "1" \
  "$(printf '%s' "$LIVE" | grep -c 'dt_helper' | tr -d ' ')"

t_end
