#!/usr/bin/env bash
# 배포용 DMG 를 만든다 (ADR 0006 M4-4).
#
#   ./scripts/make-dmg.sh            dist/DevTrail-<version>.dmg
#   ./scripts/make-dmg.sh <경로>     경로를 지정
#
# ⚠️ **현재 DMG 는 macOS 베타 배포용이다.**
#
#    서명이 ad-hoc 이고 Apple 공증(notarization)을 받지 않았기 때문에 다른
#    맥에서는 Gatekeeper 경고가 나온다. 릴리즈에는 control-클릭 → 열기와,
#    꼭 필요할 때만 격리 속성을 지우는 절차를 함께 안내한다. 이를 서명·공증된
#    정식 배포판처럼 표현해서는 안 된다.
#
# ⚠️ 사람이 봐야 하는 것은 자동화가 대신하지 못한다 — DMG 열기, 드래그,
#    첫 실행, Gatekeeper 대화상자. 확인하지 않은 것을 확인했다고 말하지 않는다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

APP="$ROOT/app/build/DevTrail.app"
VERSION=$(tr -d ' \n' < VERSION 2>/dev/null)
OUT="${1:-$ROOT/dist/DevTrail-$VERSION.dmg}"
VOLNAME="DevTrail $VERSION"

die() { printf '%s\n' "$*" >&2; exit 1; }

[ -n "$VERSION" ] || die "❌ VERSION 을 읽을 수 없습니다"
[ -d "$APP" ] || die "❌ 앱이 없습니다: $APP  (./app/build.sh)"
command -v hdiutil >/dev/null 2>&1 || die "❌ hdiutil 이 필요합니다 (macOS)"
command -v codesign >/dev/null 2>&1 || die "❌ codesign 이 필요합니다"

# ⚠️ 담기 전에 앱이 성한지 본다. 깨진 앱을 DMG 로 싸면, 문제가 한 겹 뒤로
#    숨어서 "DMG 가 이상하다" 로 보이게 된다.
codesign --verify "$APP" >/dev/null 2>&1 \
  || die "❌ 앱 서명이 유효하지 않습니다 — ./app/build.sh 를 다시 실행하세요"

STAGE=$(mktemp -d) || die "❌ 임시 디렉터리를 만들 수 없습니다"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "▶ 담는 중… $VOLNAME"
# ⚠️ -R 로 복사한다. 심볼릭 링크·권한·서명을 그대로 옮겨야 한다.
cp -R "$APP" "$STAGE/DevTrail.app" || die "❌ 앱을 담지 못했습니다"

# ⚠️ /Applications 로 가는 심볼릭 링크. 이게 없으면 사람은 앱을 어디로
#    끌어다 놓아야 하는지 모른다 — DMG 배포의 사실상 표준이다.
ln -s /Applications "$STAGE/Applications" || die "❌ Applications 링크를 만들지 못했습니다"

mkdir -p "$(dirname "$OUT")" || die "❌ 출력 디렉터리를 만들 수 없습니다"
rm -f "$OUT"

echo "▶ DMG 생성…"
# UDZO = 압축(zlib). 읽기 전용이라 받은 사람이 내용을 바꿀 수 없다.
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$OUT" || die "❌ DMG 를 만들지 못했습니다"

[ -f "$OUT" ] || die "❌ DMG 가 생기지 않았습니다: $OUT"

# ⚠️ DMG 자체도 서명한다. M7 에서 Developer ID 로 바꾸면 공증 대상이 된다.
#    실패를 삼키지 않는다 — 계약과 실제 정책이 어긋나면 M7 에서야 드러난다.
codesign --force --sign - "$OUT" 2>&1 || die "❌ DMG 서명 실패"
codesign --verify "$OUT" 2>&1 || die "❌ DMG 서명 검증 실패"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)

printf '✅ %s\n' "$OUT"
printf '   %s · %s bytes\n' "$VOLNAME" "$SIZE"
printf '   sha256 %s\n' "$SHA"
printf '\n'
printf '⚠️  macOS 베타: ad-hoc 서명이며 Apple 공증 전입니다. 다른 맥에서는\n'
printf '    Gatekeeper 경고가 날 수 있으므로 릴리즈의 설치 안내를 함께 제공하세요.\n'
