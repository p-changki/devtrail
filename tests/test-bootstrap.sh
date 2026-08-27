#!/usr/bin/env bash
# Obsidian 부트스트랩 — 볼트 레지스트리 · 플러그인 설치.
#
# 이 코드는 두 가지를 한다: 남의 Obsidian 레지스트리를 고치고, 인터넷에서
# 받은 코드를 남의 볼트에 넣는다. 둘 다 틀리면 아프다.
#
# ⚠️ 네트워크를 쓰지 않는다. 다운로드는 QA 에서 실물로 확인한다.
#    여기서는 '받은 뒤의 계약'만 검사한다 — 어디에 넣나, 무엇을 안 건드리나.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

export DEVTRAIL_ROOT="$ROOT"
unset DEVTRAIL_JOURNAL

# ⚠️ DT_JOURNAL_DIR 은 common.sh 를 '읽는 순간' DEVTRAIL_HOME 으로 굳는다.
#    나중에 바꿔도 늦다 — 실제로 이 테스트가 ~/.devtrail 에 저널을 남겼다.
#    그래서 모듈을 읽기 전에 격리한다.
export DEVTRAIL_HOME="$T_TMP/home"
export DEVTRAIL_CONFIG="$T_TMP/home/devtrail.config.json"
mkdir -p "$DEVTRAIL_HOME"

# 모듈을 직접 읽어 함수 단위로 검사한다.
_load() {
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/obsidian_app.sh"
  . "$ROOT/lib/plugins.sh"
}

# ── 고정 목록의 무결성 ───────────────────────────────────────────────────────
# 여기가 깨지면 셋업이 통째로 못 돈다.
t_start "preset/plugins.json"
PJ="$ROOT/preset/plugins.json"
t_json "유효한 JSON" "$PJ"
t_eq "id 가 전부 다르다" \
  "$(jq '[.plugins[].id] | length' "$PJ")" \
  "$(jq '[.plugins[].id] | unique | length' "$PJ")"

# ⚠️ latest 를 쫓으면 어제 되던 셋업이 오늘 깨진다. 반드시 고정 태그다.
t_eq "태그가 전부 고정" "0" \
  "$(jq '[.plugins[] | select(.tag == "latest" or .tag == "" or .tag == null)] | length' "$PJ")"

# manifest.json 이 없으면 받은 것이 무엇인지 확인할 수 없다.
t_eq "전부 manifest.json 을 받는다" "0" \
  "$(jq '[.plugins[] | select(.files | index("manifest.json") | not)] | length' "$PJ")"
t_eq "전부 main.js 를 받는다" "0" \
  "$(jq '[.plugins[] | select(.files | index("main.js") | not)] | length' "$PJ")"
t_eq "필수가 하나 이상" "true" \
  "$(jq '[.plugins[] | select(.required)] | length > 0' "$PJ")"

# ── 볼트 ID ──────────────────────────────────────────────────────────────────
t_start "볼트 ID"
(
  _load
  a=$(oa_vault_id "/tmp/vault-a")
  b=$(oa_vault_id "/tmp/vault-a")
  c=$(oa_vault_id "/tmp/vault-b")
  t_eq "같은 경로는 같은 ID" "$a" "$b"
  t_ne "다른 경로는 다른 ID" "$a" "$c"
  t_eq "16자" "16" "${#a}"
)

# ── .obsidian 생성 ───────────────────────────────────────────────────────────
# 예전에는 "Obsidian 에서 한 번 열고 오세요" 로 막았다. 그 한 줄이
# 터미널 ↔ GUI 왕복을 만들었다.
t_start ".obsidian 을 우리가 만든다"
(
  export DEVTRAIL_HOME="$T_TMP/v1-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  V="$T_TMP/v1"; mkdir -p "$V"
  jr_begin test-dot
  oa_ensure_dot "$V"
  t_dir "생겼다" "$V/.obsidian"
  t_contains "저널에 남는다" ".obsidian" "$(cat "$DEVTRAIL_HOME/journal/$DT_JOB/entries.tsv")"
  t_exit "이미 있으면 조용히 성공" 0 oa_ensure_dot "$V"
)

