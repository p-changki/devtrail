#!/usr/bin/env bash
# Command Center — 플러그인 골격과 설치 경로.
#
# Phase 1 의 계약은 하나다:
#
#   노트를 하나도 건드리지 않고 켜고 끌 수 있으며, devtrail undo 가 되돌린다.
#
# ⚠️ 이 플러그인은 우리 것이지만 예외를 두지 않는다. 남의 플러그인에 적용하는
#    안전 계약(동의·저널·되돌리기·기존 목록 보존)이 우리 것에는 필요 없다고
#    말할 근거가 없다. [ADR 0002](../docs/decisions/0002-command-center.md)
#
# ⚠️ 네트워크를 쓰지 않는다. 빌드가 없으므로 plugin/ 이 곧 배포물이다(D3).
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"
export DEVTRAIL_ROOT="$ROOT"
unset DEVTRAIL_JOURNAL
export DEVTRAIL_OBSIDIAN_REGISTRY="$T_TMP/no-registry.json"

PID=devtrail-command-center

# ── 플러그인 자체 ────────────────────────────────────────────────────────────
t_start "플러그인 파일"
t_file "manifest.json" "$ROOT/plugin/manifest.json"
t_file "main.js"       "$ROOT/plugin/main.js"
t_json "manifest 가 유효한 JSON" "$ROOT/plugin/manifest.json"
t_eq "id 가 규약대로" "$PID" "$(jq -r '.id' "$ROOT/plugin/manifest.json")"
t_ne "minAppVersion 이 있다" "null" "$(jq -r '.minAppVersion' "$ROOT/plugin/manifest.json")"
t_ne "버전이 있다" "null" "$(jq -r '.version' "$ROOT/plugin/manifest.json")"

# ⚠️ 빌드 도구를 도입하지 않기로 했다(ADR 0002 D3). 번들러 흔적이 생기면
#    그 결정이 조용히 뒤집힌 것이다.
t_no_file "package.json 이 없다"  "$ROOT/plugin/package.json"
t_no_file "tsconfig 가 없다"      "$ROOT/plugin/tsconfig.json"
t_eq "소스가 한 파일" "1" "$(ls "$ROOT/plugin"/*.js 2>/dev/null | wc -l | tr -d ' ')"

# 뒤집는 조건 중 하나 — 1500줄. 넘으면 ADR 을 다시 봐야 한다.
n=$(wc -l < "$ROOT/plugin/main.js" | tr -d ' ')
t_eq "소스가 1500줄 미만" "true" "$([ "$n" -lt 1500 ] && echo true || echo false)"

# ── 명령 표면 ────────────────────────────────────────────────────────────────
t_start "명령 표면"
t_contains "usage 에 있다" "command-center" "$("$DT" help 2>&1)"
t_contains "알 수 없는 하위 명령 거절" "알 수 없는 하위 명령" \
  "$(DEVTRAIL_CONFIG=/dev/null "$DT" command-center nonsense 2>&1)"
t_not_contains "--help 이 설정을 요구하지 않는다" "설정이 없습니다" \
  "$(DEVTRAIL_CONFIG="$T_TMP/nope.json" "$DT" command-center --help 2>&1)"

# ── 설치 ─────────────────────────────────────────────────────────────────────
_vault() {
  local v="$T_TMP/$1"
  mkdir -p "$v/.obsidian" "$v/notes/개발"
  printf -- '---\ntype: devlog\n---\n# 노트\n' > "$v/notes/개발/사용자노트.md"
  printf '%s' "$v"
}
_cfg() {
  local v="$1" h="$2"
  mkdir -p "$h"
  jq -n --arg v "$v" '{version:3, lang:"ko",
    vault:{backend:"local", path:$v, root:"notes"}, dirs:{},
    github:{user:"t", repos:[], project_groups:{}},
    install:{mode:"new", modules:["devlog"]}}' > "$h/devtrail.config.json"
}

t_start "install 은 dry-run 이 기본"
V1=$(_vault v1); H1="$T_TMP/h1"; _cfg "$V1" "$H1"
out=$(DEVTRAIL_HOME="$H1" DEVTRAIL_CONFIG="$H1/devtrail.config.json" \
      "$DT" command-center install 2>&1)
t_contains "무엇을 할지 말한다" "$PID" "$out"
t_no_file "플러그인을 깔지 않는다" "$V1/.obsidian/plugins/$PID/main.js"
t_no_file "community-plugins 를 만들지 않는다" "$V1/.obsidian/community-plugins.json"

t_start "install --apply"
DEVTRAIL_HOME="$H1" DEVTRAIL_CONFIG="$H1/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1
t_file "main.js 설치" "$V1/.obsidian/plugins/$PID/main.js"
t_file "manifest.json 설치" "$V1/.obsidian/plugins/$PID/manifest.json"
# ⚠️ 설치가 곧 활성화는 아니다. 기존 볼트에는 opt-in 이어야 한다(ADR 0002).
t_no_file "설치만으로 켜지지 않는다" "$V1/.obsidian/community-plugins.json"

# ⚠️ Phase 1 의 종료 기준 — 노트를 하나도 건드리지 않는다.
t_start "노트를 건드리지 않는다"
t_eq "사용자 노트 그대로" "$(printf -- '---\ntype: devlog\n---\n# 노트\n')" \
  "$(cat "$V1/notes/개발/사용자노트.md")"
t_eq "노트 수 그대로" "1" \
  "$(find "$V1/notes" -name '*.md' | wc -l | tr -d ' ')"

# ── 켜기·끄기 ────────────────────────────────────────────────────────────────
t_start "enable 은 남의 목록을 지우지 않는다"
printf '%s' '["obsidian-excalidraw-plugin","calendar"]' \
  > "$V1/.obsidian/community-plugins.json"
DEVTRAIL_HOME="$H1" DEVTRAIL_CONFIG="$H1/devtrail.config.json" \
  "$DT" command-center enable --apply >/dev/null 2>&1
