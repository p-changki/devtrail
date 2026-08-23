#!/usr/bin/env bash
# .app 번들이 **배포할 수 있는 모양**인가 (ADR 0006 M4).
#
# ⚠️ 왜 필요한가
#
#    최소 macOS 가 14 인데(D1), **macOS 14 는 Intel 맥도 지원한다.**
#    Apple Silicon 에서 빌드하면 기본이 arm64 하나라, 그대로 DMG 를 만들면
#    Intel 맥에서 **아예 열리지 않는다** — "설치는 됐는데 안 열린다" 는
#    종류이고, 만든 사람 기계에서는 영원히 재현되지 않는다.
#
#    그리고 헬퍼가 번들 안에 없으면 `dt_helper` 가 조용히 python3 폴백으로
#    떨어진다. python3 가 없는 기계에서는 그때 아무 말 없이 실패한다.
#
# ⚠️ 소스를 읽는 것으로는 부족하다. **빌드 산출물을 본다.** 플래그를 줬다고
#    universal 이 되는 게 아니다 — 툴체인이 조용히 호스트만 만들 수 있다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

APP="$ROOT/app/build/DevTrail.app"

t_start "빌드 스크립트가 universal 을 요구한다"
BS=$(cat "$ROOT/app/build.sh")
# ⚠️ 주석이 아니라 **실행되는 줄**을 본다.
LIVE=$(printf '%s' "$BS" | grep -vE '^\s*#')
t_eq "두 아키텍처를 함께 준다" "1" \
  "$(printf '%s' "$LIVE" | grep -cE 'arch arm64 --arch x86_64' | tr -d ' ')"
t_eq "결과를 lipo 로 확인한다" "1" \
  "$(printf '%s' "$LIVE" | grep -c 'lipo -archs' | tr -d ' ')"
# ⚠️ 횟수를 못 박지 않는다. 복사·서명·실행 확인 세 곳에서 쓰이고, 앞으로
#    더 늘 수 있다. 지켜야 할 것은 "쓰인다" 이지 "몇 번" 이 아니다.
t_eq "헬퍼를 번들에 넣는다" "no" \
  "$([ "$(printf '%s' "$LIVE" | grep -c 'Contents/Helpers/devtrail-helper' | tr -d ' ')" = 0 ] \
     && echo yes || echo no)"

t_start "번들이 dt_helper 가 찾는 경로와 맞는다"
# ⚠️ lib/common.sh 의 2순위가 .app/Contents/Helpers/devtrail-helper 다.
#    한쪽만 바꾸면 조용히 폴백으로 떨어진다.
t_contains "dt_helper 가 Helpers 를 본다" "Helpers/devtrail-helper" \
  "$(cat "$ROOT/lib/common.sh")"

if [ ! -d "$APP" ]; then
  t_start "빌드 산출물"
  dim "   app/build/DevTrail.app 없음 — 건너뜀 (⚠️ 실제 모양을 못 본다)"
  dim "   빌드: ./app/build.sh"
  t_end
  exit 0
fi

t_start "⚠️ 산출물이 실제로 universal 이다"
for rel in "Contents/MacOS/DevTrail" "Contents/Helpers/devtrail-helper"; do
  f="$APP/$rel"
  if [ ! -f "$f" ]; then
    _t_bad "$rel" "번들에 없습니다" "$f"
    FAILED=1
    continue
  fi
  archs=$(lipo -archs "$f" 2>/dev/null)
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) _t_ok "$rel — $archs" ;;
    *) _t_bad "$rel" "universal 이 아닙니다" "$archs"; FAILED=1 ;;
  esac
done

t_start "번들 안 헬퍼가 실제로 실행된다"
# ⚠️ 복사만 하고 실행 권한이 빠지거나 서명이 깨지면 여기서 걸린다.
#    "파일이 있다" 와 "돈다" 는 다른 문제다.
t_eq "version 이 답한다" "0" \
  "$("$APP/Contents/Helpers/devtrail-helper" version >/dev/null 2>&1; echo $?)"
t_eq "생성기가 답한다" "0" \
  "$("$APP/Contents/Helpers/devtrail-helper" gen-hotkeys daily \
       "$ROOT/preset/obsidian/hotkeys.tmpl.json" /dev/null "" >/dev/null 2>&1; echo $?)"

t_start "Info.plist 가 D1 과 맞는다"
MIN=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist" 2>/dev/null)
PKG=$(grep -oE 'macOS\(\.v([0-9]+)\)' "$ROOT/app/Package.swift" | grep -oE '[0-9]+' | head -1)
t_eq "LSMinimumSystemVersion 이 Package.swift 와 같다" "${PKG}.0" "$MIN"
t_eq "메뉴바 전용(LSUIElement)" "true" \
  "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist" 2>/dev/null)"
t_eq "번들 버전이 VERSION 과 같다" "$(tr -d ' \n' < "$ROOT/VERSION")" \
  "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null)"

t_start "서명이 번들 안쪽까지 닿는다"
# ⚠️ 번들만 서명하면 Contents/Helpers 안의 실행 파일이 서명되지 않은 채
#    남고, 공증(M7)에서 거부된다. ad-hoc 이라도 지금 확인해 둔다.
t_eq "번들 서명 확인" "0" "$(codesign --verify "$APP" >/dev/null 2>&1; echo $?)"
t_eq "헬퍼 서명 확인" "0" \
  "$(codesign --verify "$APP/Contents/Helpers/devtrail-helper" >/dev/null 2>&1; echo $?)"

t_end