# ── 레지스트리 ───────────────────────────────────────────────────────────────
t_start "볼트 등록"
(
  export HOME="$T_TMP/fakehome"
  export DEVTRAIL_HOME="$T_TMP/reg-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  REG="$HOME/Library/Application Support/obsidian/obsidian.json"
  mkdir -p "$(dirname "$REG")"

  # 사용자가 이미 쓰던 볼트가 있다. 이걸 날리면 안 된다.
  mkdir -p "$T_TMP/mine" "$T_TMP/new"
  jq -n --arg p "$T_TMP/mine" \
    '{vaults: {"aaaaaaaaaaaaaaaa": {path: $p, ts: 1}}}' > "$REG"

  jr_begin test-reg
  oa_register "$T_TMP/new"
  t_eq "항목이 둘" "2" "$(jq '.vaults | length' "$REG")"
  t_contains "기존 볼트가 남아 있다" "$T_TMP/mine" "$(jq -r '.vaults[].path' "$REG")"

  # ⚠️ 두 번 등록해도 하나여야 한다. 무작위 ID 를 쓰면 실행할 때마다
  #    목록이 불어난다.
  oa_register "$T_TMP/new"
  t_eq "재등록해도 그대로" "2" "$(jq '.vaults | length' "$REG")"
)

t_start "볼트 목록"
(
  export HOME="$T_TMP/fakehome2"
  _load
  REG="$HOME/Library/Application Support/obsidian/obsidian.json"
  mkdir -p "$(dirname "$REG")" "$T_TMP/live"
  jq -n --arg live "$T_TMP/live" --arg dead "$T_TMP/deleted-vault" \
    '{vaults: {a: {path: $live, ts: 2}, b: {path: $dead, ts: 1}}}' > "$REG"
  out=$(oa_vaults)
  t_contains "있는 볼트는 나온다" "$T_TMP/live" "$out"
  # 사용자가 지운 볼트를 목록에 보여주면 고르고 나서 실패한다.
  t_not_contains "사라진 볼트는 빠진다" "deleted-vault" "$out"
)

# ── 플러그인 상태 판정 ───────────────────────────────────────────────────────
t_start "설치·활성 판정"
(
  _load
  DOT="$T_TMP/dot1"; mkdir -p "$DOT/plugins/dataview"
  t_exit "main.js 가 없으면 미설치" 1 pl_installed "$DOT" dataview
  printf 'x' > "$DOT/plugins/dataview/main.js"
  t_exit "main.js 가 있으면 설치됨" 0 pl_installed "$DOT" dataview
  t_exit "목록에 없으면 꺼짐" 1 pl_enabled "$DOT" dataview
  printf '%s' '["dataview"]' > "$DOT/community-plugins.json"
  t_exit "목록에 있으면 켜짐" 0 pl_enabled "$DOT" dataview
)

# ── 받아야 할 개수 ───────────────────────────────────────────────────────────
# ⚠️ 회귀: 예전에는 한 함수가 화면도 그리고 개수도 stdout 으로 냈다.
#    $(...) 로 받으면 화면 전체가 숫자 자리에 들어와 죽었다.
t_start "받아야 할 개수는 숫자만"
(
  _load
  DOT="$T_TMP/dot2"; mkdir -p "$DOT"
  total=$(jq '.plugins | length' "$ROOT/preset/plugins.json")
  n=$(pl_todo_count "$DOT")
  t_eq "빈 볼트면 전부" "$total" "$n"
  case "$n" in ''|*[!0-9]*) t_eq "숫자만 나온다" "숫자" "$n" ;; *) t_eq "숫자만 나온다" "$n" "$n" ;; esac

  mkdir -p "$DOT/plugins/dataview"; printf 'x' > "$DOT/plugins/dataview/main.js"
  t_eq "하나 깔면 하나 줄어든다" "$((total - 1))" "$(pl_todo_count "$DOT")"
)

