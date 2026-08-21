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

# ── 템플릿 v2 — 섹션으로 제목을 합친다 ──────────────────────────────────────
t_start "템플릿 v2 — 헬퍼"
for f in preset/templates/ko/_lib.js.txt preset/templates/en/_lib.js.txt; do
  t_contains "$(basename "$(dirname "$f")") 버전 표시" "v2" "$(cat "$f")"
  t_contains "$(basename "$(dirname "$f")") dtSection"  "dtSection"  "$(cat "$f")"
  t_contains "$(basename "$(dirname "$f")") dtSections" "dtSections" "$(cat "$f")"
  t_contains "$(basename "$(dirname "$f")") dtKeysOf"   "dtKeysOf"   "$(cat "$f")"
done

t_start "개발일지가 섹션으로 묶는다"
for f in "preset/templates/ko/개발일지양식.md" "preset/templates/en/Devlog.md"; do
  n=$(basename "$f")
  t_contains "$n — 섹션으로 제목"   "dtSections(picked)" "$(cat "$f")"
  t_contains "$n — 키로 링크"       "dtKeysOf"           "$(cat "$f")"
  t_contains "$n — frontmatter 키"  "projects: <% projectList %>" "$(cat "$f")"
  t_contains "$n — project 태그"    "project/" "$(cat "$f")"
  t_not_contains "$n — 옛 방식 아님" 'picked.map(p => `#### ${p}' "$(cat "$f")"
done

