#!/usr/bin/env bash
# 한국어 · 영어 양쪽.
#
# 핵심 계약: 언어는 '표시'만 바꾼다. key 와 tag 는 바뀌지 않는다.
# 이게 깨지면 언어를 바꾼 사용자의 자동 분류가 통째로 죽는다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT
DT="$ROOT/bin/devtrail"
unset DEVTRAIL_LANG DEVTRAIL_JOURNAL

# ── 로케일에서 제안값 ────────────────────────────────────────────────────────
t_start "로케일 감지"
_l() { LANG="$1" LC_ALL="" DEVTRAIL_LANG="" bash -c \
       'DEVTRAIL_ROOT="'"$ROOT"'"; . lib/i18n.sh; dt_lang_from_locale'; }
t_eq "한국어 로케일" "ko" "$(_l ko_KR.UTF-8)"
t_eq "영어 로케일"   "en" "$(_l en_US.UTF-8)"
t_eq "그 밖의 로케일" "en" "$(_l de_DE.UTF-8)"
t_eq "로케일 없음은 기본값" "ko" "$(_l '')"

# ── 경로 ─────────────────────────────────────────────────────────────────────
t_start "경로 — 언어별"
t_vault i18n
t_config MyVault

t_eq "ko devlog" "MyVault/개발/개발일지" "$("$DT" path devlog --rel)"
t_eq "en devlog" "MyVault/Dev/Devlog"   "$(DEVTRAIL_LANG=en "$DT" path devlog --rel)"
t_eq "en 하위 폴더" "MyVault/Dev/Notes/Frontend" \
  "$(DEVTRAIL_LANG=en "$DT" path devnote.frontend --rel)"
# 이미 영어인 폴더는 번역을 두지 않았다 — path 로 떨어져야 한다
t_eq "번역 없으면 원본" "MyVault/Dev/Notes/Frontend" \
  "$(DEVTRAIL_LANG=en "$DT" path devnote.frontend --rel)"

# ── key 는 언어와 무관하다 (핵심 계약) ───────────────────────────────────────
t_start "key 는 안 바뀐다"
ko_keys=$("$DT" path --json | jq -r 'keys|sort|join(",")')
en_keys=$(DEVTRAIL_LANG=en "$DT" path --json | jq -r 'keys|sort|join(",")')
t_eq "키 집합이 동일" "$ko_keys" "$en_keys"
t_ne "경로는 다르다" \
  "$("$DT" path --json | jq -r '.devlog.rel')" \
  "$(DEVTRAIL_LANG=en "$DT" path --json | jq -r '.devlog.rel')"

# ── tag 는 언어와 무관하다 ───────────────────────────────────────────────────
t_start "tag 는 안 바뀐다"
t_eq "태그에 한글이 없다" "0" \
  "$(jq -r '[.folders[].tag//empty, ((.folders[].children//[])[].tag//empty)]|.[]' \
     preset/tree.json | grep -c '[가-힣]')"

# ── augment: 영어 볼트에 한국어 폴더가 섞이면 안 된다 ────────────────────────
# _aug_folders 가 tree.json 의 .path 만 읽어 양쪽이 다 생긴 적이 있다.
t_start "영어 볼트에 한국어 폴더 없음"
t_vault en1
t_config MyVault
DEVTRAIL_LANG=en "$DT" augment --apply >/dev/null 2>&1

t_eq "한글 폴더 0개" "0" \
  "$(find "$T_VAULT" -type d -name '*[가-힣]*' | wc -l | tr -d ' ')"
t_dir "영어 폴더가 생겼다" "$T_VAULT/MyVault/Dev/Devlog"
t_no_file "한국어 폴더가 없다" "$T_VAULT/MyVault/개발"

t_start "한국어 볼트에 영어 폴더 없음"
t_vault ko1
t_config MyVault
"$DT" augment --apply >/dev/null 2>&1
t_dir "한국어 폴더가 생겼다" "$T_VAULT/MyVault/개발/개발일지"
t_no_file "영어 폴더가 없다" "$T_VAULT/MyVault/Dev"

# ── 허브 본문 ────────────────────────────────────────────────────────────────
t_start "허브 본문 언어"
_hub() {
  DEVTRAIL_LANG="$1" DT_HUB_KEY=devlog DT_HUB_REL=x DT_HUB_FROM="V/x" \
  DT_HUB_TITLE=Devlog DT_HUB_COV_STATUS=0 DT_HUB_COV_REVIEW=0 \
  DT_HUB_DATE=2026-01-01 python3 lib/gen/hub.py
}
t_contains "ko 제목"   "## 최근"   "$(_hub ko)"
t_contains "en 제목"   "## Recent" "$(_hub en)"
t_contains "en 컬럼"   'AS "Note"' "$(_hub en)"
t_not_contains "en 에 한글 없음" "최근" "$(_hub en)"
# frontmatter 의 키는 언어와 무관해야 한다 — Dataview 가 이걸로 동작한다
t_contains "ko frontmatter 키" "devtrail_key: devlog" "$(_hub ko)"
t_contains "en frontmatter 키" "devtrail_key: devlog" "$(_hub en)"
t_contains "en 태그도 그대로" "type/moc" "$(_hub en)"

# ── 없는 언어는 기본값으로 ───────────────────────────────────────────────────
t_start "알 수 없는 언어"
t_vault fallback
t_config MyVault
t_eq "ja 는 ko 로 떨어진다" "MyVault/개발/개발일지" \
  "$(DEVTRAIL_LANG=ja "$DT" path devlog --rel)"

t_end