list=$(cat "$V1/.obsidian/community-plugins.json")
t_contains "우리 것이 들어간다" "$PID" "$list"
t_contains "쓰던 것 1" "excalidraw" "$list"
t_contains "쓰던 것 2" "calendar" "$list"
t_eq "셋이다" "3" "$(jq 'length' "$V1/.obsidian/community-plugins.json")"

t_start "disable 은 우리 것만 뺀다"
DEVTRAIL_HOME="$H1" DEVTRAIL_CONFIG="$H1/devtrail.config.json" \
  "$DT" command-center disable --apply >/dev/null 2>&1
list=$(cat "$V1/.obsidian/community-plugins.json")
t_not_contains "우리 것이 빠진다" "$PID" "$list"
t_contains "쓰던 것은 남는다" "excalidraw" "$list"
t_eq "둘이다" "2" "$(jq 'length' "$V1/.obsidian/community-plugins.json")"
# 끄는 것과 지우는 것은 다르다.
t_file "파일은 남는다" "$V1/.obsidian/plugins/$PID/main.js"

# ── status ───────────────────────────────────────────────────────────────────
t_start "status --json"
s=$(DEVTRAIL_HOME="$H1" DEVTRAIL_CONFIG="$H1/devtrail.config.json" \
    "$DT" command-center status --json 2>/dev/null)
printf '%s' "$s" > "$T_TMP/cc.json"
t_json "유효한 JSON" "$T_TMP/cc.json"
t_eq "설치됨"  "true"  "$(jq -r '.installed' "$T_TMP/cc.json")"
t_eq "꺼져 있음" "false" "$(jq -r '.enabled' "$T_TMP/cc.json")"

# ── 되돌리기 ─────────────────────────────────────────────────────────────────
#
# ⚠️ Phase 1 의 종료 기준. 되돌릴 수 없으면 남의 볼트에 넣을 수 없다.
t_start "undo 가 되돌린다"
V2=$(_vault v2); H2="$T_TMP/h2"; _cfg "$V2" "$H2"
DEVTRAIL_HOME="$H2" DEVTRAIL_CONFIG="$H2/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1
t_file "설치됨" "$V2/.obsidian/plugins/$PID/main.js"

job=$(ls -1 "$H2/journal" 2>/dev/null | tail -1)
t_ne "저널 작업이 생겼다" "" "$job"
t_eq "명령 이름" "command-center-install" \
  "$(jq -r '.command' "$H2/journal/$job/meta.json" 2>/dev/null)"

DEVTRAIL_HOME="$H2" DEVTRAIL_CONFIG="$H2/devtrail.config.json" \
  "$DT" undo "$job" --apply >/dev/null 2>&1
t_no_file "main.js 가 지워진다" "$V2/.obsidian/plugins/$PID/main.js"
t_no_file "manifest 도 지워진다" "$V2/.obsidian/plugins/$PID/manifest.json"
t_eq "사용자 노트는 그대로" "1" \
  "$(find "$V2/notes" -name '*.md' | wc -l | tr -d ' ')"

# ── Obsidian 실행 중 ────────────────────────────────────────────────────────
#
# ⚠️ 회귀: Obsidian 이 실행 중일 때 플러그인을 넣으면 그 폴더를 인지하지
#    못한다. 우리는 "설치했습니다" 라고 보고하는데 사용자는 화면을 못 본다.
#    2026-08-22 실물 확인에서 실제로 그랬다 — 설치·활성화가 다 됐는데
#    화면이 안 나왔고, 원인은 실행 중에 목록을 바꿔서였다.
#
# ⚠️ 볼트 레지스트리와는 다르다. 거기서는 Obsidian 이 종료할 때 우리 변경을
#    덮어쓰므로 아예 건너뛴다. 플러그인 파일은 살아남으므로 막지 않는다.
#    대신 재시작해야 반영된다고 말한다 — 말하지 않으면 사용자는 고장으로 본다.
t_start "실행 중이면 재시작을 알려준다"
SRC="$ROOT/lib/commandcentercmd.sh"
t_contains "install 이 실행 여부를 본다" "oa_warn_if_running" "$(cat "$SRC")"
# 켜기·끄기도 같은 함정이다.
# 주석(source 줄)이 아니라 실제 호출만 센다.
t_eq "install·update·enable·disable 네 곳" "4" \
  "$(grep -cE '^\s+oa_warn_if_running' "$SRC" | tr -d ' ')"

# 플러그인 설치 경로에도 같은 안내가 있어야 한다 — 같은 함정이다.
t_contains "plugins install 도 본다" "oa_warn_if_running" "$(cat "$ROOT/lib/plugins.sh")"

# ⚠️ 안내가 '재시작해야 보인다' 를 실제로 말하는가. 함수만 있고 문구가
#    빈약하면 사용자는 여전히 고장으로 본다.
t_contains "재시작을 말한다" "재시작" "$(cat "$ROOT/lib/obsidian_app.sh")"
t_contains "종료 후 재실행을 권한다" "종료한 뒤" "$(cat "$ROOT/lib/obsidian_app.sh")"

# 공용 헬퍼로 한 곳에서 만든다. 문구가 명령마다 갈리면 또 어긋난다.
t_contains "공용 헬퍼가 있다" "oa_warn_if_running" "$(cat "$ROOT/lib/obsidian_app.sh")"

# ⚠️ 막지는 않는다. 파일 쓰기는 유효하므로 설치 자체는 되어야 한다.
t_start "실행 중이어도 설치는 된다"
V3=$(_vault v3); H3="$T_TMP/h3"; _cfg "$V3" "$H3"
out=$(DEVTRAIL_HOME="$H3" DEVTRAIL_CONFIG="$H3/devtrail.config.json" \
      "$DT" command-center install --apply 2>&1)
