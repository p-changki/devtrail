#!/usr/bin/env bash
# 번들에 넣을 jq 를 가져와 **상류 해시와 대조**하고 universal 로 합친다.
#
#   ./scripts/fetch-jq.sh          필요할 때만 받는다 (이미 맞으면 네트워크 안 씀)
#   ./scripts/fetch-jq.sh --check  받지 않고 현재 산출물만 검사한다
#
# ⚠️ 왜 이 파일이 있나 (ADR 0006 D1)
#
#    DMG 로 배포하는 앱은 사용자 기계에 jq 가 있다고 가정할 수 없다. 그래서
#    번들에 넣는데, 넣는 순간 **출처와 무결성이 우리 책임**이 된다.
#
#    "없으면 안내" 로는 늦다. 무결성은 사용자 기계가 아니라 **빌드 시점**에
#    지킨다 — 여기서 못 박고, 어긋나면 빌드를 세운다.
#
# ⚠️ 신뢰 기준점을 새로 만들지 않는다. 합친 universal 은 lipo -thin 으로
#    다시 쪼개 **상류가 발표한 슬라이스 해시**와 대조한다. 우리가 만든
#    해시를 우리가 확인하는 순환을 피한다.
#
# ⚠️ 이 스크립트는 네트워크를 쓴다. 산출물이 이미 맞으면 **쓰지 않는다** —
#    로컬 우선 정책상 평소 빌드가 네트워크에 묶이면 안 된다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

LOCK="vendor/jq/jq.lock.json"
OUTDIR="vendor/jq/build"
BIN="$OUTDIR/jq"
LIC="$OUTDIR/COPYING"

MODE="${1:-}"

die() { printf '%s\n' "$*" >&2; exit 1; }

command -v jq   >/dev/null 2>&1 || die "❌ jq 가 필요합니다 (락 파일을 읽어야 합니다)"
command -v lipo >/dev/null 2>&1 || die "❌ lipo 가 필요합니다 (Xcode Command Line Tools)"
[ -f "$LOCK" ] || die "❌ 락 파일이 없습니다: $LOCK"

VERSION=$(jq -r '.version' "$LOCK")
LIC_SHA=$(jq -r '.license.sha256' "$LOCK")
LIC_URL=$(jq -r '.license.url' "$LOCK")
BASE="https://github.com/jqlang/jq/releases/download/$VERSION"

[ -n "$VERSION" ] && [ "$VERSION" != "null" ] || die "❌ 락 파일에서 version 을 읽을 수 없습니다"

sha_of() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

# ── 산출물이 락과 맞는가 ─────────────────────────────────────────────────────
#
# ⚠️ universal 을 **쪼개서** 본다. 파일이 있다는 것과 그 안이 맞는다는 것은
#    다른 문제다.
verify() {
  local quiet="${1:-}" tmp arch want got n=0
  [ -f "$BIN" ] || { [ -n "$quiet" ] || echo "  산출물 없음: $BIN"; return 1; }
  [ -x "$BIN" ] || { [ -n "$quiet" ] || echo "  실행 권한 없음: $BIN"; return 1; }

  tmp=$(mktemp -d) || return 1
  while IFS=' ' read -r arch want; do
    [ -n "$arch" ] || continue
    n=$((n + 1))
    if ! lipo "$BIN" -thin "$arch" -output "$tmp/$arch" 2>/dev/null; then
      [ -n "$quiet" ] || echo "  $arch 슬라이스가 없습니다"
      rm -rf "$tmp"; return 1
    fi
    got=$(sha_of "$tmp/$arch")
    if [ "$got" != "$want" ]; then
      [ -n "$quiet" ] || { echo "  $arch 해시가 락과 다릅니다"; echo "    락:   $want"; echo "    실제: $got"; }
      rm -rf "$tmp"; return 1
    fi
  done <<EOF
$(jq -r '.slices[] | "\(.arch) \(.sha256)"' "$LOCK")
EOF
  rm -rf "$tmp"
  [ "$n" -ge 2 ] || { [ -n "$quiet" ] || echo "  락에 슬라이스가 ${n}개뿐입니다 (universal 이 아닙니다)"; return 1; }

  got=$(sha_of "$LIC")
  if [ "$got" != "$LIC_SHA" ]; then
    [ -n "$quiet" ] || echo "  라이선스 파일이 락과 다릅니다 ($LIC)"
    return 1
  fi
  return 0
}

if [ "$MODE" = "--check" ]; then
  if verify; then
    echo "✅ 번들 jq 가 락과 맞습니다 — $VERSION ($(lipo -archs "$BIN"))"
    exit 0
  fi
  echo "❌ 번들 jq 가 락과 어긋납니다 — ./scripts/fetch-jq.sh 로 다시 만드세요" >&2
  exit 1
fi

# ⚠️ 이미 맞으면 네트워크를 쓰지 않는다.
if verify quiet; then
  echo "✅ 번들 jq 가 이미 락과 맞습니다 — $VERSION (네트워크 사용 안 함)"
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "❌ curl 이 필요합니다"

echo "▶ jq $VERSION 을 받습니다 — $BASE"
TMP=$(mktemp -d) || die "❌ 임시 디렉터리를 만들 수 없습니다"
trap 'rm -rf "$TMP"' EXIT

FILES=""
while IFS=' ' read -r arch asset want; do
  [ -n "$arch" ] || continue
  curl -fsSL --max-time 120 -o "$TMP/$asset" "$BASE/$asset" \
    || die "❌ 받지 못했습니다: $asset"
  got=$(sha_of "$TMP/$asset")
  # ⚠️ 여기서 세운다. 해시가 다른 바이너리를 사용자에게 배포하지 않는다.
  [ "$got" = "$want" ] || die "$(printf '❌ %s 의 sha256 이 락과 다릅니다\n   락:   %s\n   실제: %s' "$asset" "$want" "$got")"
  echo "  ✓ $asset  ($arch)"
  FILES="$FILES $TMP/$asset"
done <<EOF
$(jq -r '.slices[] | "\(.arch) \(.asset) \(.sha256)"' "$LOCK")
EOF

curl -fsSL --max-time 60 -o "$TMP/COPYING" "$LIC_URL" || die "❌ 라이선스를 받지 못했습니다"
got=$(sha_of "$TMP/COPYING")
[ "$got" = "$LIC_SHA" ] || die "$(printf '❌ COPYING 의 sha256 이 락과 다릅니다\n   락:   %s\n   실제: %s' "$LIC_SHA" "$got")"
echo "  ✓ COPYING  (라이선스 원본)"

mkdir -p "$OUTDIR" || die "❌ $OUTDIR 를 만들 수 없습니다"
# shellcheck disable=SC2086
lipo -create -output "$BIN" $FILES || die "❌ universal 로 합치지 못했습니다"
chmod +x "$BIN"
cp "$TMP/COPYING" "$LIC" || die "❌ 라이선스를 복사하지 못했습니다"

# ⚠️ 합친 결과를 **다시 확인한다.** 합쳤다는 것과 맞게 합쳐졌다는 것은 다르다.
verify || die "❌ 합친 결과가 락과 맞지 않습니다"

# ⚠️ 그리고 **실제로 돌려 본다.** 해시가 맞아도 못 돌 수 있다.
ACTUAL=$("$BIN" --version 2>/dev/null) || die "❌ 합친 jq 가 실행되지 않습니다"
[ "$ACTUAL" = "$VERSION" ] || die "❌ jq 가 $ACTUAL 라고 답합니다 (락: $VERSION)"

echo "✅ $BIN — $VERSION ($(lipo -archs "$BIN"))"
echo "   라이선스: $LIC"
