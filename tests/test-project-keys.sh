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

t_end