t_file "실행 여부와 무관하게 설치된다" "$V3/.obsidian/plugins/$PID/main.js"
t_eq "종료코드 0" "0" "$?"

# ── 읽기 모델 ────────────────────────────────────────────────────────────────
#
# Phase 2 의 종료 기준: 어떤 카드도 지어낸 데이터를 보고하지 않는다.
#
# ⚠️ 볼트에는 '노트처럼 생겼지만 노트가 아닌 것' 이 많다. 실측(QA 볼트):
#
#      type: project-home    6건 — 그중 2건이 템플릿
#      status: inbox         2건 — 둘 다 템플릿
#
#    템플릿을 세면 빈 볼트에서도 "프로젝트 2개" 가 뜬다. 그게 지어낸
#    데이터다. 제외 규칙은 화면 장식이 아니라 계약이다.
t_start "읽기 모델의 제외 규칙"
JS="$ROOT/plugin/main.js"
t_contains "템플릿 폴더를 제외한다"  "templates"   "$(cat "$JS")"
t_contains "밑줄 파일을 제외한다"    "startsWith('_')" "$(cat "$JS")"
t_contains "허브(_index)를 제외한다" "_index"      "$(cat "$JS")"

# 제외 함수가 실제로 동작하는지 — 문자열 검사만으로는 '있지만 안 부르는' 코드를 못 잡는다.
t_start "제외가 실제로 동작한다"
cat > "$T_TMP/excl.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {} };
  return orig(r, p, m);
};
const P = require(process.argv[2]);
const f = P.__test;
if (!f || typeof f.isUserNote !== 'function') { console.log('NOHOOK'); process.exit(0); }
const paths = { templates: 'notes/템플릿' };
const cases = [
  ['notes/템플릿/Inbox Capture 템플릿.md', false],
  ['notes/템플릿/_devtrail-project-readme.md', false],
  ['notes/개발/프로젝트/_index.md', false],
  ['notes/개발/프로젝트/my-app/README.md', true],
  ['notes/개발/개발일지/2026-08-22 devlog.md', true],
];
let bad = 0;
for (const [p, want] of cases) {
  const got = f.isUserNote(p, paths);
  if (got !== want) { bad++; console.log('MISMATCH', p, 'want', want, 'got', got); }
}
console.log(bad === 0 ? 'OK' : 'FAIL');
JSEOF
if command -v node >/dev/null 2>&1; then
  r=$(node "$T_TMP/excl.js" "$JS" 2>&1 | tail -1)
  t_eq "템플릿·밑줄·허브를 걸러낸다" "OK" "$r"
else
  dim "   node 없음 — 동작 검사 건너뜀"
fi

# ── 카드 ─────────────────────────────────────────────────────────────────────
t_start "카드가 실재 소스를 읽는다"
# 설계안 §6 의 읽기 모델. 없는 필드를 지어내지 않는다.
t_contains "프로젝트: project-home"  "project-home"   "$(cat "$JS")"
t_contains "프로젝트: status active" "'active'"       "$(cat "$JS")"
t_contains "Inbox: status inbox"     "'inbox'"        "$(cat "$JS")"
t_contains "리뷰: review_at"         "review_at"      "$(cat "$JS")"
# ⚠️ v1 에 없는 필드를 만들지 않는다. frontmatter 커버리지가 고르지 않아
#    빈 대시보드가 되고, 사용자 노트 마이그레이션을 강요하게 된다.
#    ⚠️ 주석에 단어가 나오는 것은 괜찮다. '읽는지' 를 봐야 한다.
t_eq "priority 를 읽지 않는다" "0" \
  "$(grep -cE 'meta\.priority|\.priority\b' "$JS" | tr -d ' ')"
t_eq "due 를 읽지 않는다" "0" \
  "$(grep -cE 'meta\.due\b|\.due\b' "$JS" | tr -d ' ')"

# 빈 볼트에서 0 을 늘어놓지 않는다 — 안내가 되어야 한다.
t_contains "빈 상태 문구가 있다" "empty" "$(cat "$JS")"

# ── 라우트 ───────────────────────────────────────────────────────────────────
#
# Phase 3 의 종료 기준: 각 화면이 구체적인 다음 행동을 주고,
#                      노트 생성 로직을 중복하지 않는다.
t_start "라우트가 존재한다"
for r in home today capture projects reviews; do
  t_contains "$r" "'$r'" "$(cat "$JS")"
done

# ── 노트 생성을 다시 만들지 않는다 ──────────────────────────────────────────
#
# ⚠️ Capture 는 기존 Templater 명령을 부른다. 같은 노트를 만드는 코드가
#    플러그인에도 생기면 템플릿을 고쳐도 플러그인 쪽은 옛말을 한다.
#    2026-08-22 QA 에서 프로젝트 허브 본문이 두 곳에 있어 링크가 전부
#    깨진 적이 있다 — 같은 유형이다.
t_start "노트 생성을 중복하지 않는다"
t_contains "명령을 실행한다" "commands.executeCommandById" "$(cat "$JS")"
# 노트를 직접 만들면 그게 두 번째 생성 경로다.
t_eq "vault.create 를 부르지 않는다" "0" \
  "$(grep -cE 'vault\.create\(|vault\.createFolder\(' "$JS" | tr -d ' ')"
t_eq "파일에 쓰지 않는다" "0" \
  "$(grep -cE 'vault\.modify\(|vault\.append\(' "$JS" | tr -d ' ')"

# ⚠️ Templater 명령 id 에는 볼트 경로가 들어간다. 하드코딩하면 영어 볼트나
#    다른 루트를 쓰는 사람에게서 조용히 죽는다 — 경로 맵에서 조립해야 한다.
t_contains "명령 id 를 조립한다" "templater-obsidian:create-" "$(cat "$JS")"
# ⚠️ 파일명 한/영 매핑(CAPTURES)은 필요하다 — 템플릿 이름이 언어마다 다르다.
#    막아야 할 것은 '경로' 하드코딩이다. notes/템플릿 처럼 볼트 구조를 박으면
#    루트를 바꾼 사람에게서 조용히 죽는다.
t_eq "볼트 경로를 박지 않는다" "0" \
  "$(grep -cE "['\"\`][^'\"\`]*notes/" "$JS" | tr -d ' ')"

