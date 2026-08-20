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
VERSION="0.1.0"
OUT="build/$APP_NAME.app"

command -v swift >/dev/null 2>&1 || { echo "❌ swift 없음 — Xcode 또는 Command Line Tools 필요"; exit 1; }

echo "▶ 빌드 중…"
swift build -c release --disable-sandbox 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true

BIN=$(swift build -c release --show-bin-path)/DevTrailApp
[ -x "$BIN" ] || { echo "❌ 빌드 산출물 없음: $BIN"; exit 1; }

echo "▶ .app 번들 조립…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"

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
codesign --force --sign - "$OUT" 2>/dev/null && echo "  ad-hoc 서명 완료" || echo "  (서명 생략)"

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