# ── 활성화는 더하기다 ────────────────────────────────────────────────────────
t_start "활성화는 남의 목록을 지우지 않는다"
(
  export DEVTRAIL_HOME="$T_TMP/en-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  DOT="$T_TMP/dot3"; mkdir -p "$DOT"
  # 사용자가 이미 쓰던 플러그인들. 여기를 덮어쓰면 전부 꺼진다.
  printf '%s' '["obsidian-excalidraw-plugin","calendar"]' > "$DOT/community-plugins.json"
  jr_begin test-enable
  _pl_enable "$DOT" dataview
  out=$(cat "$DOT/community-plugins.json")
  t_contains "새 것이 들어갔다" "dataview" "$out"
  t_contains "쓰던 것 1" "excalidraw" "$out"
  t_contains "쓰던 것 2" "calendar" "$out"
  t_eq "셋이다" "3" "$(jq 'length' "$DOT/community-plugins.json")"

  _pl_enable "$DOT" dataview
  t_eq "두 번 켜도 셋" "3" "$(jq 'length' "$DOT/community-plugins.json")"
)

# ── 설치된 것은 건드리지 않는다 ──────────────────────────────────────────────
# 사용자가 최신 Templater 를 쓰고 있는데 우리가 고정 버전으로 되돌리면
# 그건 다운그레이드다 — 최악의 피해다.
t_start "이미 있는 플러그인은 건드리지 않는다"
(
  export DEVTRAIL_HOME="$T_TMP/keep-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  DOT="$T_TMP/dot4"; mkdir -p "$DOT/plugins/templater-obsidian"
  printf 'MINE-9.9.9' > "$DOT/plugins/templater-obsidian/main.js"
  before=$(cat "$DOT/plugins/templater-obsidian/main.js")

  # 네트워크를 타지 않도록 이미 설치된 것만 있는 상태로 판정만 확인한다.
  t_exit "설치됨으로 본다" 0 pl_installed "$DOT" templater-obsidian
  t_eq "내용 그대로" "$before" "$(cat "$DOT/plugins/templater-obsidian/main.js")"
)

# ── 라우터 ───────────────────────────────────────────────────────────────────
t_start "devtrail plugins"
t_contains "usage 에 있다" "devtrail plugins" "$("$ROOT/bin/devtrail" help 2>&1)"
t_contains "알 수 없는 하위 명령은 거절" "알 수 없는 하위 명령" \
  "$(DEVTRAIL_CONFIG=/dev/null "$ROOT/bin/devtrail" plugins nonsense 2>&1)"

# ── Templater 자동 삽입 스위치 ───────────────────────────────────────────────
#
# ⚠️ 회귀: Templater 2.x 는 로드할 때 예전 키를 **삭제한다**.
#      for (n of ["trigger_on_file_creation", "enable_folder_templates", ...])
#        delete i[n]
#    예전 키만 쓰면 모드가 "none" 이 되어 자동 삽입이 통째로 꺼진다.
#    2026-08-22 실물 QA 에서 확인했다 — 노트를 만들어도 양식이 안 들어왔다.
t_start "Templater 자동 삽입 스위치"
(
  export DEVTRAIL_HOME="$T_TMP/tp-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  PL="$T_TMP/tp-plugin"; mkdir -p "$PL"
  PATHS="$T_TMP/tp-paths.json"
  jq -n '{paths: {templates: "notes/템플릿", devlog: "notes/개발/개발일지"}}' > "$PATHS"

  # 1) 신버전: main.js 가 data_version 을 말한다
  printf 'var gr={data_version:2,trigger_on_file_creation_mode:"none"};' > "$PL/main.js"
  out=$(DT_TEMPLATER_DIR="$PL" python3 "$ROOT/lib/gen/hotkeys.py" templater         "$ROOT/preset/obsidian/hotkeys.tmpl.json" "$PATHS" "" 2>/dev/null)
  t_eq "모드가 folder"        "folder" "$(printf '%s' "$out" | jq -r '.trigger_on_file_creation_mode')"
  t_eq "data_version 을 따른다" "2"      "$(printf '%s' "$out" | jq -r '.data_version')"
  # 예전 키가 남으면 Templater 가 "설정을 초기화했습니다" 경고를 띄운다.
  t_eq "예전 키를 남기지 않는다" "null"  "$(printf '%s' "$out" | jq -r '.trigger_on_file_creation')"
  t_eq "예전 폴더 키도 없다"    "null"  "$(printf '%s' "$out" | jq -r '.enable_folder_templates')"

  # 2) 버전을 못 읽으면 예전 키로 떨어진다 — 구버전에서는 그게 맞는 키다.
  printf 'nothing useful here' > "$PL/main.js"
  out2=$(DT_TEMPLATER_DIR="$PL" python3 "$ROOT/lib/gen/hotkeys.py" templater          "$ROOT/preset/obsidian/hotkeys.tmpl.json" "$PATHS" "" 2>/dev/null)
  t_eq "구버전이면 예전 키" "true" "$(printf '%s' "$out2" | jq -r '.trigger_on_file_creation')"
  t_eq "폴더 템플릿도 켠다" "true" "$(printf '%s' "$out2" | jq -r '.enable_folder_templates')"
  t_eq "가짜 data_version 을 쓰지 않는다" "null" "$(printf '%s' "$out2" | jq -r '.data_version')"

  # 3) 어느 쪽이든 '꺼짐' 으로 끝나면 안 된다
  t_ne "신버전이 none 이 아니다" "none" "$(printf '%s' "$out" | jq -r '.trigger_on_file_creation_mode')"
)