# 명령이 없을 때 조용히 다른 노트를 만들면 안 된다 — 무엇을 해야 할지 말한다.
t_contains "없는 명령을 알려준다" "notReady" "$(cat "$JS")"

# ── 조립이 실제로 맞는가 ────────────────────────────────────────────────────
t_start "명령 id 조립"
cat > "$T_TMP/cmdid.js" <<'JSEOF'
const Module = require('module'); const orig = Module._load;
Module._load = (r,p,m) => r === 'obsidian' ? { Plugin: class{}, ItemView: class{} } : orig(r,p,m);
const P = require(process.argv[2]);
const f = P.__test;
if (!f || typeof f.templaterCommandId !== 'function') { console.log('NOHOOK'); process.exit(0); }
const ko = f.templaterCommandId({ templates: 'notes/템플릿' }, '개발일지양식.md');
const en = f.templaterCommandId({ templates: 'MyVault/Templates' }, 'Devlog.md');
const bad = f.templaterCommandId({}, 'Devlog.md');
console.log(ko === 'templater-obsidian:create-notes/템플릿/개발일지양식.md'
         && en === 'templater-obsidian:create-MyVault/Templates/Devlog.md'
         && bad === null ? 'OK' : `FAIL ko=${ko} en=${en} bad=${bad}`);
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "경로 맵에서 조립한다" "OK" "$(node "$T_TMP/cmdid.js" "$JS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

# ── 메인 탭 전체 화면 ───────────────────────────────────────────────────────
#
# ⚠️ 사이드 패널(폭 300px)에는 정보 밀도를 담을 수 없다. 메인 워크스페이스
#    탭으로 연다.
#
# ⚠️ getLeaf(true) 가 아니라 getLeaf('tab') 이다. true 는 "새 leaf 를 강제"
#    라는 뜻이고, 우리가 원하는 건 "메인 영역의 탭" 이다. Obsidian 자신이
#    app.asar 에서 getLeaf("tab") · getLeaf("split") 을 쓴다(2026-08-22 확인).
t_start "메인 탭으로 연다"
t_contains "메인 탭 API 를 쓴다" "getLeaf('tab')" "$(cat "$JS")"
t_eq "사이드 패널로 열지 않는다" "0" \
  "$(grep -c 'getRightLeaf' "$JS" | tr -d ' ')"

# ⚠️ 회귀: 이미 열린 뷰가 사이드 패널에 있으면 그걸 재사용해서, 메인 탭
#    코드가 아예 실행되지 않았다. Phase 1·2 를 써본 사람은 전부 그 상태다 —
#    갱신해도 화면이 옛 자리에 그대로 있다(2026-08-22 실물 확인).
#    사이드에 있는 뷰는 재사용하지 않고 옮긴다.
t_contains "사이드에 있으면 옮긴다" "isMainLeaf" "$(cat "$JS")"
# ⚠️ 함수가 있는 것과 '쓰는' 것은 다르다. activate 가 실제로 걸러야 한다.
t_contains "activate 가 메인을 고른다" "isMainLeaf(l, workspace.rootSplit)" "$(cat "$JS")"
# 아무 leaf 나 재사용하면 사이드에 남은 옛 뷰가 이긴다.
t_eq "아무 leaf 나 재사용하지 않는다" "0" \
  "$(grep -c 'revealLeaf(open\[0\])' "$JS" | tr -d ' ')"
# 사이드에 남은 것은 닫아야 같은 화면이 둘이 되지 않는다.
t_contains "남은 뷰를 닫는다" "l.detach()" "$(cat "$JS")"

# ⚠️ 회귀: Obsidian 은 시작할 때 workspace.json 의 레이아웃을 복원한다.
#    예전 버전이 사이드독에 열어둔 뷰가 거기 저장돼 있어서, 재시작하면
#    activate() 를 거치지 않고 사이드에 그대로 되살아난다.
#    실측: workspace.json 의 right 에 뷰가 1개 있었다(2026-08-22).
#    레이아웃이 준비되면 스스로 옮겨야 한다.
t_contains "레이아웃 준비 후 정리한다" "onLayoutReady" "$(cat "$JS")"
t_contains "복원된 사이드 뷰를 옮긴다" "relocateIfSide" "$(cat "$JS")"

cat > "$T_TMP/leaf.js" <<'JSEOF'
const Module = require('module'); const orig = Module._load;
Module._load = (r,p,m) => r === 'obsidian' ? { Plugin: class{}, ItemView: class{} } : orig(r,p,m);
const f = require(process.argv[2]).__test;
if (!f || typeof f.isMainLeaf !== 'function') { console.log('NOHOOK'); process.exit(0); }
// 메인 탭의 leaf 는 루트 컨테이너 아래에 있다. 사이드는 좌·우 split 아래다.
const root = { type: 'split' };
const main  = { getRoot: () => root, parent: { type: 'tabs' } };
const side  = { getRoot: () => ({ type: 'sidedock' }), parent: { type: 'tabs' } };
const ok = f.isMainLeaf(main, root) === true && f.isMainLeaf(side, root) === false;
console.log(ok ? 'OK' : 'FAIL');
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "메인/사이드를 구분한다" "OK" "$(node "$T_TMP/leaf.js" "$JS" 2>&1 | tail -1)"
fi

