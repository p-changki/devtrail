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

# ⚠️ 최소 macOS 의 정본은 **Package.swift 하나**다 (D1: macOS 14).
#    Info.plist 에 숫자를 직접 적으면 두 벌이 되고, 한쪽만 올리는 날
#    "설치는 됐는데 안 열린다" 가 된다.
MIN_MACOS=$(grep -oE 'macOS\(\.v([0-9]+)\)' Package.swift | grep -oE '[0-9]+' | head -1)
[ -n "$MIN_MACOS" ] || { echo "❌ Package.swift 에서 최소 macOS 를 읽지 못했습니다"; exit 1; }

command -v swift >/dev/null 2>&1 || { echo "❌ swift 없음 — Xcode 또는 Command Line Tools 필요"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq 없음 — 번들 jq 락 파일을 읽어야 합니다"; exit 1; }
# ⚠️ 서명은 선택이 아니다 (아래 참조). 없으면 여기서 세운다.
command -v codesign >/dev/null 2>&1 || { echo "❌ codesign 없음 — Xcode Command Line Tools 필요"; exit 1; }

# ── 번들 jq 관문 ─────────────────────────────────────────────────────────────
#
# ⚠️ **빌드보다 먼저 세운다.** 90초짜리 swift 빌드를 끝내고 나서 "jq 가
#    어긋났습니다" 를 말하면 늦다. 그리고 여기서 막히면 기존 번들은
#    건드리지 않은 채로 남는다 — rm -rf "$OUT" 은 아래에 있다.
#
#    DMG 를 받는 사람에게 jq 가 있다고 가정할 수 없다. CLI 는 40개 파일
#    139곳에서 jq 를 부른다 — 없으면 앱이 켜진 채로 아무것도 못 한다.
#
#    출처·해시·라이선스의 정본은 vendor/jq/jq.lock.json 이고,
#    scripts/fetch-jq.sh 가 상류 해시와 대조해 만든다. 여기서는 **만들어진
#    것이 락과 맞는지 다시 확인**한다 — 오래된 산출물이 조용히 실려 나가는
#    것을 막는다.
#
#    ⚠️ 실린 jq 를 나중에 상류 해시로 되짚을 수는 **없다.** 서명이 바이트를
#       바꾸고, 서명을 지워도 원본으로 돌아오지 않는다(실측). 그래서 무결성은
#       넣기 **전에** 확인해야 하고, 이 관문이 마지막 기회다.
if ! ../scripts/fetch-jq.sh --check >/dev/null 2>&1; then
  echo "❌ 번들 jq 가 락과 어긋납니다 — ./scripts/fetch-jq.sh 를 먼저 실행하세요"
  ../scripts/fetch-jq.sh --check
  exit 1
fi

# ⚠️ jq 가 요구하는 최소 macOS 가 우리 최소보다 **높으면** 안 된다.
#    앱은 뜨는데 jq 만 못 도는 기계가 생긴다 — 그때는 에러도 이상하게 난다.
JQ_MIN=$(jq -r '.min_macos' ../vendor/jq/jq.lock.json 2>/dev/null | cut -d. -f1)
case "$JQ_MIN" in
  ''|*[!0-9]*) echo "❌ 락에서 jq 의 min_macos 를 읽지 못했습니다"; exit 1 ;;
esac
if [ "$JQ_MIN" -gt "$MIN_MACOS" ]; then
  echo "❌ 번들 jq 는 macOS $JQ_MIN 이상이 필요한데 앱 최소는 $MIN_MACOS 입니다"
  exit 1
fi

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

# ⚠️ jq 를 함께 넣는다 (ADR 0006 D1). 검사는 이미 위에서 끝났다.
cp ../vendor/jq/build/jq "$OUT/Contents/Helpers/jq"
chmod +x "$OUT/Contents/Helpers/jq"

# ⚠️ 라이선스를 **원본 그대로** 넣는다. MIT 하나가 아니라 다섯 블록이다
#    (jq · Lucent decNumber · ICU · KTH · NetBSD strptime). 요약하면 틀린다.
mkdir -p "$OUT/Contents/Resources/licenses"
cp ../vendor/jq/build/COPYING "$OUT/Contents/Resources/licenses/jq-COPYING.txt"


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
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}.0</string>
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
#
# ⚠️ **실패하면 빌드를 세운다.** 예전에는 `|| true` 로 넘겼는데, 그러면
#    서명이 통째로 실패해도 빌드가 초록불로 끝난다 — 문서와 테스트는
#    "안쪽부터 서명한다" 를 배포 계약으로 말하는데 실제 정책만 달랐다.
#    그 차이는 M7 공증에서야 드러나고, 그때는 원인이 멀어져 있다.
for _sig in "$OUT/Contents/Helpers/devtrail-helper" \
            "$OUT/Contents/Helpers/jq" \
            "$OUT"; do
  codesign --force --sign - "$_sig" 2>&1 \
    || { echo "❌ 서명 실패: ${_sig#"$OUT"/}"; exit 1; }
done

# ⚠️ 서명했다는 것과 서명이 유효하다는 것은 다르다. 안쪽부터 확인한다 —
#    바깥 번들 서명은 안쪽이 나중에 바뀌면 조용히 깨진다.
for _sig in "$OUT/Contents/Helpers/devtrail-helper" \
            "$OUT/Contents/Helpers/jq" \
            "$OUT"; do
  codesign --verify "$_sig" 2>&1 \
    || { echo "❌ 서명 검증 실패: ${_sig#"$OUT"/}"; exit 1; }
done
echo "  ad-hoc 서명 완료 (헬퍼 · jq · 번들)"

# ⚠️ 헬퍼가 번들 안에서 **실제로 실행되는지** 본다. 복사만 하고 실행 권한이
#    빠지거나 서명이 깨지면 여기서 걸린다.
if "$OUT/Contents/Helpers/devtrail-helper" version >/dev/null 2>&1; then
  echo "  헬퍼 실행 확인"
else
  echo "❌ 번들 안 헬퍼가 실행되지 않습니다"; exit 1
fi

# ⚠️ jq 도 **돌려 본다.** 서명이 깨지거나 실행 권한이 빠지면 여기서 걸린다.
#    "파일이 있다" 로는 배포할 수 없다.
JQ_WANT=$(jq -r '.version' ../vendor/jq/jq.lock.json)
JQ_GOT=$("$OUT/Contents/Helpers/jq" --version 2>/dev/null) || {
  echo "❌ 번들 안 jq 가 실행되지 않습니다"; exit 1
}
[ "$JQ_GOT" = "$JQ_WANT" ] || { echo "❌ 번들 jq 가 $JQ_GOT 라고 답합니다 (락: $JQ_WANT)"; exit 1; }
echo "  jq 실행 확인 ($JQ_GOT)"

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
