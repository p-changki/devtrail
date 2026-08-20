#!/usr/bin/env bash
# devtrail augment — 없는 것만 만든다(멱등).
#
# 빈 볼트에서는 전체 스캐폴딩이 되고, 기존 볼트에서는 없는 것만 채운다.
# 신규/기존을 분기하지 않고 같은 코드로 처리하는 것이 설계의 핵심이라
# 그 두 경로를 다 확인한다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"

# ── dry-run 이 기본 ──────────────────────────────────────────────────────────
t_start "dry-run 이 기본값"
t_vault dryrun
t_config notes

out=$("$DT" augment devlog 2>&1)
t_contains "생성 예정이라고 말한다" "생성 예정" "$out"
t_contains "적용 방법을 안내한다" "--apply" "$out"
t_no_file "실제로는 만들지 않는다" "$T_VAULT/notes/개발/개발일지/_index.md"

# ── 실제 생성 ────────────────────────────────────────────────────────────────
t_start "--apply 로 생성"
t_vault apply
t_config notes

"$DT" augment devlog --apply >/dev/null 2>&1
t_dir "폴더" "$T_VAULT/notes/개발/개발일지"
t_dir "하위 폴더" "$T_VAULT/notes/개발/개발메모/Frontend"
t_file "L3 허브" "$T_VAULT/notes/개발/개발일지/_index.md"
t_file "경로 맵" "$T_VAULT/notes/템플릿/_devtrail-paths.md"
t_file "L1 대시보드" "$T_VAULT/notes/대시보드.md"
t_file "가이드" "$T_VAULT/notes/가이드/1. 시작하기.md"

# ── 멱등성 — 리팩터가 깨뜨리기 가장 쉬운 계약 ────────────────────────────────
t_start "재실행이 멱등"
before=$(find "$T_VAULT" -type f | wc -l | tr -d ' ')
out=$("$DT" augment devlog --apply 2>&1)
after=$(find "$T_VAULT" -type f | wc -l | tr -d ' ')

t_eq "파일 수가 그대로" "$before" "$after"
t_contains "0개 생성이라고 말한다" "0개 생성" "$out"

# 사용자가 고친 허브를 덮어쓰지 않는다
printf '# 내가 고친 허브\n' > "$T_VAULT/notes/개발/개발일지/_index.md"
"$DT" augment devlog --apply >/dev/null 2>&1
t_eq "사용자 수정을 보존" \
  "# 내가 고친 허브" "$(head -1 "$T_VAULT/notes/개발/개발일지/_index.md")"

# ── 모듈 필터 ────────────────────────────────────────────────────────────────
t_start "모듈 단위 설치"
t_vault modules
t_config notes

"$DT" augment devlog --apply >/dev/null 2>&1
t_dir "devlog 모듈은 생성" "$T_VAULT/notes/개발/개발일지"
if [ -d "$T_VAULT/notes/자료실/00_Inbox" ]; then
  _t_bad "pkm 모듈은 건너뛴다" "고르지 않은 모듈이 생성됨"
else
  _t_ok "pkm 모듈은 건너뛴다"
fi

"$DT" augment pkm --apply >/dev/null 2>&1
t_dir "나중에 추가할 수 있다" "$T_VAULT/notes/자료실/00_Inbox"

t_exit "알 수 없는 모듈은 거부" 1 "$DT" augment nosuchmodule --apply

# ── config 매핑을 존중한다 (「얹기」) ────────────────────────────────────────
t_start "기존 폴더를 그대로 쓴다"
t_vault adopt 5
t_config "" '.dirs.devlog = "Daily"'

out=$("$DT" augment devlog --apply 2>&1)
t_contains "매핑된 폴더는 유지" "유지  Daily" "$out"
t_file "매핑된 폴더에 허브 생성" "$T_VAULT/Daily/_index.md"
t_eq "기존 노트 무손상" "5" "$(find "$T_VAULT/Daily" -name '2026-*.md' | wc -l | tr -d ' ')"

if [ -d "$T_VAULT/개발/개발일지" ]; then
  _t_bad "평행 구조를 만들지 않는다" "기본 경로에도 폴더가 생김"
else
  _t_ok "평행 구조를 만들지 않는다"
fi

# ── 허브 쿼리가 커버리지를 따른다 ────────────────────────────────────────────
t_start "허브 쿼리 선택"
hub="$T_VAULT/Daily/_index.md"
t_contains "폴더 경로가 주입됨" 'FROM "Daily"' "$(cat "$hub")"
t_contains "근사치임을 밝힌다" "근사" "$(cat "$hub")"
t_not_contains "경로 하드코딩 없음" "창기/" "$(cat "$hub")"

# ── 경로 맵 ──────────────────────────────────────────────────────────────────
t_start "경로 맵"
t_vault pathmap
t_config notes '.github.project_groups = {"demo":"demo"}'
"$DT" augment devlog --apply >/dev/null 2>&1

map="$T_VAULT/notes/템플릿/_devtrail-paths.md"
json=$(sed -n '/```json/,/```/p' "$map" | sed '1d;$d')
printf '%s' "$json" > "$T_TMP/map.json"
t_json "코드블록이 유효한 JSON" "$T_TMP/map.json"
t_eq "루트를 담는다" "notes" "$(jq -r '.root' "$T_TMP/map.json")"
t_eq "경로를 담는다" "notes/개발/개발일지" "$(jq -r '.paths.devlog' "$T_TMP/map.json")"
t_eq "프로젝트 목록을 담는다" "demo" "$(jq -r '.projects[0]' "$T_TMP/map.json")"
t_eq "카테고리를 담는다" "6" "$(jq '.categories | length' "$T_TMP/map.json")"

t_end