# ── 지표 ────────────────────────────────────────────────────────────────────
#
# ⚠️ 지표는 DevTrail 개념이다. Meetings·Events·Focus 같은 것을 넣으면 볼트에
#    그 개념이 없어 전부 0 이 뜬다 — 실측: meeting 0 · event 0 · task 0 ·
#    focus 0 · area 0 · priority 0. 그건 지어낸 화면이다.
t_start "지표가 DevTrail 개념이다"
for k in devlog projects inbox trouble; do
  t_contains "지표 $k" "$k" "$(cat "$JS")"
done
t_eq "meeting 을 세지 않는다" "0" "$(grep -cE "'meeting'|\"meeting\"" "$JS" | tr -d ' ')"
t_eq "event 를 세지 않는다"   "0" "$(grep -cE "'event'|\"event\"" "$JS" | tr -d ' ')"

# ── 레이아웃 ────────────────────────────────────────────────────────────────
t_start "전체 화면 레이아웃"
CSS="$ROOT/plugin/styles.css"
t_contains "지표 스트립" "devtrail-cc-metrics" "$(cat "$CSS")"
t_contains "3열 그리드"  "devtrail-cc-columns" "$(cat "$CSS")"
# ⚠️ 좁아지면 열이 줄어야 한다. 고정 3열이면 사이드 패널에서 깨진다.
t_contains "폭에 따라 접힌다" "auto-fit" "$(cat "$CSS")"
t_contains "지표도 접힌다" "minmax" "$(cat "$CSS")"

# ── 단축키 ───────────────────────────────────────────────────────────────────
#
# ⚠️ 남의 단축키를 덮어쓰는 것은 되돌리기 어려운 피해다. 사용자는 자기가
#    무엇을 잃었는지도 모른다. 기존 hotkeys.json 은 전부 보존한다.
#
# ⚠️ 별도의 덮어쓰기 구현을 만들지 않는다. 기존 병합 구조(lib/gen/hotkeys.py
#    의 place())가 이미 충돌을 처리한다 — 이미 배정된 것은 유지하고, 점유된
#    조합은 대체를 찾거나 건너뛰며 보고한다.
t_start "단축키: 사용자 것을 보존한다"
HKSPEC="$ROOT/preset/obsidian/hotkeys.tmpl.json"
PATHS2="$T_TMP/hk-paths.json"
jq -n '{paths: {templates: "notes/템플릿", devlog: "notes/개발/개발일지"}}' > "$PATHS2"

# 사용자가 쓰던 단축키 — 우리와 무관한 것 + 우리가 원하는 조합을 이미 점유한 것
MINE="$T_TMP/mine-hotkeys.json"
jq -n '{
  "workspace:split-vertical": [{"modifiers":["Mod"],"key":"\\"}],
  "editor:toggle-bold":       [{"modifiers":["Mod"],"key":"B"}]
}' > "$MINE"

OUT=$(DT_TEMPLATES_DIR="$ROOT/preset/templates/ko" \
      python3 "$ROOT/lib/gen/hotkeys.py" hotkeys "$HKSPEC" "$PATHS2" "$MINE" "" 2>/dev/null)
printf '%s' "$OUT" > "$T_TMP/hk-out.json"
t_json "결과가 유효한 JSON" "$T_TMP/hk-out.json"

# (a) 기존 사용자 단축키가 그대로 남는다
t_eq "쓰던 단축키 1 유지" '[{"modifiers":["Mod"],"key":"\\"}]' \
  "$(jq -c '."workspace:split-vertical"' "$T_TMP/hk-out.json")"
t_eq "쓰던 단축키 2 유지" '[{"modifiers":["Mod"],"key":"B"}]' \
  "$(jq -c '."editor:toggle-bold"' "$T_TMP/hk-out.json")"

t_start "단축키: 충돌을 덮어쓰지 않는다"
# 우리가 쓰려는 조합(Mod+Shift+D)을 사용자가 이미 점유하고 있다면?
BUSY="$T_TMP/busy.json"
jq -n '{"my:own-command": [{"modifiers":["Mod","Shift"],"key":"D"}]}' > "$BUSY"
OUT2=$(DT_TEMPLATES_DIR="$ROOT/preset/templates/ko" \
       python3 "$ROOT/lib/gen/hotkeys.py" hotkeys "$HKSPEC" "$PATHS2" "$BUSY" "" 2>/dev/null)
printf '%s' "$OUT2" > "$T_TMP/hk-busy.json"
t_eq "점유한 조합은 그대로" '[{"modifiers":["Mod","Shift"],"key":"D"}]' \
  "$(jq -c '."my:own-command"' "$T_TMP/hk-busy.json")"
# 우리 명령은 다른 키로 가거나 배정되지 않는다 — 같은 조합을 쓰면 안 된다.
t_eq "같은 조합을 두 명령에 주지 않는다" "1" \
  "$(jq '[to_entries[] | .value[] | (.modifiers|sort|join("+")) + "+" + .key]
        | map(select(. == "Mod+Shift+D")) | length' "$T_TMP/hk-busy.json")"

# ⚠️ 우리가 먼저 배정한 키를 사용자가 나중에 다른 명령에 준 경우.
#    place() 는 '이미 우리 것' 이라 유지하고 넘어가는데, 그러면 두 명령이
#    같은 조합을 갖고도 아무도 모른다. 고쳐주지는 않는다 — 사용자 선택일 수
#    있다 — 대신 반드시 말한다(2026-08-22 실물에서 실제로 발생).
t_start "단축키: 뒤늦은 충돌을 말해준다"
LATE="$T_TMP/late.json"
jq -n '{
  "obsidian-shellcommands:shell-command-devtrail-activity-force":
    [{"modifiers":["Mod","Shift"],"key":"J"}],
  "my:precious": [{"modifiers":["Mod","Shift"],"key":"J"}]
}' > "$LATE"
ERR=$(DT_TEMPLATES_DIR="$ROOT/preset/templates/ko" \
      python3 "$ROOT/lib/gen/hotkeys.py" hotkeys "$HKSPEC" "$PATHS2" "$LATE" "" 2>&1 >/dev/null)
