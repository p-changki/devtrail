#!/usr/bin/env bash
# devtrail path — 경로 해석 단일 창구.
#
# 여기가 깨지면 템플릿·스킬·쿼리가 전부 엉뚱한 곳을 가리킨다.
# 가장 먼저 지켜야 할 계약이다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"

# ── 기본 해석 ────────────────────────────────────────────────────────────────
t_start "tree.json 기본값"
t_vault basic
t_config notes

t_eq "루트 아래 상대경로" \
  "notes/개발/개발일지" "$("$DT" path --rel devlog)"
t_eq "하위 폴더 (점 표기)" \
  "notes/개발/개발메모/Frontend" "$("$DT" path --rel devnote.frontend)"
t_eq "절대경로는 볼트 경로로 시작" \
  "$T_VAULT/notes/개발/개발일지" "$("$DT" path devlog)"

# ── config 가 tree.json 을 이긴다 (「얹기」의 핵심) ───────────────────────────
t_start "config.dirs 우선순위"
t_vault adopt
t_config notes '.dirs.devlog = "Daily"'

t_eq "config 값이 이긴다" \
  "notes/Daily" "$("$DT" path --rel devlog)"
t_eq "매핑 안 한 키는 기본값" \
  "notes/개발/아이디어" "$("$DT" path --rel idea)"

# ── 빈 루트 (볼트 최상위에 바로 두는 사람) ───────────────────────────────────
t_start "빈 루트"
t_vault emptyroot
t_config "" '.dirs.devlog = "Daily"'

t_eq "앞 슬래시가 붙지 않는다" \
  "Daily" "$("$DT" path --rel devlog)"
t_not_contains "절대경로에 이중 슬래시가 없다" \
  "//" "$("$DT" path devlog)"

# ── 오류 처리 ────────────────────────────────────────────────────────────────
t_start "알 수 없는 키"
t_vault unknown
t_config notes

t_exit "종료코드 1" 1 "$DT" path nosuchkey
t_contains "안내 문구" "전체 목록" "$("$DT" path nosuchkey 2>&1)"

# ── 전체 목록 · JSON ─────────────────────────────────────────────────────────
t_start "목록과 JSON"
t_vault listing
t_config notes

n=$("$DT" path | wc -l | tr -d ' ')
t_ne "목록이 비지 않는다" "0" "$n"
t_eq "tree.json 정의 수와 일치" \
  "$(jq '[.folders[], (.folders[].children // [])[]] | length' "$ROOT/preset/tree.json")" "$n"

"$DT" path --json > "$T_TMP/paths.json"
t_json "유효한 JSON" "$T_TMP/paths.json"
t_eq "abs·rel 둘 다 낸다" \
  "notes/개발/개발일지" "$(jq -r '.devlog.rel' "$T_TMP/paths.json")"

t_end