# ── 단축키가 실재하는 명령을 가리키는가 ─────────────────────────────────────
#
# ⚠️ 회귀: Templater 는 enabled_templates_hotkeys 에 있는 템플릿에만
#    명령을 만든다. 그 목록을 비워둔 채 hotkeys.json 에만 키를 배정하면
#    존재하지 않는 명령에 키를 거는 셈이라 눌러도 아무 일이 없다.
#    "단축키 13개 등록" 이라고 보고하면서 실제로는 0개였다.
t_start "단축키가 실재하는 명령을 가리킨다"
(
  export DEVTRAIL_HOME="$T_TMP/hk-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  PL="$T_TMP/hk-plugin"; mkdir -p "$PL"
  printf 'var gr={data_version:2};' > "$PL/main.js"
  PATHS="$T_TMP/hk-paths.json"
  jq -n '{paths: {templates: "notes/템플릿", devlog: "notes/개발/개발일지"}}' > "$PATHS"
  SPEC="$ROOT/preset/obsidian/hotkeys.tmpl.json"
  TDIR="$ROOT/preset/templates/ko"

  data=$(DT_TEMPLATES_DIR="$TDIR" DT_TEMPLATER_DIR="$PL"          python3 "$ROOT/lib/gen/hotkeys.py" templater "$SPEC" "$PATHS" "" 2>/dev/null)
  hk=$(DT_TEMPLATES_DIR="$TDIR"        python3 "$ROOT/lib/gen/hotkeys.py" hotkeys "$SPEC" "$PATHS" "" "" 2>/dev/null)

  # hotkeys.json 이 거는 템플릿 명령 = Templater 에 등록한 템플릿
  bound=$(printf '%s' "$hk" | jq -r 'keys[] | select(startswith("templater-obsidian:create-notes/"))
                                     | sub("^templater-obsidian:create-"; "")' | sort)
  reg=$(printf '%s' "$data" | jq -r '.enabled_templates_hotkeys[]' | sort)

  t_ne "템플릿 단축키가 하나 이상" "" "$bound"
  t_eq "배정한 키 = 등록한 명령" "$bound" "$reg"

  # 사용자가 이미 넣어둔 항목을 지우면 그 사람의 단축키가 죽는다.
  prev=$(jq -n '{enabled_templates_hotkeys: ["notes/템플릿/내것.md"]}')
  PREVF="$T_TMP/hk-prev.json"; printf '%s' "$prev" > "$PREVF"
  data2=$(DT_TEMPLATES_DIR="$TDIR" DT_TEMPLATER_DIR="$PL"           python3 "$ROOT/lib/gen/hotkeys.py" templater "$SPEC" "$PATHS" "$PREVF" 2>/dev/null)
  t_contains "쓰던 항목이 남는다" "내것.md" "$(printf '%s' "$data2" | jq -r '.enabled_templates_hotkeys|join(",")')"

  # 두 번 돌려도 불어나지 않는다.
  D2F="$T_TMP/hk-d2.json"; printf '%s' "$data" > "$D2F"
  data3=$(DT_TEMPLATES_DIR="$TDIR" DT_TEMPLATER_DIR="$PL"           python3 "$ROOT/lib/gen/hotkeys.py" templater "$SPEC" "$PATHS" "$D2F" 2>/dev/null)
  t_eq "재실행해도 개수 그대로"     "$(printf '%s' "$data"  | jq '.enabled_templates_hotkeys|length')"     "$(printf '%s' "$data3" | jq '.enabled_templates_hotkeys|length')"
)

# ── 라우팅 규칙 순서 ─────────────────────────────────────────────────────────
#
# ⚠️ 회귀: Auto Note Mover 는 배열 순서대로 첫 매칭을 쓴다(for i=0..).
#    개발일지에는 type/devlog 와 project/<키> 가 함께 붙는다. project 규칙이
#    앞에 오면 개발일지가 프로젝트 폴더로 끌려간다 — 사용자 노트가
#    사라진 것처럼 보이는 사고다(2026-08-22 실물 QA 에서 실제로 발생).
#
#    원인은 병합이었다. 새 규칙만 앞에 붙이고(kept + old_rules) 이미 있던
#    우리 규칙은 뒤에 뒀기 때문에, 프로젝트를 '나중에' 등록하면 순서가 뒤집혔다.
t_start "라우팅 규칙 순서"
(
  export DEVTRAIL_HOME="$T_TMP/anm-home"; mkdir -p "$DEVTRAIL_HOME"
  _load
  CFG="$T_TMP/anm-cfg.json"
  jq -n '{version:3, lang:"ko", vault:{backend:"local", path:"/tmp/v", root:"notes"},
          dirs:{}, github:{user:"t", repos:[], project_groups:{"acme-be":"acme","my-app":"my-app"}},
          install:{mode:"new", modules:["devlog"]}}' > "$CFG"
  PROF="$ROOT/preset/profiles/new.json"

  # 1) 한 번에 만들면 순서가 맞는가
  out=$(python3 "$ROOT/lib/gen/anm.py" "$ROOT/preset/tree.json" "$CFG" "$PROF" 2>/dev/null)
  dev=$(printf '%s' "$out" | jq '[.folder_tag_pattern[].tag] | index("#type/devlog")')
  prj=$(printf '%s' "$out" | jq '[.folder_tag_pattern[].tag] | index("#project/acme-be")')
  t_ne "type/devlog 규칙이 있다"   "null" "$dev"
  t_ne "project 규칙도 있다"       "null" "$prj"
  t_eq "type/devlog 가 앞이다"     "true" "$(jq -n --argjson a "$dev" --argjson b "$prj" '$a < $b')"

  # 2) ★ 프로젝트를 '나중에' 등록해도 순서가 유지되는가 — 여기가 깨졌던 곳이다.
  NOPRJ="$T_TMP/anm-noprj.json"
  jq '.github.project_groups = {}' "$CFG" > "$NOPRJ"
  first=$(python3 "$ROOT/lib/gen/anm.py" "$ROOT/preset/tree.json" "$NOPRJ" "$PROF" 2>/dev/null)
  PREV="$T_TMP/anm-prev.json"; printf '%s' "$first" > "$PREV"
  second=$(python3 "$ROOT/lib/gen/anm.py" "$ROOT/preset/tree.json" "$CFG" "$PROF" "$PREV" 2>/dev/null)

  dev2=$(printf '%s' "$second" | jq '[.folder_tag_pattern[].tag] | index("#type/devlog")')
  prj2=$(printf '%s' "$second" | jq '[.folder_tag_pattern[].tag] | index("#project/acme-be")')
  t_ne "나중에 등록해도 project 규칙 생성" "null" "$prj2"
  t_eq "나중에 등록해도 type/devlog 가 앞" "true"     "$(jq -n --argjson a "$dev2" --argjson b "$prj2" '$a < $b')"

  # 3) 사용자가 직접 넣은 규칙은 사라지지 않는다.
  MINE="$T_TMP/anm-mine.json"
  printf '%s' "$first" | jq '.folder_tag_pattern += [{folder:"내폴더", tag:"#내태그", pattern:""}]' > "$MINE"
  third=$(python3 "$ROOT/lib/gen/anm.py" "$ROOT/preset/tree.json" "$CFG" "$PROF" "$MINE" 2>/dev/null)
  t_contains "사용자 규칙이 남는다" "내태그"     "$(printf '%s' "$third" | jq -r '[.folder_tag_pattern[].tag] | join(",")')"
)