t_contains "겹친다고 알려준다" "Mod+Shift+J" "$ERR"
t_contains "어느 명령인지 말한다" "my:precious" "$ERR"

t_start "단축키: Command Center"
# (c) 실제 존재하는 명령만 가리킨다 — 우리 플러그인의 command id 는
#     manifest id + ':' + addCommand 의 id 다.
CCID="$(jq -r '.id' "$ROOT/plugin/manifest.json"):open"
t_contains "스펙에 Command Center 가 있다" "$CCID" "$(cat "$HKSPEC")"
t_contains "플러그인이 그 명령을 만든다" "id: 'open'" "$(cat "$JS")"
t_ne "단축키가 배정된다" "null" "$(jq -r --arg c "$CCID" '.[$c]' "$T_TMP/hk-out.json")"

# ⚠️ 외부 플러그인 명령은 스펙에 박지 않는다. 설치 여부도, 명령 id 도
#    실행 시점에만 알 수 있다.
t_eq "Omnisearch 를 스펙에 박지 않는다" "0" \
  "$(grep -ci 'omnisearch' "$HKSPEC" | tr -d ' ')"

t_start "검색: 없으면 안내만 한다"
# (d) Omnisearch 가 없으면 버튼이 안전하게 비활성화되고 안내가 뜬다
t_contains "플러그인 id 로 명령을 찾는다" "findCommandByPluginId" "$(cat "$JS")"
t_eq "명령 id 를 하드코딩하지 않는다" "0" \
  "$(grep -cE \"omnisearch:[a-z-]+\" "$JS" | tr -d ' ')"
t_contains "설치 안내 문구가 있다" "searchMissing" "$(cat "$JS")"

# (e) 명령 실행이 파일을 만들지 않는다 — 이미 위에서 보지만 검색에도 해당한다
t_eq "검색 버튼이 파일을 만들지 않는다" "0" \
  "$(grep -cE 'vault\.create\(|vault\.modify\(' "$JS" | tr -d ' ')"

# ── 시각 규약 ────────────────────────────────────────────────────────────────
#
# ⚠️ Obsidian 안에서는 테마를 이긴다고 생각하지 않는다. 우리 색을 강제하면
#    남의 테마가 깨진다 — docs/design-tokens.md 의 원칙 4.
#    색은 전부 Obsidian 의 시맨틱 변수에서 온다.
t_start "색을 하드코딩하지 않는다"
CSS="$ROOT/plugin/styles.css"
# ⚠️ 주석에 단어가 나오는 것은 괜찮다. 선언(: 뒤)에 있는지를 본다.
t_eq "hex 색이 없다" "0" \
  "$(grep -cE ':[^;]*#[0-9a-fA-F]{3,8}\b' "$CSS" | tr -d ' ')"
t_eq "rgb() 색이 없다" "0" \
  "$(grep -cE ':[^;]*rgba?\(' "$CSS" | tr -d ' ')"
# 전역 폰트·body 를 건드리면 사용자 볼트 전체가 바뀐다.
t_eq "body 를 건드리지 않는다" "0" "$(grep -cE '^\s*body\s*[{,]' "$CSS" | tr -d ' ')"
t_eq "전역 폰트를 정하지 않는다" "0" "$(grep -c 'font-family' "$CSS" | tr -d ' ')"

t_start "상태를 색으로만 말하지 않는다"
# ⚠️ 설계안 §3: 색만으로 신호하지 않는다. 색을 못 보는 사람이 있다.
#    배지는 글자를 갖고, 비활성 버튼은 title 로 이유를 말한다.
t_contains "배지에 글자가 있다" "devtrail-cc-badge" "$(cat "$JS")"
t_contains "비활성 이유를 title 로" "setAttr('title'" "$(cat "$JS")"

t_start "접근성"
t_contains "포커스가 보인다" "focus-visible" "$(cat "$CSS")"
t_contains "네비에 aria-label" "aria-label" "$(cat "$JS")"
t_contains "현재 탭을 알린다" "aria-current" "$(cat "$JS")"
# ⚠️ 움직임에 민감한 사람이 있다. 애니메이션을 넣었다면 끌 수 있어야 한다.
t_eq "감소된 모션을 존중한다" "1" \
  "$(grep -c 'prefers-reduced-motion' "$CSS" | tr -d ' ')"

t_start "지표 카드"
# 숫자만 있으면 무엇의 숫자인지 모른다. 아이콘·설명·이동이 함께 간다.
t_contains "아이콘을 붙인다" "setIcon" "$(cat "$JS")"
# ⚠️ 함수가 있는 것과 '연결된' 것은 다르다. 클릭 핸들러가 실제로 붙어야 한다.
t_contains "카드를 누르면 이동한다" "metricRoute" "$(cat "$JS")"
t_contains "클릭이 연결돼 있다" "() => this.metricRoute(route)" "$(cat "$JS")"
# 지표 6개가 갈 곳을 다 갖는가 — 하나라도 빠지면 누르고 아무 일도 안 난다.
t_eq "지표가 6개다" "6" "$(grep -c '\[t\.m' "$JS" | tr -d ' ')"

# ── 업데이트 ────────────────────────────────────────────────────────────────
#
# 배포 경로는 하나다 — 저장소의 plugin/ 이 곧 배포물이다(ADR 0002 D3).
# devtrail update(git pull)가 소스를 갱신하고, command-center update 가
# 그것을 볼트에 반영한다. 별도 다운로드 경로를 만들지 않는다 — 두 경로가
# 서로 다른 버전을 가져오면 사용자가 어느 게 진짜인지 모른다.
#
# ⚠️ 감지는 자동, 적용은 승인. 실행 중인 Obsidian 아래에서 파일을 갈아치우면
#    로딩 상태가 꼬인다.
_ccenv() {
  printf 'DEVTRAIL_HOME=%s DEVTRAIL_CONFIG=%s' "$1" "$1/devtrail.config.json"
}

