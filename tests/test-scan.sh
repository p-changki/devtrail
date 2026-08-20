#!/usr/bin/env bash
# devtrail scan — 볼트 진단. 쓰기가 없어야 한다.
#
# scan 결과가 모드 제안 · 충돌 회피 · 허브 쿼리 선택을 전부 결정한다.
# 여기가 틀리면 그 뒤가 조용히 어긋난다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"
PY="$ROOT/lib/scan.py"

# ── 쓰기가 없어야 한다 ───────────────────────────────────────────────────────
t_start "쓰기 없음"
t_vault readonly 5
t_config notes

before=$(find "$T_VAULT" -type f | wc -l | tr -d ' ')
"$DT" scan "$T_VAULT" >/dev/null 2>&1
after=$(find "$T_VAULT" -type f | wc -l | tr -d ' ')
t_eq "파일을 만들지 않는다" "$before" "$after"

# ── 빈 볼트 ──────────────────────────────────────────────────────────────────
t_start "빈 볼트"
t_vault empty
t_config notes

python3 "$PY" "$T_VAULT" > "$T_TMP/empty.json"
t_json "유효한 JSON" "$T_TMP/empty.json"
t_eq "노트 0개" "0" "$(jq -r '.scale.notes' "$T_TMP/empty.json")"
t_eq "역할 후보 없음" "0" \
  "$(jq '[.folders[]? | select(.role_candidates | length > 0)] | length' "$T_TMP/empty.json")"
t_contains "신규를 제안" "새로 시작" "$("$DT" scan "$T_VAULT" 2>&1)"

# ── 노트가 있는 볼트 ─────────────────────────────────────────────────────────
t_start "기존 볼트"
t_vault existing 15
t_config notes

python3 "$PY" "$T_VAULT" > "$T_TMP/ex.json"
t_eq "노트 수를 센다" "15" "$(jq -r '.scale.notes' "$T_TMP/ex.json")"
t_contains "기존을 제안" "기존 볼트에 얹기" "$("$DT" scan "$T_VAULT" 2>&1)"

# 날짜 파일명이 모인 폴더를 devlog 로 추론한다
t_eq "역할을 추론한다" "Daily" \
  "$(jq -r '[.folders[]? | select(.role_candidates.devlog)] | .[0].path // "없음"' "$T_TMP/ex.json")"

# ── 필드 커버리지: 키와 값을 구분한다 ────────────────────────────────────────
t_start "키와 값 구분"
t_vault fields
mkdir -p "$T_VAULT/n"
# review_at 키만 있고 값이 빈 노트 — 원본 볼트에서 232개가 이랬다
printf -- '---\ntype: note\nreview_at:\n---\n# a\n' > "$T_VAULT/n/a.md"
printf -- '---\ntype: note\nreview_at: 2026-01-01\n---\n# b\n' > "$T_VAULT/n/b.md"
t_config notes

python3 "$PY" "$T_VAULT" > "$T_TMP/f.json"
t_eq "키는 2개" "2" "$(jq -r '.fields.review_at.with_key' "$T_TMP/f.json")"
t_eq "값은 1개" "1" "$(jq -r '.fields.review_at.with_value' "$T_TMP/f.json")"

# ── YAML 다중행 리스트 ───────────────────────────────────────────────────────
# 처음에 이걸 못 읽어 태그 집계가 실제의 1% 로 나왔다.
t_start "YAML 리스트 파싱"
t_vault tags
mkdir -p "$T_VAULT/n"
printf -- '---\ntags:\n  - type/devlog\n  - project/x\n---\n# a\n' > "$T_VAULT/n/a.md"
printf -- '---\ntags: [type/idea]\n---\n# b\n' > "$T_VAULT/n/b.md"
t_config notes

python3 "$PY" "$T_VAULT" > "$T_TMP/t.json"
t_eq "다중행 리스트를 읽는다" "3" "$(jq -r '.tags.total_uses' "$T_TMP/t.json")"
t_contains "type 네임스페이스를 센다" "type/devlog" \
  "$(jq -r '[.tags.top[][0]] | join(",")' "$T_TMP/t.json")"

# ── 노이즈 폴더 제외 ─────────────────────────────────────────────────────────
# 자동 수집물·백업이 진짜 역할 폴더를 밀어내면 안 된다.
t_start "노이즈 제외"
t_vault noise
mkdir -p "$T_VAULT/Daily" "$T_VAULT/아카이브/backup"
i=1; while [ "$i" -le 8 ]; do
  printf -- '# x\n' > "$T_VAULT/Daily/2026-08-0$i.md"
  printf -- '# x\n' > "$T_VAULT/아카이브/backup/2026-07-0$i.md"
  i=$((i + 1))
done
t_config notes

python3 "$PY" "$T_VAULT" > "$T_TMP/n.json"
cands=$(jq -r '[.folders[]? | select(.role_candidates.devlog) | .path] | join(",")' "$T_TMP/n.json")
t_contains "진짜 폴더는 잡는다" "Daily" "$cands"
t_not_contains "아카이브는 뺀다" "backup" "$cands"

# ── 오류 처리 ────────────────────────────────────────────────────────────────
t_start "없는 경로"
t_exit "종료코드 1" 1 "$DT" scan "$T_TMP/nosuchvault"

t_end