# ── 프로젝트 허브가 단일 출처인가 ───────────────────────────────────────────
#
# ⚠️ 회귀: 프로젝트를 만드는 경로가 둘이었다.
#      Obsidian 「프로젝트 생성 템플릿」 → 폴더 + README (허브 전체)
#      devtrail project add            → 폴더만, README 없음
#    개발일지·개발메모·트러블슈팅 템플릿이 전부 <프로젝트>/README 로 링크하는데
#    CLI 로 만든 프로젝트는 그 링크가 전부 깨져 있었다(2026-08-22 실물 QA).
t_start "프로젝트 허브"
HUB_KO="$ROOT/preset/hub/project-readme.ko.md"
HUB_EN="$ROOT/preset/hub/project-readme.en.md"
t_file "허브 원본 (ko)" "$HUB_KO"
t_file "허브 원본 (en)" "$HUB_EN"

# ⚠️ 개발일지는 프로젝트 README 로 링크하지 **않는다** (2026-08-28 결정).
#
#    예전에는 `#### <섹션>` 아래에 `> [[.../README|키]]` 를 넣었다. 실물에서
#    프로젝트마다 두 줄이 되어 읽기 나빴고, DevTrail 이 만들지 않은 폴더에는
#    README 가 없어 깨진 링크가 됐다. 일지와 프로젝트는 `project/<키>` 태그가
#    잇는다 — 링크가 없어도 연결은 남는다.
#
#    ⚠️ CLI(생성·붙이기)와 템플릿이 같은 형식이어야 한다. 한쪽만 바꾸면
#       만든 경로에 따라 본문이 달라진다.
for f in "$ROOT/preset/templates/ko/개발일지양식.md" \
         "$ROOT/preset/templates/en/Devlog.md"; do
  t_not_contains "$(basename "$f") — README 링크 없음" "/README|" "$(cat "$f")"