t_start "update 는 기본이 읽기 전용"
VU=$(_vault vu); HU="$T_TMP/hu"; _cfg "$VU" "$HU"
DEVTRAIL_HOME="$HU" DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1

# 설치본을 옛 버전으로 만든다 — 업데이트가 필요한 상태.
python3 - "$VU/.obsidian/plugins/$PID/manifest.json" <<'PYEOF'
import json, io, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding='utf-8'))
d['version'] = '0.0.1'
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
before=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)

out=$(DEVTRAIL_HOME="$HU" DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
      "$DT" command-center update 2>&1)
t_contains "무엇이 바뀔지 말한다" "0.0.1" "$out"
after=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
t_eq "파일을 바꾸지 않는다" "$before" "$after"
t_eq "manifest 도 그대로" "0.0.1" \
  "$(jq -r '.version' "$VU/.obsidian/plugins/$PID/manifest.json")"

t_start "update --apply 만 바꾼다"
DEVTRAIL_HOME="$HU" DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "버전이 올라간다" "$(jq -r '.version' "$ROOT/plugin/manifest.json")" \
  "$(jq -r '.version' "$VU/.obsidian/plugins/$PID/manifest.json")"

t_start "최신이면 아무것도 안 바꾼다"
b2=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
out2=$(DEVTRAIL_HOME="$HU" DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
       "$DT" command-center update --apply 2>&1)
a2=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
t_eq "파일 그대로" "$b2" "$a2"
t_contains "최신이라고 말한다" "$(L "최신" "up to date")" "$out2"

t_start "검증 실패 시 기존 설치를 보존한다"
# ⚠️ 원본이 깨졌으면 아무것도 하지 않는다. 절반만 바꾼 플러그인이 최악이다.
BAD="$T_TMP/badsrc"; mkdir -p "$BAD"
printf '%s' '{"id":"someone-else","version":"9.9.9"}' > "$BAD/manifest.json"
printf 'x' > "$BAD/main.js"
keep=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
out3=$(DT_CC_SRC_OVERRIDE="$BAD" DEVTRAIL_HOME="$HU" \
       DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
       "$DT" command-center update --apply 2>&1)
