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
t_eq "install·enable·disable 세 곳" "3" \
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

t_end