done
t_not_contains "capture devlog 도 README 링크 없음" "/README|" "$(cat "$ROOT/lib/capturecmd.sh")"
t_not_contains "project link 도 README 링크 없음" "/README|" "$(cat "$ROOT/lib/projectcmd.sh")"

# ⚠️ 본문이 두 곳에 있으면 언젠가 어긋난다. 템플릿은 '읽어야' 한다.
for f in "$ROOT/preset/templates/ko/프로젝트 생성 템플릿.md" \
         "$ROOT/preset/templates/en/New project.md"; do
  t_contains "$(basename "$f") — 허브를 읽는다" "_devtrail-project-readme.md" "$(cat "$f")"
  t_not_contains "$(basename "$f") — 본문을 품지 않는다" "## 다시 볼 때가 된 것" "$(cat "$f")"
  t_not_contains "$(basename "$f") — 영어 본문도 없다" "## Due for another look" "$(cat "$f")"
done

# 치환자가 양쪽에 같은 이름으로 있어야 한다.
for v in NAME FOLDER REPODOCS TODAY; do
  t_contains "ko 허브에 {{${v}}}" "{{${v}}}" "$(cat "$HUB_KO")"
  t_contains "en 허브에 {{${v}}}" "{{${v}}}" "$(cat "$HUB_EN")"
done