now=$(md5 -q "$VU/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VU/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
t_eq "id 가 다르면 안 바꾼다" "$keep" "$now"
t_contains "id 불일치를 말한다" "id" "$out3"

t_start "업데이트가 사용자 것을 보존한다"
t_eq "활성 목록 그대로" "true" \
  "$(jq --arg p "$PID" 'index($p) != null' "$VU/.obsidian/community-plugins.json" 2>/dev/null || echo true)"
t_eq "사용자 노트 그대로" "1" \
  "$(find "$VU/notes" -name '*.md' | wc -l | tr -d ' ')"

t_start "update 도 되돌릴 수 있다"
job=$(ls -1 "$HU/journal" 2>/dev/null | tail -1)
t_ne "저널 작업이 있다" "" "$job"
t_contains "명령 이름이 update" "command-center-update" \
  "$(jq -r '.command' "$HU/journal/$job/meta.json" 2>/dev/null)"

t_start "status --json 이 상태를 다 말한다"
st=$(DEVTRAIL_HOME="$HU" DEVTRAIL_CONFIG="$HU/devtrail.config.json" \
     "$DT" command-center status --json 2>/dev/null)
printf '%s' "$st" > "$T_TMP/ccst.json"
t_json "유효한 JSON" "$T_TMP/ccst.json"
# ⚠️ false 는 유효한 값이다. // 는 false 를 falsy 로 보고 기본값으로 떨군다 —
#    저장소가 jq 의 // 를 boolean 에 쓰지 말라고 정한 이유가 이것이다.
for k in installed enabled installed_version available_version update_available \
         min_app_version restart_required; do
  t_eq "필드 $k 가 있다" "true" \
    "$(jq --arg k "$k" 'has($k)' "$T_TMP/ccst.json")"
  t_ne "필드 $k 가 null 이 아니다" "null" \
    "$(jq -r --arg k "$k" '.[$k] | tostring' "$T_TMP/ccst.json")"
done
# ⚠️ 모르는 것은 지어내지 않는다. 설치가 안 된 볼트에서는 버전을 알 수 없다.
VN=$(_vault vn); HN="$T_TMP/hn"; _cfg "$VN" "$HN"
stn=$(DEVTRAIL_HOME="$HN" DEVTRAIL_CONFIG="$HN/devtrail.config.json" \
      "$DT" command-center status --json 2>/dev/null)
printf '%s' "$stn" > "$T_TMP/ccst-none.json"
t_eq "미설치면 버전을 모른다" "unknown" \
  "$(jq -r '.installed_version' "$T_TMP/ccst-none.json")"
t_eq "미설치면 업데이트 여부도 모른다" "unknown" \
  "$(jq -r '.update_available | tostring' "$T_TMP/ccst-none.json")"
t_eq "설치 여부는 안다" "false" \
  "$(jq -r '.installed | tostring' "$T_TMP/ccst-none.json")"

# ── 프로젝트 칸반 ───────────────────────────────────────────────────────────
#
# 카드 하나 = 프로젝트 노트 하나다. 개발일지 체크박스를 카드로 만들지 않는다 —
# 같은 일을 두 곳에 적으면 둘 다 믿을 수 없게 된다.
#
# ⚠️ 읽기 전용이다. 카드를 옮겨 frontmatter 를 고치는 것은 다음 Phase다.
t_start "stage 를 컬럼으로 정규화한다"
cat > "$T_TMP/stage.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {} };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.normalizeStage !== 'function') { console.log('NOHOOK'); process.exit(0); }
const cases = [
  ['planning', 'planning'], ['planned', 'planning'], ['plan', 'planning'],
  ['in-progress', 'active'], ['in_progress', 'active'], ['active', 'active'], ['doing', 'active'],
  ['blocked', 'blocked'],
  ['done', 'done'], ['completed', 'done'], ['complete', 'done'], ['archived', 'done'],
  ['  Planning  ', 'planning'],  // 공백·대소문자를 견딘다
  ['IN-PROGRESS', 'active'],
  // ⚠️ 모르는 것을 임의 컬럼에 넣지 않는다. 사용자가 지정하지 않은 상태를
  //    '계획 중' 이라고 보여주면 화면이 사실이 아닌 것을 말한다.
  ['', null], [null, null], [undefined, null],
  ['nonsense', null], ['진행중', null], ['todo', null],
];
let bad = 0;
for (const [input, want] of cases) {
  const got = f.normalizeStage(input);
  if (got !== want) { bad++; console.log('MISMATCH', JSON.stringify(input), 'want', want, 'got', got); }
}
console.log(bad === 0 ? 'OK' : 'FAIL');
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "별칭이 옳은 컬럼으로 간다" "OK" "$(node "$T_TMP/stage.js" "$JS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "보드가 네 컬럼과 미지정을 갖는다"
t_contains "컬럼 정의" "BOARD_COLUMNS" "$(cat "$JS")"
for k in planning active blocked done; do
  t_contains "컬럼 $k" "'$k'" "$(cat "$JS")"
done
# ⚠️ 미지정은 다섯 번째 컬럼이 아니라 별도 영역이다 — 상태가 아니라 '빠진 것' 이다.
t_contains "미지정을 따로 다룬다" "unstaged" "$(cat "$JS")"
t_eq "컬럼은 넷이다" "4" \
  "$(grep -A8 'BOARD_COLUMNS = \[' "$JS" | grep -c "^\s*\['")"

t_start "카드가 노트에서 읽은 것만 보여준다"
t_contains "프로젝트명" "p.name" "$(cat "$JS")"
t_contains "next_action" "p.next" "$(cat "$JS")"
t_contains "마지막 수정" "p.file.stat.mtime" "$(cat "$JS")"
# 카드 전체가 눌린다 — 링크만 누르게 하면 표적이 너무 작다.
# ⚠️ 'Enter' 문구는 최근 기록 행에도 있다. 존재만 보면 카드에서 빼도 통과한다 —
#    카드 함수 안에 있는지를 본다.
t_contains "카드를 키보드로 연다" "ev.key === 'Enter'" \
  "$(sed -n '/projectCard(parent, t, p, colKey)/,/^  }/p' "$JS")"
t_contains "카드 전체가 눌린다" "c.addEventListener('click', open)" \
  "$(sed -n '/projectCard(parent, t, p, colKey)/,/^  }/p' "$JS")"
t_contains "빈 컬럼 문구" "emptyColumn" "$(cat "$JS")"

t_start "노트를 쓰지 않는다"
# ⚠️ 플러그인은 읽기 모델이다. 쓰기는 Templater 통로 하나뿐이다.
for m in "vault.create" "vault.modify" "vault.append" "processFrontMatter"; do
  t_eq "$m 를 부르지 않는다" "0" "$(grep -c "$m" "$JS" | tr -d ' ')"
done

t_start "상태색이 글자·아이콘과 함께 온다"
# ⚠️ 색만으로 상태를 말하지 않는다 — 다크/라이트와 색각에서 무너진다.
t_contains "상태 클래스" "devtrail-cc-col--" "$(cat "$JS")"
t_contains "컬럼에 아이콘" "devtrail-cc-col-icon" "$(cat "$JS")"
CSS="$ROOT/plugin/styles.css"
for s in "devtrail-cc-col--planning" "devtrail-cc-col--active" \
         "devtrail-cc-col--blocked" "devtrail-cc-col--done"; do
  t_contains "CSS $s" "$s" "$(cat "$CSS")"
done
t_contains "보드가 접힌다" "devtrail-cc-board" "$(cat "$CSS")"
t_contains "카드 포커스" ":focus-visible" "$(cat "$CSS")"

# ── 헤더 검색 · 빠른 실행 ───────────────────────────────────────────────────
#
# ⚠️ 검색기를 만들지 않는다. 설치된 검색 플러그인이나 Obsidian 기본 검색으로
#    가는 통로일 뿐이다 — 결과 목록을 흉내 내면 없는 기능을 있는 척하게 된다.
t_start "검색은 통로일 뿐이다"
t_contains "헤더에 검색 진입점" "devtrail-cc-search" "$(cat "$JS")"
t_contains "명령 존재를 확인한다" "commandExists" "$(cat "$JS")"
# 결과 UI 를 흉내 내지 않는다.
t_eq "결과 목록이 없다" "0" "$(grep -c 'searchResult\|renderResults' "$JS" | tr -d ' ')"
t_eq "자체 인덱스가 없다" "0" "$(grep -c 'buildIndex\|fuzzySearch' "$JS" | tr -d ' ')"
t_contains "없으면 안내로 떨어진다" "searchMissingHelp" "$(cat "$JS")"

t_start "빠른 실행이 Templater 만 부른다"
t_contains "실행 바" "devtrail-cc-launch" "$(cat "$JS")"
# ⚠️ 명령이 없으면 조용히 노트를 만들지 않는다 — 무엇을 해야 하는지 말한다.
# ⚠️ disabled 는 검색 바에도 있다. 실행 바가 명령 존재를 확인하는지를 본다.
t_contains "명령이 없으면 비활성" "if (!commandExists(this.app, id))" \
  "$(sed -n '/launchBar(root, t, data)/,/^  }/p' "$JS")"
t_contains "비활성으로 표시한다" "b.setAttr('disabled', 'true')" \
  "$(sed -n '/launchBar(root, t, data)/,/^  }/p' "$JS")"
t_contains "CSS 실행 바" "devtrail-cc-launch" "$(cat "$CSS")"

t_end
