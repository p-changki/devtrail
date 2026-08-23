#!/usr/bin/env bash
# DMG 가 **배포할 수 있는 모양**인가 (ADR 0006 M4-4).
#
# ⚠️ 소스가 아니라 산출물을 본다. 실제로 **마운트해서** 안을 연다 —
#    "hdiutil 을 불렀다" 와 "열리는 이미지가 나왔다" 는 다르다.
#
# ⚠️ 지금 이 DMG 는 **남에게 줄 수 없다.** ad-hoc 서명이고 공증을 받지
#    않았다. 이 파일은 그 사실도 **단언으로 못 박는다** — 아무도 "이제
#    배포해도 된다" 고 잘못 말하지 못하도록. M7 에서 의도적으로 뒤집는다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

VERSION=$(tr -d ' \n' < "$ROOT/VERSION")
DMG="$ROOT/dist/DevTrail-$VERSION.dmg"

# ⚠️ 마운트한 것은 **반드시** 떼어낸다. 중간에 실패해도 붙어 있으면 다음
#    실행이 이상하게 깨지고, 원인이 여기라는 걸 아무도 못 찾는다.
DT_TMP=$(mktemp -d)
MNT=""
_detach() {
  [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null
  MNT=""
}
_cleanup() { _detach; rm -rf "$DT_TMP"; }
trap _cleanup EXIT

t_start "DMG 만드는 법이 한 곳에 있다"
t_eq "make-dmg.sh 가 실행 가능하다" "yes" \
  "$([ -x "$ROOT/scripts/make-dmg.sh" ] && echo yes || echo no)"
MD=$(grep -vE '^\s*#' "$ROOT/scripts/make-dmg.sh")
# ⚠️ 이름에 버전이 들어가야 한다. 같은 이름으로 덮어쓰면 사람이 어느 판을
#    받았는지 말할 수 없게 된다.
t_eq "출력 이름에 VERSION 을 쓴다" "yes" \
  "$(printf '%s' "$MD" | grep -q 'DevTrail-\$VERSION\.dmg' && echo yes || echo no)"
# ⚠️ /Applications 링크가 없으면 사람은 어디로 끌어다 놓는지 모른다.
t_eq "Applications 링크를 만든다" "1" \
  "$(printf '%s\n' "$MD" | grep -cE '^[[:space:]]*ln -s /Applications' | tr -d ' ')"

# ⚠️ **여기서 직접 만든다.** 만들어 두고 검사하는 순서로 두면, 앞 판의
#    DMG 를 보면서 통과할 수 있다 — 산출물이 낡았는지 아무도 모른다.
#    (헬퍼 계약 시험이 헬퍼를 직접 빌드하는 것과 같은 이유다.)
if [ -d "$ROOT/app/build/DevTrail.app" ]; then
  t_start "DMG 를 실제로 만든다"
  rm -f "$DMG"
  if "$ROOT/scripts/make-dmg.sh" > "$DT_TMP/dmg.log" 2>&1; then
    _t_ok "make-dmg.sh"
  else
    _t_bad "make-dmg.sh" "DMG 를 만들지 못했습니다" "$(tail -5 "$DT_TMP/dmg.log")"
    FAILED=1
  fi
fi

if [ ! -f "$DMG" ]; then
  t_start "DMG 산출물"
  dim "   app/build/DevTrail.app 이 없어 만들지 못했습니다 — 건너뜀"
  dim "   빌드: ./app/build.sh"
  t_end
  exit 0
fi

t_start "⚠️ 실제로 마운트된다"
t_eq "이미지 형식이 압축 읽기전용(UDZO)" "1" \
  "$(hdiutil imageinfo "$DMG" 2>/dev/null | grep -c '^Format: UDZO' | tr -d ' ')"

MNT=$(hdiutil attach "$DMG" -nobrowse -readonly -mountrandom /tmp 2>/dev/null \
      | tail -1 | awk '{$1="";$2="";sub(/^ +/,"");print}')
t_eq "마운트됐다" "yes" "$([ -n "$MNT" ] && [ -d "$MNT" ] && echo yes || echo no)"

if [ -n "$MNT" ] && [ -d "$MNT" ]; then
  A="$MNT/DevTrail.app"

  t_start "받은 사람이 보는 것"
  t_eq "앱이 있다" "yes" "$([ -d "$A" ] && echo yes || echo no)"
  # ⚠️ 심볼릭 링크 **자체**를 본다. -d 로 보면 /Applications 를 따라가서
  #    링크가 없어도 통과한다.
  t_eq "Applications 로 가는 링크가 있다" "yes" \
    "$([ -L "$MNT/Applications" ] && echo yes || echo no)"
  t_eq "링크가 /Applications 를 가리킨다" "/Applications" \
    "$(readlink "$MNT/Applications" 2>/dev/null)"

  t_start "DMG 안의 앱이 성하다"
  # ⚠️ 압축·복사 과정에서 깨질 수 있다. 담기 전이 아니라 **꺼낸 것**을 본다.
  t_eq "universal 이다 (아키텍처 2종)" "2" \
    "$(lipo -archs "$A/Contents/MacOS/DevTrail" 2>/dev/null \
       | tr ' ' '\n' | grep -cE '^(arm64|x86_64)$' | tr -d ' ')"
  t_eq "번들 jq 가 실행된다" \
    "$(jq -r '.version' "$ROOT/vendor/jq/jq.lock.json" 2>/dev/null)" \
    "$("$A/Contents/Helpers/jq" --version 2>/dev/null)"
  t_eq "번들 CLI 가 답한다" "devtrail $VERSION" \
    "$( (cd / && "$A/Contents/Resources/bin/devtrail" version 2>/dev/null | head -1) )"
  t_eq "서명이 살아 있다" "0" "$(codesign --verify "$A" >/dev/null 2>&1; echo $?)"
  t_eq "번들 버전이 VERSION 과 같다" "$VERSION" \
    "$(plutil -extract CFBundleShortVersionString raw "$A/Contents/Info.plist" 2>/dev/null)"

  t_start "⚠️ 아직 남에게 줄 수 없다 (M7 전)"
  # ⚠️ 이건 "고장" 이 아니라 **현재 사실**이다. 단언으로 못 박아 두는 이유는,
  #    누군가 "이제 배포해도 된다" 고 잘못 말하는 것을 막기 위해서다.
  #
  #    M7 에서 Developer ID + 공증이 붙으면 이 단언은 **의도적으로** 뒤집는다.
  #    그때 이 줄을 고치는 행위가 곧 "배포 가능해졌다" 는 선언이 된다.
  t_eq "서명이 ad-hoc 이다" "1" \
    "$(codesign -dvv "$A" 2>&1 | grep -c 'Signature=adhoc' | tr -d ' ')"
  t_eq "Gatekeeper 가 아직 거부한다" "1" \
    "$(spctl --assess --type execute "$A" 2>&1 | grep -c 'rejected' | tr -d ' ')"

  t_start "DMG 자체도 서명돼 있다"
  # ⚠️ M7 에서 이 서명이 Developer ID 로 바뀌고 공증 대상이 된다. 지금
  #    비어 있으면 그때 "왜 안 되지" 를 여기서부터 되짚어야 한다.
  t_eq "codesign --verify" "0" "$(codesign --verify "$DMG" >/dev/null 2>&1; echo $?)"
fi

_detach

# ══ 파괴적 시험은 맨 뒤 ═════════════════════════════════════════════════════
#
# ⚠️ 아래는 빌드된 .app 을 일부러 망가뜨린다. 위쪽 단언들이 보던 산출물을
#    중간에 건드리면 그 단언들이 무효가 된다 — M4-3 에서 겪었다.

t_start "⚠️ 깨진 앱은 담지 않는다"
# ⚠️ 문제를 한 겹 뒤로 숨기지 않는다. 깨진 앱을 DMG 로 싸면 증상이
#    "DMG 가 이상하다" 로 보이고, 원인에서 멀어진다.
APPB="$ROOT/app/build/DevTrail.app"
if [ -d "$APPB" ]; then
  cp -R "$APPB" "$DT_TMP/app-bak"
  # 봉인된 파일을 건드리면 서명이 깨진다.
  printf 'x' >> "$APPB/Contents/Resources/VERSION"
  t_eq "서명이 깨진 앱이면 make-dmg.sh 가 실패한다" "no" \
    "$("$ROOT/scripts/make-dmg.sh" >/dev/null 2>&1 && echo yes || echo no)"
  rm -rf "$APPB"; cp -R "$DT_TMP/app-bak" "$APPB"
  t_eq "복원됐다 (서명 유효)" "0" "$(codesign --verify "$APPB" >/dev/null 2>&1; echo $?)"
fi

t_start "⚠️ DMG 서명이 실패하면 만들지 않는다"
# ⚠️ 문자열로는 확인할 수 없다 — 실제로 실패시켜 본다. jq·앱 번들에서 쓴
#    방식과 같다: 우리 산출물에만 실패하는 codesign 을 PATH 에 심는다.
if [ -d "$APPB" ]; then
  CSD="$DT_TMP/cs"
  mkdir -p "$CSD"
  cat > "$CSD/codesign" <<'FAKE'
#!/bin/sh
case "$*" in
  *.dmg*) echo "fake codesign: dmg refused" >&2; exit 1 ;;
esac
exec /usr/bin/codesign "$@"
FAKE
  chmod +x "$CSD/codesign"
  t_eq "DMG 서명이 실패하면 make-dmg.sh 가 실패한다" "no" \
    "$(PATH="$CSD:$PATH" "$ROOT/scripts/make-dmg.sh" >/dev/null 2>&1 && echo yes || echo no)"
  # ⚠️ 마지막에 성한 DMG 를 남겨 둔다. 뒤에 오는 사람이 반쯤 만든 것을
  #    집어들지 않도록.
  "$ROOT/scripts/make-dmg.sh" >/dev/null 2>&1 || dim "   ⚠️ DMG 재생성 실패"
fi

t_end