# CLI 가 실제로 README 를 만드는가 — 치환자가 남으면 죽은 쿼리가 된다.
t_contains "project add 가 허브를 만든다" "_pj_readme" "$(cat "$ROOT/lib/projectcmd.sh")"
t_contains "치환자가 남으면 쓰지 않는다" "허브 치환 실패" "$(cat "$ROOT/lib/projectcmd.sh")"
# 이미 등록된 프로젝트도 허브를 받아야 한다.
t_contains "README 누락을 할 일로 센다" "will_readme" "$(cat "$ROOT/lib/projectcmd.sh")"
# 볼트에 원본이 깔려야 템플릿이 읽는다.
t_contains "obsidian 이 허브 원본을 설치" "_devtrail-project-readme.md" \
  "$(cat "$ROOT/lib/merge/templates.sh")"

# ── 쓰기 명령은 dry-run 이 기본이다 ─────────────────────────────────────────
#
# ⚠️ 회귀: install-schedule 만 인자를 아예 보지 않고 즉시 적용했다.
#    `devtrail install-schedule --help` 가 도움말 대신 사용자 머신에
#    launchd 작업을 등록해 버렸다(2026-08-22 실물 QA 에서 실제로 발생).
#    되돌리려면 devtrail uninstall 을 알아야 하는데, 그 사실을 알려주지도
#    않았다. 백그라운드 작업을 거는 명령이야말로 dry-run 이 필요한 자리다.
t_start "쓰기 명령의 dry-run 규약"
t_vault sched
t_config notes
SC="$ROOT/lib/schedule.sh"

t_contains "install-schedule 이 --apply 를 안다" -- "--apply" "$(cat "$SC")"
t_contains "dry-run 문구가 있다" "dry-run" "$(cat "$SC")"
# 알 수 없는 옵션을 삼키면 오타가 곧 실행이 된다.
t_contains "알 수 없는 옵션을 거절" "알 수 없는 옵션" "$(cat "$SC")"
# 되돌리는 방법을 화면에 남긴다 — 사용자가 uninstall 을 알 길이 없다.
t_contains "되돌리기를 안내" "devtrail uninstall" "$(cat "$SC")"

# ⚠️ 실제로 등록하지 않는지 확인한다. 문구만 보면 '설명은 dry-run,
#    동작은 즉시 적용' 을 못 잡는다.
AG="$T_TMP/agents"; mkdir -p "$AG"
out=$(HOME="$T_TMP/fakehome-sched" "$ROOT/bin/devtrail" install-schedule 2>&1)
t_contains "인자 없으면 dry-run" "dry-run" "$out"
t_eq "plist 를 만들지 않는다" "0" \
  "$(ls "$T_TMP/fakehome-sched/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')"

# ⚠️ --help 은 라우터가 가로채므로 여기까지 오지 않는다. 그래도 부작용이
#    없는지는 확인한다 — 결함 7 은 도움말을 물었는데 등록을 한 것이었다.
out2=$(HOME="$T_TMP/fakehome-sched" "$ROOT/bin/devtrail" install-schedule --help 2>&1)
t_contains "--help 는 무언가 알려준다" "install-schedule" "$out2"
t_eq "--help 도 plist 를 만들지 않는다" "0" \
  "$(ls "$T_TMP/fakehome-sched/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')"

t_exit "알 수 없는 옵션은 종료코드 1" 1 \
  env HOME="$T_TMP/fakehome-sched" "$ROOT/bin/devtrail" install-schedule --nonsense

