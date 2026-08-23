#!/usr/bin/env bash
# DevTrail 메뉴바 앱 빌드.
#
#   ./app/build.sh              릴리즈 빌드 → app/build/DevTrail.app
#   ./app/build.sh --install    빌드 후 /Applications 에 복사
#   ./app/build.sh --run        빌드 후 바로 실행
#
# SwiftPM은 실행 파일만 만든다. 메뉴바 앱이 되려면 .app 번들 구조와
# Info.plist(LSUIElement=1)가 필요해서 여기서 직접 조립한다.
# 코드 서명은 하지 않는다 — 직접 빌드한 앱은 서명 없이도 실행된다.
# (남에게 '빌드된 앱'을 배포할 때만 서명·공증이 필요하다.)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="DevTrail"
BUNDLE_ID="com.devtrail.menubar"
# cd 를 이미 했으므로 여기서는 상대경로가 app/ 기준이다.
VERSION=$(cat ../VERSION 2>/dev/null || echo "0.0.0-dev")
OUT="build/$APP_NAME.app"

command -v swift >/dev/null 2>&1 || { echo "❌ swift 없음 — Xcode 또는 Command Line Tools 필요"; exit 1; }

# ⚠️ **universal 로 만든다** (arm64 + x86_64).
#
#    최소 macOS 가 14 인데(D1), macOS 14 는 **Intel 맥도 지원한다.**
#    호스트 아키텍처만 만들면 Apple Silicon 에서 빌드한 DMG 가 Intel 맥에서
#    아예 뜨지 않는다 — "설치는 됐는데 안 열린다" 는 종류다.
#
#    앱·헬퍼 **둘 다** 해당한다. 하나만 universal 이면 소용없다.
ARCHS="--arch arm64 --arch x86_64"

echo "▶ 빌드 중… (universal: arm64 + x86_64)"
# shellcheck disable=SC2086
swift build -c release $ARCHS --disable-sandbox 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]|^[0-9]+%' || true

# shellcheck disable=SC2086
BINDIR=$(swift build -c release $ARCHS --show-bin-path)
BIN="$BINDIR/DevTrailApp"
HELPER_BIN="$BINDIR/DevTrailHelper"
[ -x "$BIN" ] || { echo "❌ 빌드 산출물 없음: $BIN"; exit 1; }
[ -x "$HELPER_BIN" ] || { echo "❌ 헬퍼 산출물 없음: $HELPER_BIN"; exit 1; }

# ⚠️ universal 인지 **확인한다.** 플래그를 줬다고 되는 게 아니다 —
#    툴체인이 조용히 호스트만 만들 수 있다.
for b in "$BIN" "$HELPER_BIN"; do
  archs=$(lipo -archs "$b" 2>/dev/null)
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "❌ universal 이 아닙니다: $(basename "$b") → $archs"; exit 1 ;;
  esac
done
echo "  universal 확인: arm64 + x86_64"

echo "▶ .app 번들 조립…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Helpers"
cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"

# ⚠️ 헬퍼를 번들에 넣는다. lib/common.sh 의 dt_helper 가 2순위로 여기를
#    본다 — 경로가 어긋나면 조용히 python3 폴백으로 떨어진다.
cp "$HELPER_BIN" "$OUT/Contents/Helpers/devtrail-helper"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- 메뉴바 전용 앱: Dock 아이콘과 ⌘Tab 에 나타나지 않는다 -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if ! plutil -lint "$OUT/Contents/Info.plist" >/dev/null; then
  echo "❌ Info.plist 오류"; exit 1
fi

# 서명 없는 번들은 macOS가 격리할 수 있어 ad-hoc 서명만 붙인다(무료, 로컬 전용).
#
# ⚠️ **안쪽부터 서명한다.** 번들만 서명하면 Contents/Helpers 안의 실행
#    파일이 서명되지 않은 채 남고, 공증(M7) 에서 거부된다.
codesign --force --sign - "$OUT/Contents/Helpers/devtrail-helper" 2>/dev/null || true
codesign --force --sign - "$OUT" 2>/dev/null && echo "  ad-hoc 서명 완료 (헬퍼 포함)" || echo "  (서명 생략)"

# ⚠️ 헬퍼가 번들 안에서 **실제로 실행되는지** 본다. 복사만 하고 실행 권한이
#    빠지거나 서명이 깨지면 여기서 걸린다.
if "$OUT/Contents/Helpers/devtrail-helper" version >/dev/null 2>&1; then
  echo "  헬퍼 실행 확인"
else
  echo "❌ 번들 안 헬퍼가 실행되지 않습니다"; exit 1
fi

echo "✅ $OUT"

case "${1:-}" in
  --install)
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$OUT" /Applications/
    echo "✅ /Applications/$APP_NAME.app 설치됨"
    ;;
  --run)
    open "$OUT"
    echo "✅ 실행했습니다 — 메뉴바를 확인하세요"
    ;;
esac
