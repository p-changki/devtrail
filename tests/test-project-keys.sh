#!/usr/bin/env bash
# project_groups 의 두 얼굴.
#
#   "my-app": "myapp"    실제 프로젝트   → 태그·폴더·라우팅·선택창
#   "acme-*": "acme"     PR 섹션 매칭 규칙 → summary.sh 만
#
# 거르지 않으면 #project/acme-* → 프로젝트/acme-* 라우팅 규칙이 생긴다.
# Obsidian 태그에 * 를 쓸 수 없으므로 영원히 매치되지 않는 죽은 규칙이고,
# 선택창에도 'acme-*' 가 항목으로 뜬다.
#
# ADR 0001 D1a.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT
DT="$ROOT/bin/devtrail"

# 섹션 매핑 — summary.sh.tmpl 과 같은 jq 표현식
_section() {
  jq -r --arg r "$2" '
    (.github.project_groups // {}) as $g
    | ($g[$r]
       // ($g | to_entries
             | map(. as $e | select($e.key | endswith("*"))
                   | select($r | startswith($e.key[:-1]))
                   | $e.value) | first)
       // $r)' "$1"
}

# 라우팅 규칙에서 project/* 태그만 뽑는다
_routes() {
  python3 lib/gen/anm.py preset/tree.json "$1" preset/profiles/new.json 2>/dev/null \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d.get("folder_tag_pattern", []):
    t = r.get("tag", "")
    if t.startswith("#project/"):
        print(t)
'
}

# ── wildcard 는 라우팅 규칙이 되지 않는다 ────────────────────────────────────
t_start "wildcard 는 라우팅 규칙이 아니다"
t_vault wc
t_config MyVault '.github.project_groups = {"my-app":"myapp","acme-*":"acme"}'

routes=$(_routes "$T_CONFIG")
t_contains "실제 프로젝트는 규칙이 있다" "#project/my-app" "$routes"
t_not_contains "wildcard 는 규칙이 없다"  "acme-*"          "$routes"
t_eq "규칙은 하나뿐" "1" "$(printf '%s\n' "$routes" | grep -c . | tr -d ' ')"

# ── wildcard 는 선택창에 뜨지 않는다 ─────────────────────────────────────────
t_start "wildcard 는 선택창에 없다"
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1
pmap="$T_VAULT/MyVault/템플릿/_devtrail-paths.md"
t_file "경로 맵이 있다" "$pmap"

projects=$(sed -n '/```json/,/```/p' "$pmap" | sed '1d;$d' | jq -c '.projects')
t_contains "실제 프로젝트는 있다" "my-app" "$projects"
t_not_contains "wildcard 는 없다"  "acme-*" "$projects"

# ── summary 는 wildcard 를 계속 쓴다 ─────────────────────────────────────────
#
# 이게 이 수정의 핵심이다. 설정은 그대로 두고 읽는 쪽에서만 거르므로,
# 사용자의 acme-* 는 PR 요약에서 계속 동작해야 한다.
t_start "summary 는 wildcard 를 유지한다"
t_eq "접두사 일치 (fe)" "acme"  "$(_section "$T_CONFIG" acme-frontend)"
t_eq "접두사 일치 (be)" "acme"  "$(_section "$T_CONFIG" acme-backend)"
t_eq "정확 일치"        "myapp" "$(_section "$T_CONFIG" my-app)"
t_eq "매핑 없으면 그대로" "other" "$(_section "$T_CONFIG" other)"

# ── wildcard 가 없는 설정은 아무것도 달라지지 않는다 ─────────────────────────
#
# 대부분의 사용자가 여기 해당한다. init 은 항등 매핑을 만든다.
t_start "wildcard 없는 설정은 그대로"
t_vault plain
t_config MyVault '.github.project_groups = {"my-app":"my-app","other":"other"}'
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1

projects=$(sed -n '/```json/,/```/p' "$T_VAULT/MyVault/템플릿/_devtrail-paths.md" \
           | sed '1d;$d' | jq -c '.projects')
t_eq "둘 다 남는다" '["my-app","other"]' "$projects"
t_eq "라우팅도 둘" "2" "$(_routes "$T_CONFIG" | grep -c . | tr -d ' ')"

# ── 파일명에 못 쓰는 문자도 거른다 ───────────────────────────────────────────
# 태그와 폴더 이름이 되므로 * 말고도 위험한 문자가 있다.
t_start "위험한 문자를 거른다"
t_vault bad
t_config MyVault '.github.project_groups = {"ok":"ok","a/b":"x","c:d":"y","e?f":"z"}'
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1

projects=$(sed -n '/```json/,/```/p' "$T_VAULT/MyVault/템플릿/_devtrail-paths.md" \
           | sed '1d;$d' | jq -c '.projects')
t_eq "안전한 것만 남는다" '["ok"]' "$projects"
t_eq "라우팅도 하나" "1" "$(_routes "$T_CONFIG" | grep -c . | tr -d ' ')"

# ── 경로 맵이 키와 섹션을 함께 내려보낸다 ───────────────────────────────────
#
# ⚠️ projects 는 문자열 배열로 유지한다. 헬퍼는 템플릿 안에 복사돼 있어서
#    옛 템플릿은 새 포맷을 흡수할 코드가 없다. 객체 배열로 바꾸면 태그와
#    파일명이 "[object Object]" 로 오염된다.  ADR 0001 D7.
t_start "경로 맵 — projects · project_sections"
t_vault sect
t_config MyVault '.github.project_groups = {"acme-fe":"acme","acme-be":"acme","myapp":"myapp","acme-*":"acme"}'
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1

pm="$T_VAULT/MyVault/템플릿/_devtrail-paths.md"
json=$(sed -n '/```json/,/```/p' "$pm" | sed '1d;$d')

t_eq "projects 는 문자열 배열" "string" \
  "$(printf '%s' "$json" | jq -r '.projects[0] | type')"
t_eq "wildcard 는 projects 에 없다" "false" \
  "$(printf '%s' "$json" | jq -c '.projects | index("acme-*") != null')"
t_eq "wildcard 는 sections 에도 없다" "false" \
  "$(printf '%s' "$json" | jq -c '.project_sections | has("acme-*")')"

# 둘의 짝이 맞아야 한다 — 한쪽에만 있으면 소비자가 못 잇는다
t_eq "키 집합이 동일" "true" \
  "$(printf '%s' "$json" | jq -c '(.projects | sort) == (.project_sections | keys | sort)')"

t_eq "섹션 값" "acme" "$(printf '%s' "$json" | jq -r '.project_sections["acme-fe"]')"
t_eq "항등 매핑도 담긴다" "myapp" "$(printf '%s' "$json" | jq -r '.project_sections.myapp')"

# ── 옛 템플릿이 새 경로 맵을 봐도 깨지지 않는다 ─────────────────────────────
#
# 이게 D7 의 핵심이다. 옛 dtProjects 는 DT.projects 만 읽는다.
t_start "옛 템플릿 호환"
t_eq "옛 헬퍼가 받는 것은 문자열" "true" \
  "$(printf '%s' "$json" | jq -c '[.projects[] | type == "string"] | all')"
t_not_contains "object 가 섞이지 않는다" "object" \
  "$(printf '%s' "$json" | jq -r '[.projects[] | type] | join(",")')"

# ── devtrail project add ─────────────────────────────────────────────────────
t_start "project add — 등록과 골격"
t_vault pjadd
t_config MyVault
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1

# dry-run 이 기본
out=$("$DT" project add my-app 2>&1)
t_contains "dry-run 이라고 말한다" "dry-run" "$out"
t_eq "설정이 안 바뀐다" "" "$(cfg_get() { jq -r --arg k my-app '.github.project_groups[$k] // ""' "$T_CONFIG"; }; cfg_get)"
t_no_file "폴더도 안 생긴다" "$T_VAULT/MyVault/개발/프로젝트/my-app"

"$DT" project add my-app --apply >/dev/null 2>&1
t_eq "등록됨" "my-app" "$(jq -r '.github.project_groups["my-app"]' "$T_CONFIG")"
t_dir "폴더 생성" "$T_VAULT/MyVault/개발/프로젝트/my-app"
t_dir "worklogs"  "$T_VAULT/MyVault/개발/프로젝트/my-app/worklogs"

# 골격은 preset/project-skeleton.json 이 단일 출처다
want=$(jq -r '.docs | length' preset/project-skeleton.json)
got=$(find "$T_VAULT/MyVault/개발/프로젝트/my-app/docs" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
t_eq "docs 골격이 선언과 일치" "$want" "$got"

# 경로 맵이 즉시 갱신된다 — 선택창에 바로 나타나야 한다
json=$(sed -n '/```json/,/```/p' "$T_VAULT/MyVault/템플릿/_devtrail-paths.md" | sed '1d;$d')
t_contains "경로 맵에 반영" "my-app" "$(printf '%s' "$json" | jq -c '.projects')"

# ── wildcard 는 거부한다 ─────────────────────────────────────────────────────
t_start "project add — wildcard 거부"
t_exit "종료코드 1" 1 "$DT" project add 'acme-*'
out=$("$DT" project add 'acme-*' 2>&1 || true)
t_contains "대안을 안내한다" "--section" "$out"
t_eq "설정에 안 들어간다" "false" \
  "$(jq -c '.github.project_groups | has("acme-*")' "$T_CONFIG")"

# ── 그룹핑 — 각각 등록하고 같은 섹션 ─────────────────────────────────────────
t_start "project add — 그룹핑"
"$DT" project add acme-fe --section acme --apply >/dev/null 2>&1
"$DT" project add acme-be --section acme --apply >/dev/null 2>&1
t_eq "fe 섹션" "acme" "$(jq -r '.github.project_groups["acme-fe"]' "$T_CONFIG")"
t_eq "be 섹션" "acme" "$(jq -r '.github.project_groups["acme-be"]' "$T_CONFIG")"

json=$(sed -n '/```json/,/```/p' "$T_VAULT/MyVault/템플릿/_devtrail-paths.md" | sed '1d;$d')
t_eq "제목은 하나로 합쳐진다" "1" \
  "$(printf '%s' "$json" | jq -r '[.project_sections["acme-fe"], .project_sections["acme-be"]] | unique | length')"

# ── 기존 폴더를 만났을 때 (D4) ───────────────────────────────────────────────
t_start "project add — 기존 노트 무수정"
mkdir -p "$T_VAULT/MyVault/개발/프로젝트/legacy/docs/01-product"
printf '# 내 노트\n' > "$T_VAULT/MyVault/개발/프로젝트/legacy/README.md"
before=$(cat "$T_VAULT/MyVault/개발/프로젝트/legacy/README.md")

out=$("$DT" project add legacy 2>&1)
t_contains "기존 노트를 밝힌다" "건드리지 않습니다" "$out"

"$DT" project add legacy --apply >/dev/null 2>&1
t_eq "README 무수정" "$before" "$(cat "$T_VAULT/MyVault/개발/프로젝트/legacy/README.md")"
t_dir "없던 것만 보강" "$T_VAULT/MyVault/개발/프로젝트/legacy/worklogs"
t_dir "있던 것 유지"   "$T_VAULT/MyVault/개발/프로젝트/legacy/docs/01-product"

# ── 롤백 — 설정과 폴더가 함께 되돌아간다 ────────────────────────────────────
#
# 설정만 바뀌고 폴더가 없는 상태를 남기면 안 된다.  ADR 0001 D4.
t_start "project add — undo"
t_vault pjundo
t_config MyVault
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1
"$DT" project add rollme --apply >/dev/null 2>&1
job=$(ls -1 "$DEVTRAIL_HOME/journal" | tail -1)
"$DT" undo "$job" --apply >/dev/null 2>&1

t_eq "설정에서 사라진다" "false" \
  "$(jq -c '.github.project_groups | has("rollme")' "$T_CONFIG")"
t_no_file "폴더도 사라진다" "$T_VAULT/MyVault/개발/프로젝트/rollme"

t_end
