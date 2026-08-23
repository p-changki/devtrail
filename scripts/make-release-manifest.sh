#!/usr/bin/env bash
# 릴리즈 매니페스트를 만든다 — 무엇이 함께 나가는지 한 파일에 적는다.
#
# ⚠️ 왜 필요한가 (ADR 0006 M6)
#
#    DMG 하나에 앱 · 헬퍼 · 번들 jq · 플러그인 · 템플릿 · 설정 스키마가
#    함께 들어간다. 이것들이 **따로 움직이면** 사용자 볼트가 조용히
#    어긋난다 — 앱이 설정 스키마 v3 를 쓰는데 템플릿이 v4 를 가정하는 식.
#
#    "문서에 적어두자" 로는 안 된다. 이 저장소는 dirs.devlog 기본값을 네
#    곳에 두고 같은 결함을 네 번 고쳤다. 게이트가 소비하는 파일이어야 한다.
#
# ⚠️ 이 파일은 **빌드 산출물**이다. 손으로 고치지 않는다 — 고치면
#    scripts/verify-local.sh --release 가 잡는다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

OUT="${1:-$ROOT/release.json}"

die() { printf '%s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq 가 필요합니다"

VERSION=$(tr -d ' \n' < VERSION) || die "VERSION 을 읽을 수 없습니다"
[ -n "$VERSION" ] || die "VERSION 이 비어 있습니다"

PLUGIN_VER=$(jq -r '.version' plugin/manifest.json 2>/dev/null) \
  || die "plugin/manifest.json 을 읽을 수 없습니다"
PLUGIN_ID=$(jq -r '.id' plugin/manifest.json 2>/dev/null)

# ⚠️ 스키마 버전의 정본은 lib/migrate.sh 하나다. 여기서 다시 적지 않는다.
SCHEMA=$(grep -E '^DT_SCHEMA=' lib/migrate.sh | head -1 | cut -d= -f2)
case "$SCHEMA" in ''|*[!0-9]*) die "DT_SCHEMA 를 읽을 수 없습니다" ;; esac

# ⚠️ 최소 macOS 는 Package.swift 가 정본이다 (D1: macOS 14).
MIN_MACOS=$(grep -oE 'macOS\(\.v([0-9]+)\)' app/Package.swift | grep -oE '[0-9]+' | head -1)
[ -n "$MIN_MACOS" ] || die "Package.swift 에서 최소 macOS 를 읽을 수 없습니다"

# ── 함께 나가는 파일 ─────────────────────────────────────────────────────────
#
# ⚠️ 플러그인 파일 목록의 정본은 plugin/files.json 이다. 여기서 다시
#    적으면 두 벌이 된다 — ADR 0006 이 세운 계약이다.
plugin_files() {
  jq -r '.files[]' plugin/files.json 2>/dev/null
}

hash_of() {   # hash_of <경로>
  [ -f "$1" ] || return 1
  shasum -a 256 "$1" | cut -d' ' -f1
}

# 배포물 목록을 (경로, sha256, 크기) 로 만든다.
artifacts_json() {
  local first=1
  printf '['
  local f h sz
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    h=$(hash_of "plugin/$f") || {
      printf ']'
      return 1
    }
    sz=$(wc -c < "plugin/$f" | tr -d ' ')
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"path":"plugin/%s","sha256":"%s","size":%s}' "$f" "$h" "$sz"
  done <<EOF
$(plugin_files)
EOF
  printf ']'
}

ARTS=$(artifacts_json) || die "플러그인 파일 중 없는 것이 있습니다 (files.json 과 실제가 다릅니다)"

jq -n \
  --arg version "$VERSION" \
  --arg plugin_id "$PLUGIN_ID" \
  --arg plugin_version "$PLUGIN_VER" \
  --argjson config_schema "$SCHEMA" \
  --arg min_macos "$MIN_MACOS" \
  --argjson artifacts "$ARTS" \
  '{
     schema: 1,
     _why: "DevTrail 한 릴리즈에 함께 나가는 것들의 단일 정본. 손으로 고치지 않는다 — scripts/make-release-manifest.sh 가 만든다.",
     version: $version,
     app: { bundle_version: $version, min_macos: $min_macos },
     plugin: { id: $plugin_id, version: $plugin_version },
     config_schema: $config_schema,
     artifacts: $artifacts
   }' > "$OUT" || die "매니페스트를 쓰지 못했습니다: $OUT"

printf '릴리즈 매니페스트: %s\n' "$OUT"
printf '  version %s · plugin %s · schema v%s · min macOS %s · 파일 %s개\n' \
  "$VERSION" "$PLUGIN_VER" "$SCHEMA" "$MIN_MACOS" \
  "$(printf '%s' "$ARTS" | jq 'length')"