# 인라인 헤더가 원본과 동기화돼 있어야 한다 — 안 그러면 설치 직후가 구버전이 된다
t_start "인라인 헤더 동기화"
# ⚠️ 파일명에 공백이 있다("Dev note.md"). ls | xargs 는 쪼갠다 — grep -l 을 직접 쓴다.
for lang in ko en; do
  want=$(grep -lE 'DevTrail (공통 헬퍼|shared helpers)' preset/templates/$lang/*.md | wc -l | tr -d ' ')
  got=$(grep -lE '(공통 헬퍼|shared helpers) v2' preset/templates/$lang/*.md | wc -l | tr -d ' ')
  t_eq "$lang — 전부 v2" "$want" "$got"
done

# ── devtrail template ────────────────────────────────────────────────────────
t_start "template list — 신규 설치는 최신"
t_vault tpl2
t_config MyVault
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1
"$DT" obsidian >/dev/null 2>&1
t_contains "최신이라고 말한다" "v2" "$("$DT" template list 2>&1)"

t_start "template — 구버전 감지"
TPL="$T_VAULT/MyVault/템플릿/개발일지양식.md"
printf '%s\n' "$(sed 's/공통 헬퍼 v2/공통 헬퍼/' "$TPL")" > "$TPL"
printf '\n## 내가 고친 것\n' >> "$TPL"

out=$("$DT" template list 2>&1)
t_contains "구버전이라고 말한다" "개발일지양식.md" "$out"
t_contains "obsidian 도 알린다" "구버전" "$("$DT" obsidian 2>&1)"

# ⚠️ 덮어쓰지 않는다. dry-run 이 기본이다.
t_start "template update — 안전 계약"
before=$(cat "$TPL")
"$DT" template update 개발일지양식.md >/dev/null 2>&1
t_eq "dry-run 은 안 바꾼다" "$before" "$(cat "$TPL")"

"$DT" template update 개발일지양식.md --apply >/dev/null 2>&1
t_contains "교체됨 (v2)" "v2" "$(cat "$TPL")"
t_not_contains "사용자 수정은 사라진다" "내가 고친 것" "$(cat "$TPL")"

# 저널에 남아 되돌아간다 — 사용자 수정을 잃지 않는 마지막 보루
job=$(ls -1 "$DEVTRAIL_HOME/journal" | tail -1)
"$DT" undo "$job" --apply >/dev/null 2>&1
t_contains "undo 로 복구된다" "내가 고친 것" "$(cat "$TPL")"

# ── worklog — AI 없이도 만들 수 있다 ────────────────────────────────────────
#
# 지금까지 worklog 작성 규칙은 AI 스킬에만 있었다. "AI 없이도 동일하게
# 쓸 수 있다"는 제품 철학과 어긋났다.
t_start "worklog 템플릿"
for f in "preset/templates/ko/워크로그 템플릿.md" "preset/templates/en/Worklog.md"; do
  n=$(basename "$f")
  t_file "$n 존재" "$f"
  t_contains "$n — 프로젝트 목록을 조회" "dtProjects()"  "$(cat "$f")"
  t_contains "$n — 작업 하나 = 폴더 하나" "worklogs/"     "$(cat "$f")"
  t_contains "$n — 프로젝트 태그"        "project/"      "$(cat "$f")"
  t_contains "$n — 프로젝트 README 링크" "/README|"      "$(cat "$f")"
  # 볼트 밖에 쓰지 않는다
  t_not_contains "$n — 볼트 밖 경로 없음" "Desktop/worklogs" \
    "$(grep -v '⚠️\|used to\|예전' "$f")"
done

t_start "worklog 단축키"
t_contains "tmpl.json 에 등록" "워크로그 템플릿.md" "$(cat preset/obsidian/hotkeys.tmpl.json)"
t_contains "영어 이름도"       "Worklog.md"         "$(cat preset/obsidian/hotkeys.tmpl.json)"
t_not_contains "fallback 에서 뺐다" '"W"' \
  "$(jq -c '.fallback_keys' preset/obsidian/hotkeys.tmpl.json)"

t_start "worklog 설치"
t_vault wl
t_config MyVault
mkdir -p "$T_VAULT/.obsidian"
"$DT" augment --apply >/dev/null 2>&1
"$DT" obsidian >/dev/null 2>&1
t_file "템플릿 설치됨" "$T_VAULT/MyVault/템플릿/워크로그 템플릿.md"
t_contains "단축키 배정됨" "워크로그" \
  "$(jq -r 'keys[]' "$T_VAULT/.obsidian/hotkeys.json" | grep 워크로그 || echo '')"

# 문서가 AI 없는 경로를 안내해야 한다
t_start "문서가 ⌘⇧W 를 안내한다"
t_contains "가이드(ko)"  '⌘⇧W' "$(cat 'preset/guides/ko/3. 단축키.md')"
t_contains "가이드(en)"  '⌘⇧W' "$(cat 'preset/guides/en/3. Hotkeys.md')"
t_contains "스킬(ko)"    '⌘⇧W' "$(cat skills/ko/worklog/SKILL.md)"
t_contains "스킬(en)"    '⌘⇧W' "$(cat skills/en/worklog/SKILL.md)"

# ── 프로젝트 허브 — 볼트 전체에서 이 프로젝트를 모은다 ─────────────────────
#
# 예전에는 자기 폴더 안(docs·worklogs)만 봤다. 그래서 "이 프로젝트의 지난
# 작업·설계안·트러블슈팅"을 한 번에 볼 수 없었다.
t_start "프로젝트 허브"
for f in "preset/templates/ko/프로젝트 생성 템플릿.md" "preset/templates/en/New project.md"; do
  n=$(basename "$f"); c=$(cat "$f")
  t_contains "$n — 개발일지"     'WHERE type = "devlog"'     "$c"
  t_contains "$n — 메모·트러블"  'type != "devlog"'          "$c"
  t_contains "$n — 레포 문서"    '${repodocs}/${name}'       "$c"
  t_contains "$n — 재방문"       'review_at <= date(today)'  "$c"
  # 태그로 모은다 — 폴더가 아니라
  t_contains "$n — 태그로 모음"  'FROM #project/${name}'     "$c"
done

# 허브가 찾는 태그를 실제로 붙이는 템플릿들
t_start "허브가 찾는 태그를 붙인다"
for t in "개발일지양식.md" "워크로그 템플릿.md" "개발메모 템플릿.md" \
         "docs 문서 템플릿.md" "트러블슈팅 템플릿.md"; do
  t_contains "$t" "project/" "$(cat "preset/templates/ko/$t")"
done
for t in "Devlog.md" "Worklog.md" "Dev note.md" "Project doc.md" "Troubleshooting.md"; do
  t_contains "$t" "project/" "$(cat "preset/templates/en/$t")"
done

# 트러블슈팅은 프로젝트를 고를 수 있어야 한다 — 안 그러면 태그가 안 붙는다
t_start "트러블슈팅이 프로젝트를 묻는다"
for f in "preset/templates/ko/트러블슈팅 템플릿.md" "preset/templates/en/Troubleshooting.md"; do
  n=$(basename "$f"); c=$(cat "$f")
  t_contains "$n — 선택창"       "dtProjects()"            "$c"
  # ⚠️ 정의만 보면 안 된다. frontmatter 에서 '쓰는지'까지 봐야
  #    태그가 실제로 붙는다. (변이 주입으로 확인했다)
  t_contains "$n — 태그 조립"    "const projectTag"        "$c"
  t_contains "$n — 태그 삽입"    "<% projectTag %>"        "$c"
  t_contains "$n — frontmatter"  "project: <% project %>"  "$c"
  t_contains "$n — 헬퍼 v2"      "v2"                      "$c"
done

# ── app uninstall — 설치했으면 지울 수도 있어야 한다 ────────────────────────
#
# devtrail uninstall 은 자동화(plist)만 지우고 앱은 남겼다.
# 남의 /Applications 에 우리 것을 두고 나가는 셈이었다.
t_start "app uninstall"
t_contains "라우터에 있다"   "uninstall) shift" "$(cat lib/appcmd.sh)"
t_contains "사용법에 있다"   "build|uninstall"  "$(cat lib/appcmd.sh)"
t_contains "dry-run 이 기본" 'apply=0'          "$(cat lib/appcmd.sh)"
t_contains "볼트를 안 건드린다고 밝힌다" "볼트와 설정은 건드리지 않습니다" \
  "$(cat lib/appcmd.sh)"

# 설치되지 않았을 때 죽지 않는다
out=$(DEVTRAIL_HOME="$T_TMP/nohome" DEVTRAIL_CONFIG="$T_TMP/nohome/c.json" \
      sh -c 'mkdir -p "$DEVTRAIL_HOME"; printf "{\"version\":3,\"lang\":\"ko\",\"vault\":{\"path\":\"/tmp\",\"root\":\"x\"},\"install\":{\"mode\":\"new\",\"modules\":[\"devlog\"]},\"dirs\":{}}" > "$DEVTRAIL_CONFIG"' 2>/dev/null; \
      echo ok)
t_eq "설정 준비" "ok" "$out"

# 문서가 새 명령을 안내한다
t_start "app uninstall 문서"
t_contains "README(ko)" "app uninstall" "$(cat README.md)"
t_contains "README(en)" "app uninstall" "$(cat README.en.md)"

t_end