# ── 오류는 stderr 로 ────────────────────────────────────────────────────────
#
# ⚠️ 회귀: die 가 stdout 으로 나가면 명령 치환에 갇힌다.
#
#      spec=$(sp_read "$file")   # 안에서 die 하면 메시지가 $() 에 삼켜진다
#
#    스펙이 잘못돼도 화면에 아무것도 나오지 않았다(2026-08-22). 그때는
#    검증을 치환 밖으로 빼는 국소 수정을 했지만, 원인은 die 의 출력
#    스트림이다. 같은 함정이 lib/ 곳곳에 남아 있었다.
#
# ⚠️ 성공 출력(ok/info/step)은 stdout 그대로 둔다. 파이프로 넘기는 값이다.
t_start "오류는 stderr 로 나간다"
(
  export DEVTRAIL_ROOT="$ROOT"
  . "$ROOT/lib/common.sh"
  printf '%s' "$(fail "보이면 안 됨" 2>/dev/null)" > "$T_TMP/fail-stdout"
  fail "여기 나와야 함" 2> "$T_TMP/fail-stderr" >/dev/null
  warn "경고도" 2> "$T_TMP/warn-stderr" >/dev/null
  ok   "성공은" > "$T_TMP/ok-stdout" 2>/dev/null
)
t_eq "fail 은 stdout 에 안 쓴다" "" "$(cat "$T_TMP/fail-stdout")"
t_contains "fail 은 stderr 로"   "여기 나와야 함" "$(cat "$T_TMP/fail-stderr")"
t_contains "warn 도 stderr 로"   "경고도"         "$(cat "$T_TMP/warn-stderr")"
# 성공 출력까지 옮기면 $(devtrail path devlog) 같은 것이 전부 빈다.
t_contains "ok 는 stdout 유지"   "성공은"         "$(cat "$T_TMP/ok-stdout")"

# ⚠️ 진짜로 중요한 것: 명령 치환 안에서도 사용자가 오류를 본다.
t_start "명령 치환 안에서도 오류가 보인다"
out=$( { v=$(DEVTRAIL_CONFIG="$T_TMP/nope.json" "$ROOT/bin/devtrail" path devlog); } 2>&1 )
t_contains "설정 없음을 말해준다" "설정이 없습니다" "$out"

# 실제로 이 함정에 빠졌던 경로 — 잘못된 스펙
BADSPEC="$T_TMP/badspec.json"
jq -n '{spec_version: 99, vault: {path: "/tmp/x"}}' > "$BADSPEC"
out2=$( { v=$(DEVTRAIL_CONFIG="$T_TMP/nope.json" \
          "$ROOT/bin/devtrail" setup apply --input "$BADSPEC"); } 2>&1 )
t_contains "모르는 spec_version 을 말해준다" "spec_version" "$out2"

# ── --help 은 설정을 요구하지 않는다 ────────────────────────────────────────
#
# ⚠️ 도움말을 보려는 사람에게 "먼저 devtrail init 을 실행하세요" 가 뜨는 건
#    말이 안 된다. 그런데 require_config 가 인자 파싱보다 먼저 돌아서
#    augment · path · config · template · project 가 전부 그랬다.
#
# ⚠️ 명령마다 따로 처리하면 또 갈린다 — 실제로 어떤 것은 "알 수 없는 옵션",
#    어떤 것은 "init 하세요", doctor 는 그냥 진단을 돌렸다.
#    라우터 한 곳에서 가로챈다.
t_start "--help 은 설정 없이도 답한다"
for c in scan augment doctor path config template project skills plugins \
         update undo app setup activity weekly sync; do
  out=$(DEVTRAIL_CONFIG="$T_TMP/nope.json" "$ROOT/bin/devtrail" "$c" --help 2>&1)
  t_not_contains "$c — init 을 요구하지 않는다" "설정이 없습니다" "$out"
  t_ne "$c — 무언가 알려준다" "" "$out"
done

# -h 도 같아야 한다.
t_not_contains "-h 도 마찬가지" "설정이 없습니다" \
  "$(DEVTRAIL_CONFIG="$T_TMP/nope.json" "$ROOT/bin/devtrail" augment -h 2>&1)"

# ⚠️ --help 이 부작용을 내면 안 된다. 결함 7 이 그것이었다.
t_start "--help 은 아무것도 하지 않는다"
HH="$T_TMP/help-home"; mkdir -p "$HH"
DEVTRAIL_CONFIG="$T_TMP/nope.json" HOME="$HH" \
  "$ROOT/bin/devtrail" install-schedule --help >/dev/null 2>&1
t_eq "launchd 를 등록하지 않는다" "0" \
  "$(ls "$HH/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')"

t_end
