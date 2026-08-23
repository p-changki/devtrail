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
# ⚠️ $( ) 안에 heredoc 을 쓰지 않는다. bash 가 종료어를 제대로 못 찾아
#    파이썬이 그 줄까지 읽고 NameError 를 낸다 — 결과가 비면 개수를 세는
#    단언은 0 을 얻어 **조용히 통과**한다. 2026-08-22 에 네 곳이 그랬다.
#    스크립트를 파일로 두고 부른다.
_run_py() {
  local name="$1"; shift
  python3 "$T_TMP/py/$name.py" "$@"
}
mkdir -p "$T_TMP/py"
cat > "$T_TMP/py/_pyck1.py" <<'PYSRC'
import re, sys
css = open(sys.argv[1], encoding='utf-8').read()
blk = css.find('@media (prefers-reduced-motion: reduce)')
if blk < 0:
    print('no'); raise SystemExit
# 블록 앞쪽에서 마지막으로 transition 을 선언한 자리
before = css[:blk]
last = before.rfind('transition:')
# 블록 뒤에 transition 선언이 남아 있으면 그것이 이긴다 — 실패다.
after = css[blk:]
end = after.find('\n}\n')
tail = after[end:] if end > 0 else ''
print('no' if 'transition:' in tail else 'yes')
PYSRC
cat > "$T_TMP/py/_pyck2.py" <<'PYSRC'
import re, sys
css = open(sys.argv[1], encoding='utf-8').read()
# transition 을 선언한 최상위 선택자들
animated = set()
for m in re.finditer(r'(?m)^(\.devtrail-cc-[a-z-]+)[^{]*\{([^}]*)\}', css):
    if 'transition:' in m.group(2):
        animated.add(m.group(1))
blk = re.search(r'@media \(prefers-reduced-motion: reduce\) \{(.*?)\n\}', css, re.S)
covered = set(re.findall(r'\.devtrail-cc-[a-z-]+', blk.group(1))) if blk else set()
print(' '.join(sorted(animated - covered)))
PYSRC
cat > "$T_TMP/py/_pyck3.py" <<'PYSRC'
import re, sys
from collections import Counter
css = open(sys.argv[1], encoding='utf-8').read()
sels = [m.group(1).strip() for m in re.finditer(r'(?m)^([^@/}\s][^{]*)\{', css)]
print(' '.join(sorted(s for s, n in Counter(sels).items() if n > 1)))
PYSRC
cat > "$T_TMP/py/_pyck4.py" <<'PYSRC'
import re, sys
css = open(sys.argv[1], encoding='utf-8').read()
bad = []
for m in re.finditer(r'(?m)^(\.[a-z-]+[^{]*)\{([^}]*)\}', css):
    props = [p.split(':')[0].strip() for p in m.group(2).split(';') if ':' in p]
    if any(props.count(x) > 1 for x in set(props)):
        bad.append(m.group(1).strip())
print(' '.join(bad))
PYSRC

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
# ⚠️ ADR 0004 로 여러 파일이 됐다. 지켜야 할 것은 '한 파일' 이 아니라
#    '빌드 단계가 없다' 는 것이다 — 소스가 곧 배포물이다(D2·D3).
t_eq "빌드 산출물이 없다" "0" \
  "$(ls "$ROOT/plugin"/*.min.js "$ROOT/plugin"/*.map 2>/dev/null | wc -l | tr -d ' ')"
t_eq "모든 js 가 배포 목록에 있다" "0" \
  "$(for f in "$ROOT/plugin"/*.js; do b=$(basename "$f");
       jq -e --arg b "$b" '.files | index($b)' "$ROOT/plugin/files.json" >/dev/null 2>&1 || echo x
     done | wc -l | tr -d ' ')"

# 뒤집는 조건 중 하나 — 1500줄. 넘으면 ADR 을 다시 봐야 한다.
# ⚠️ 나눴다고 총량이 준 것은 아니다. 합계로 본다 — 파일을 쪼개
#    한도를 피해 가는 일이 없게.
n=$(cat "$ROOT/plugin"/*.js | wc -l | tr -d ' ')
# ⚠️ ADR 0002 D3 의 1500 은 **재검토 조건**이지 상한이 아니다("이 결정을 다시
#    본다"). 하드 캡으로 바꾸면 정직하게 늘어난 코드를 막고, 그러면 사람은
#    테스트를 지우거나 숫자를 올린다. 넘는 것을 막는 대신 **기록 없이 넘는
#    것**을 막는다.
if [ "$n" -lt 1500 ]; then
  t_eq "1500줄 아래" "true" "true"
else
  t_contains "1500을 넘었으면 재검토가 기록돼 있다" "재검토 1" \
    "$(cat "$ROOT/docs/decisions/0002-command-center.md")"
fi

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
RMJS="$ROOT/plugin/read-model.js"
CMDJS="$ROOT/plugin/commands.js"
t_contains "템플릿 폴더를 제외한다"  "templates"   "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "밑줄 파일을 제외한다"    "startsWith('_')" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "허브(_index)를 제외한다" "_index"      "$(cat "$JS" "$RMJS" "$CMDJS")"

# 제외 함수가 실제로 동작하는지 — 문자열 검사만으로는 '있지만 안 부르는' 코드를 못 잡는다.
t_start "제외가 실제로 동작한다"
cat > "$T_TMP/excl.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
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
  r=$(node "$T_TMP/excl.js" "$RMJS" 2>&1 | tail -1)
  t_eq "템플릿·밑줄·허브를 걸러낸다" "OK" "$r"
else
  dim "   node 없음 — 동작 검사 건너뜀"
fi

# ── 카드 ─────────────────────────────────────────────────────────────────────
t_start "카드가 실재 소스를 읽는다"
# 설계안 §6 의 읽기 모델. 없는 필드를 지어내지 않는다.
t_contains "프로젝트: project-home"  "project-home"   "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "프로젝트: status active" "'active'"       "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "Inbox: status inbox"     "'inbox'"        "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "리뷰: review_at"         "review_at"      "$(cat "$JS" "$RMJS" "$CMDJS")"
# ⚠️ v1 에 없는 필드를 만들지 않는다. frontmatter 커버리지가 고르지 않아
#    빈 대시보드가 되고, 사용자 노트 마이그레이션을 강요하게 된다.
#    ⚠️ 주석에 단어가 나오는 것은 괜찮다. '읽는지' 를 봐야 한다.
t_eq "priority 를 읽지 않는다" "0" \
  "$(grep -cE 'meta\.priority|\.priority\b' "$JS" | tr -d ' ')"
t_eq "due 를 읽지 않는다" "0" \
  "$(grep -cE 'meta\.due\b|\.due\b' "$JS" | tr -d ' ')"

# 빈 볼트에서 0 을 늘어놓지 않는다 — 안내가 되어야 한다.
t_contains "빈 상태 문구가 있다" "empty" "$(cat "$JS" "$RMJS" "$CMDJS")"

# ── 라우트 ───────────────────────────────────────────────────────────────────
#
# Phase 3 의 종료 기준: 각 화면이 구체적인 다음 행동을 주고,
#                      노트 생성 로직을 중복하지 않는다.
t_start "라우트가 존재한다"
# ⚠️ 'capture' 는 없앴다 — 빠른 실행 바가 같은 6개를 항상 보여준다.
for r in home today projects reviews; do
  t_contains "$r" "'$r'" "$(cat "$JS" "$RMJS" "$CMDJS")"
done

# ── 노트 생성을 다시 만들지 않는다 ──────────────────────────────────────────
#
# ⚠️ Capture 는 기존 Templater 명령을 부른다. 같은 노트를 만드는 코드가
#    플러그인에도 생기면 템플릿을 고쳐도 플러그인 쪽은 옛말을 한다.
#    2026-08-22 QA 에서 프로젝트 허브 본문이 두 곳에 있어 링크가 전부
#    깨진 적이 있다 — 같은 유형이다.
t_start "노트 생성을 중복하지 않는다"
t_contains "명령을 실행한다" "commands.executeCommandById" "$(cat "$JS" "$RMJS" "$CMDJS")"
# 노트를 직접 만들면 그게 두 번째 생성 경로다.
t_eq "vault.create 를 부르지 않는다" "0" \
  "$(grep -cE 'vault\.create\(|vault\.createFolder\(' "$JS" | tr -d ' ')"
t_eq "파일에 쓰지 않는다" "0" \
  "$(grep -cE 'vault\.modify\(|vault\.append\(' "$JS" | tr -d ' ')"

# ⚠️ Templater 명령 id 에는 볼트 경로가 들어간다. 하드코딩하면 영어 볼트나
#    다른 루트를 쓰는 사람에게서 조용히 죽는다 — 경로 맵에서 조립해야 한다.
t_contains "명령 id 를 조립한다" "templater-obsidian:create-" "$(cat "$JS" "$RMJS" "$CMDJS")"
# ⚠️ 파일명 한/영 매핑(CAPTURES)은 필요하다 — 템플릿 이름이 언어마다 다르다.
#    막아야 할 것은 '경로' 하드코딩이다. notes/템플릿 처럼 볼트 구조를 박으면
#    루트를 바꾼 사람에게서 조용히 죽는다.
t_eq "볼트 경로를 박지 않는다" "0" \
  "$(grep -cE "['\"\`][^'\"\`]*notes/" "$JS" | tr -d ' ')"

# 명령이 없을 때 조용히 다른 노트를 만들면 안 된다 — 무엇을 해야 할지 말한다.
t_contains "없는 명령을 알려준다" "notReady" "$(cat "$JS" "$RMJS" "$CMDJS")"

# ── 조립이 실제로 맞는가 ────────────────────────────────────────────────────
t_start "명령 id 조립"
cat > "$T_TMP/cmdid.js" <<'JSEOF'
const Module = require('module'); const orig = Module._load;
Module._load = (r,p,m) => r === 'obsidian' ? { Plugin: class{}, ItemView: class{}, Modal: class { constructor() {} } } : orig(r,p,m);
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
  t_eq "경로 맵에서 조립한다" "OK" "$(node "$T_TMP/cmdid.js" "$CMDJS" 2>&1 | tail -1)"
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
t_contains "메인 탭 API 를 쓴다" "getLeaf('tab')" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "사이드 패널로 열지 않는다" "0" \
  "$(grep -c 'getRightLeaf' "$JS" | tr -d ' ')"

# ⚠️ 회귀: 이미 열린 뷰가 사이드 패널에 있으면 그걸 재사용해서, 메인 탭
#    코드가 아예 실행되지 않았다. Phase 1·2 를 써본 사람은 전부 그 상태다 —
#    갱신해도 화면이 옛 자리에 그대로 있다(2026-08-22 실물 확인).
#    사이드에 있는 뷰는 재사용하지 않고 옮긴다.
t_contains "사이드에 있으면 옮긴다" "isMainLeaf" "$(cat "$JS" "$RMJS" "$CMDJS")"
# ⚠️ 함수가 있는 것과 '쓰는' 것은 다르다. activate 가 실제로 걸러야 한다.
t_contains "activate 가 메인을 고른다" "isMainLeaf(l, workspace.rootSplit)" "$(cat "$JS" "$RMJS" "$CMDJS")"
# 아무 leaf 나 재사용하면 사이드에 남은 옛 뷰가 이긴다.
t_eq "아무 leaf 나 재사용하지 않는다" "0" \
  "$(grep -c 'revealLeaf(open\[0\])' "$JS" | tr -d ' ')"
# 사이드에 남은 것은 닫아야 같은 화면이 둘이 되지 않는다.
t_contains "남은 뷰를 닫는다" "l.detach()" "$(cat "$JS" "$RMJS" "$CMDJS")"

# ⚠️ 회귀: Obsidian 은 시작할 때 workspace.json 의 레이아웃을 복원한다.
#    예전 버전이 사이드독에 열어둔 뷰가 거기 저장돼 있어서, 재시작하면
#    activate() 를 거치지 않고 사이드에 그대로 되살아난다.
#    실측: workspace.json 의 right 에 뷰가 1개 있었다(2026-08-22).
#    레이아웃이 준비되면 스스로 옮겨야 한다.
t_contains "레이아웃 준비 후 정리한다" "onLayoutReady" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "복원된 사이드 뷰를 옮긴다" "relocateIfSide" "$(cat "$JS" "$RMJS" "$CMDJS")"

cat > "$T_TMP/leaf.js" <<'JSEOF'
const Module = require('module'); const orig = Module._load;
Module._load = (r,p,m) => r === 'obsidian' ? { Plugin: class{}, ItemView: class{}, Modal: class { constructor() {} } } : orig(r,p,m);
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
  t_contains "지표 $k" "$k" "$(cat "$JS" "$RMJS" "$CMDJS")"
done
t_eq "meeting 을 세지 않는다" "0" "$(grep -cE "'meeting'|\"meeting\"" "$JS" | tr -d ' ')"
t_eq "event 를 세지 않는다"   "0" "$(grep -cE "'event'|\"event\"" "$JS" | tr -d ' ')"

# ── 레이아웃 ────────────────────────────────────────────────────────────────
t_start "전체 화면 레이아웃"
CSS="$ROOT/plugin/styles.css"
t_contains "기록 흐름 히트맵" "devtrail-cc-heat" "$(cat "$CSS")"
# ⚠️ 옛 3열 그리드(devtrail-cc-columns)는 없앴다 — 좌측 레일 + 중앙 보드의
#    작업 공간으로 바뀌었다.
t_contains "2단 배치"  "devtrail-cc-grid-2" "$(cat "$CSS")"
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
t_contains "플러그인이 그 명령을 만든다" "id: 'open'" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_ne "단축키가 배정된다" "null" "$(jq -r --arg c "$CCID" '.[$c]' "$T_TMP/hk-out.json")"

# ⚠️ 외부 플러그인 명령은 스펙에 박지 않는다. 설치 여부도, 명령 id 도
#    실행 시점에만 알 수 있다.
t_eq "Omnisearch 를 스펙에 박지 않는다" "0" \
  "$(grep -ci 'omnisearch' "$HKSPEC" | tr -d ' ')"

t_start "검색: 없으면 안내만 한다"
# (d) Omnisearch 가 없으면 버튼이 안전하게 비활성화되고 안내가 뜬다
# ⚠️ 옛 계약은 'id 로 시작하는 첫 명령' 이었다. 그건 인덱스 재생성 같은 것을
#    검색 버튼에 물릴 수 있어 바꿨다 — 이름과 접미사를 함께 본다.
t_contains "검색 명령을 가려서 찾는다" "findSearchCommand" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "명령 id 를 하드코딩하지 않는다" "0" \
  "$(grep -cE \"omnisearch:[a-z-]+\" "$JS" | tr -d ' ')"
t_contains "설치 안내 문구가 있다" "searchMissing" "$(cat "$JS" "$RMJS" "$CMDJS")"

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
# ⚠️ 전역 폰트만 금지한다. 디자인 핸드오프는 숫자·날짜·태그에 mono 를
#    요구하고, 그건 테마가 이미 가진 --font-monospace 다 — 남의 폰트를
#    강제하는 게 아니라 테마의 것을 고르는 것이다.
t_eq "폰트를 강제하지 않는다" "0" \
  "$(grep -E 'font-family' "$CSS" | grep -vc 'var(--font-' | tr -d ' ')"
t_eq "전역에 폰트를 걸지 않는다" "0" \
  "$(grep -B2 'font-family' "$CSS" | grep -cE '^(body|:root|html|\*)' | tr -d ' ')"

t_start "상태를 색으로만 말하지 않는다"
# ⚠️ 설계안 §3: 색만으로 신호하지 않는다. 색을 못 보는 사람이 있다.
#    배지는 글자를 갖고, 비활성 버튼은 title 로 이유를 말한다.
t_contains "배지에 글자가 있다" "devtrail-cc-badge" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "비활성 이유를 title 로" "setAttr('title'" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "접근성"
t_contains "포커스가 보인다" "focus-visible" "$(cat "$CSS")"
t_contains "네비에 aria-label" "aria-label" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "현재 탭을 알린다" "aria-current" "$(cat "$JS" "$RMJS" "$CMDJS")"
# ⚠️ 움직임에 민감한 사람이 있다. 애니메이션을 넣었다면 끌 수 있어야 한다.
# ⚠️ 블록이 '있다' 와 '듣는다' 는 다르다. 같은 특정도라면 **나중 규칙이 이긴다** —
#    감소된 모션 블록이 transition 선언보다 앞에 있으면 아무 효과가 없다.
#    2026-08-22 에 실제로 그랬고, 개수만 세던 이 검사는 그것을 못 봤다.
# ⚠️ 디자인 핸드오프(2026-08-22): "애니메이션 없음. transition 없음."
#    움직이는 것이 없으면 줄일 모션도 없다 — 블록 자체가 필요 없다.
#    (예전엔 블록이 transition 선언보다 앞에 있어 아무 효과가 없었다.
#     같은 함정을 다시 만들지 않으려면 애초에 움직이지 않는 게 낫다.)
t_eq "움직이지 않는다" "0" "$(grep -c 'transition:' "$CSS" | tr -d ' ')"
t_eq "animation 도 없다" "0" "$(grep -cE '^\s*animation:' "$CSS" | tr -d ' ')"

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
# ⚠️ L 은 CLI 안에서만 사는 함수다. 테스트에서 부르면 빈 문자열이 되어
#    단언이 공허하게 통과한다 — 실제 문구를 그대로 적는다.
t_contains "최신이라고 말한다" "최신입니다" "$out2"

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
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
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
  t_eq "별칭이 옳은 컬럼으로 간다" "OK" "$(node "$T_TMP/stage.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "보드가 네 컬럼과 미지정을 갖는다"
t_contains "컬럼 정의" "BOARD_COLUMNS" "$(cat "$JS" "$RMJS" "$CMDJS")"
for k in planning active blocked done; do
  t_contains "컬럼 $k" "'$k'" "$(cat "$JS" "$RMJS" "$CMDJS")"
done
# ⚠️ 미지정은 다섯 번째 컬럼이 아니라 별도 영역이다 — 상태가 아니라 '빠진 것' 이다.
t_contains "미지정을 따로 다룬다" "unstaged" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "컬럼은 넷이다" "4" \
  "$(grep -A8 'BOARD_COLUMNS = \[' "$RMJS" | grep -c "^\s*\['")"

t_start "카드가 노트에서 읽은 것만 보여준다"
t_contains "프로젝트명" "p.name" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "next_action" "p.next" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "마지막 수정" "p.file.stat.mtime" "$(cat "$JS" "$RMJS" "$CMDJS")"
# 카드 전체가 눌린다 — 링크만 누르게 하면 표적이 너무 작다.
# ⚠️ 'Enter' 문구는 최근 기록 행에도 있다. 존재만 보면 카드에서 빼도 통과한다 —
#    카드 함수 안에 있는지를 본다.
t_contains "카드를 키보드로 연다" "ev.key === 'Enter'" \
  "$(sed -n '/projectCard(parent, t, p, colKey)/,/^  }/p' "$JS")"
t_contains "카드 전체가 눌린다" "c.addEventListener('click', open)" \
  "$(sed -n '/projectCard(parent, t, p, colKey)/,/^  }/p' "$JS")"
t_contains "빈 컬럼 문구" "emptyColumn" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "노트를 쓰지 않는다"
# ⚠️ 플러그인은 읽기 모델이다. 쓰기는 Templater 통로 하나뿐이다.
for m in "vault.create" "vault.modify" "vault.append" "processFrontMatter"; do
  t_eq "$m 를 부르지 않는다" "0" "$(grep -c "$m" "$JS" | tr -d ' ')"
done
t_start "쓰는 문구가 전부 정의돼 있다"
# ⚠️ t.lastEdit 이 정의 없이 쓰여 화면에 'undefined 2026. 8. 22.' 가 떴다.
#    문구는 ko·en 양쪽에 다 있어야 한다 — 한쪽만 있으면 다른 언어에서 깨진다.
cat > "$T_TMP/i18n.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const fs = require('fs');
const T = require(process.argv[2]).__test.TEXT;
if (!T || !T.ko || !T.en) { console.log('NOHOOK'); process.exit(0); }
const src = fs.readFileSync(process.argv[2], 'utf8');
const used = new Set([...src.matchAll(/\bt\.([a-zA-Z][a-zA-Z0-9]*)/g)].map((m) => m[1]));
const bad = [];
for (const k of used) {
  if (T.ko[k] === undefined) bad.push('ko:' + k);
  if (T.en[k] === undefined) bad.push('en:' + k);
}
console.log(bad.length === 0 ? 'OK' : 'MISSING ' + bad.join(' '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "정의 없는 문구가 없다" "OK" "$(node "$T_TMP/i18n.js" "$JS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "CSS 클래스가 두 번 선언되지 않는다"
# ⚠️ .devtrail-cc-card 를 보드 카드에도 쓰는 바람에 뒤 선언이 홈 카드를 뒤집어
#    지표가 잘리고 열이 겹쳤다. 같은 이름을 두 곳에 쓰면 뒤가 이긴다.
# ⚠️ 처음엔 ^\.devtrail-cc-[a-z-]+ \{ 만 봤다. 그래서 .devtrail-command-center
#    (접두사가 다르다) 와 .devtrail-cc-header h2 (자손 선택자) 의 중복을
#    놓쳤고, 루트 블록이 두 번 선언된 채로 지나갔다. 선택자 전부를 본다.
t_eq "중복 선언이 없다" "" \
  "$(_run_py "_pyck3" "$CSS")"
# --- _pyck3 ---
t_start "버전을 SemVer 로 비교한다"
cat > "$T_TMP/sv.sh" <<'SHEOF'
. "$1/lib/common.sh" >/dev/null 2>&1 || true
. "$1/lib/commandcentercmd.sh"
bad=0
chk() { got=$(_cc_semver_cmp "$1" "$2"); [ "$got" = "$3" ] || { echo "MISMATCH $1 $2 want $3 got $got"; bad=1; }; }
chk 1.0.0 1.0.0 0
chk 1.0.1 1.0.0 1
chk 1.0.0 1.0.1 -1
chk 1.10.0 1.9.0 1        # 문자열 비교였다면 틀린다
chk 0.2.10 0.2.9 1
chk 2.0.0 1.99.99 1
chk 1.2 1.2.0 0           # 자리가 모자라면 0 으로 채운다
[ $bad = 0 ] && echo OK || echo FAIL
SHEOF
t_eq "자릿수를 숫자로 본다" "OK" "$(bash "$T_TMP/sv.sh" "$ROOT" 2>&1 | tail -1)"

t_start "다운그레이드하지 않는다"
VD=$(_vault vd); HD="$T_TMP/hd"; _cfg "$VD" "$HD"
DEVTRAIL_HOME="$HD" DEVTRAIL_CONFIG="$HD/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1
# 설치본을 저장소보다 새 버전으로 만든다.
python3 - "$VD/.obsidian/plugins/$PID/manifest.json" <<'PYEOF'
import json, io, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding='utf-8')); d['version'] = '99.0.0'
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
keep=$(md5 -q "$VD/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VD/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
out=$(DEVTRAIL_HOME="$HD" DEVTRAIL_CONFIG="$HD/devtrail.config.json" \
      "$DT" command-center update --apply 2>&1)
now=$(md5 -q "$VD/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VD/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
t_eq "설치본이 더 새로우면 안 바꾼다" "$keep" "$now"
t_eq "버전도 그대로" "99.0.0" "$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")"
t_contains "왜 안 바꿨는지 말한다" "설치본이 더 새롭" "$out"
st=$(DEVTRAIL_HOME="$HD" DEVTRAIL_CONFIG="$HD/devtrail.config.json" \
     "$DT" command-center status --json 2>/dev/null)
printf '%s' "$st" > "$T_TMP/newer.json"
t_eq "status 가 사실대로 말한다" "installed_newer" \
  "$(jq -r '.update_state' "$T_TMP/newer.json")"
t_eq "업데이트 있다고 하지 않는다" "false" \
  "$(jq -r '.update_available | tostring' "$T_TMP/newer.json")"

t_start "version 없는 원본을 거부한다"
NOV="$T_TMP/nover"; mkdir -p "$NOV"
printf '%s' '{"id":"devtrail-command-center","name":"x"}' > "$NOV/manifest.json"
cp "$ROOT/plugin/main.js" "$NOV/main.js"; cp "$ROOT/plugin/styles.css" "$NOV/styles.css"
keep2=$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")
out=$(DT_CC_SRC_OVERRIDE="$NOV" DEVTRAIL_HOME="$HD" \
      DEVTRAIL_CONFIG="$HD/devtrail.config.json" "$DT" command-center update --apply 2>&1)
t_eq "설치본을 건드리지 않는다" "$keep2" \
  "$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")"
t_contains "version 이 없다고 말한다" "version" "$out"

t_start "깨진 JSON 원본을 거부한다"
BJ="$T_TMP/badjson"; mkdir -p "$BJ"
printf '%s' '{"id": broken' > "$BJ/manifest.json"
cp "$ROOT/plugin/main.js" "$BJ/main.js"; cp "$ROOT/plugin/styles.css" "$BJ/styles.css"
out=$(DT_CC_SRC_OVERRIDE="$BJ" DEVTRAIL_HOME="$HD" \
      DEVTRAIL_CONFIG="$HD/devtrail.config.json" "$DT" command-center update --apply 2>&1)
t_eq "여전히 그대로" "$keep2" \
  "$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")"

t_start "부분 업데이트가 남지 않는다"
# ⚠️ 필수 파일 하나가 없는 원본. manifest 만 새 버전으로 갈아치우고 끝나면
#    Obsidian 이 새 manifest + 옛 코드를 로드한다 — 아무도 모르는 상태다.
HALF="$T_TMP/half"; mkdir -p "$HALF"
python3 - "$ROOT/plugin/manifest.json" "$HALF/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '99.99.99'
json.dump(d, io.open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
cp "$ROOT/plugin/main.js" "$HALF/main.js"   # styles.css 를 일부러 빼둔다
before=$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")
out=$(DT_CC_SRC_OVERRIDE="$HALF" DEVTRAIL_HOME="$HD" \
      DEVTRAIL_CONFIG="$HD/devtrail.config.json" "$DT" command-center update --apply 2>&1)
t_eq "manifest 가 앞서 나가지 않는다" "$before" \
  "$(jq -r .version "$VD/.obsidian/plugins/$PID/manifest.json")"
t_eq "styles.css 가 남아 있다" "yes" \
  "$([ -f "$VD/.obsidian/plugins/$PID/styles.css" ] && echo yes || echo no)"

t_start "undo 가 신규 파일까지 지운다"
VN2=$(_vault vn2); HN2="$T_TMP/hn2"; _cfg "$VN2" "$HN2"
DEVTRAIL_HOME="$HN2" DEVTRAIL_CONFIG="$HN2/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1
python3 - "$VN2/.obsidian/plugins/$PID/manifest.json" <<'PYEOF'
import json, io, sys
p = sys.argv[1]; d = json.load(io.open(p, encoding='utf-8')); d['version'] = '0.0.1'
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
# 새 릴리스가 파일 하나를 더 들고 온다.
NEWSRC="$T_TMP/newsrc"; mkdir -p "$NEWSRC"
# ⚠️ 파일 이름을 손으로 적지 않는다. 목록에서 복사한다 — 모듈이 늘 때마다
#    고정물을 고쳐야 하면, 언젠가 안 고쳐서 엉뚱한 이유로 빨간불이 뜬다.
for f in $(jq -r '.files[]' "$ROOT/plugin/files.json"); do cp "$ROOT/plugin/$f" "$NEWSRC/$f"; done
printf '/* 새 릴리스가 들고 온 파일 */
' > "$NEWSRC/extra.js"
# ⚠️ 목록도 함께 바꾼다. 배포물은 files.json 이 정한다 — 환경변수로
#    갈아끼우던 길(DT_CC_FILES_OVERRIDE)은 없앴다.
jq '.files += ["extra.js"]' "$ROOT/plugin/files.json" > "$NEWSRC/files.json"
oldjs=$(md5 -q "$VN2/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VN2/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)
DT_CC_SRC_OVERRIDE="$NEWSRC" DEVTRAIL_HOME="$HN2" DEVTRAIL_CONFIG="$HN2/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "새 파일이 들어왔다" "yes" \
  "$([ -f "$VN2/.obsidian/plugins/$PID/extra.js" ] && echo yes || echo no)"
job=$(ls -1 "$HN2/journal" | tail -1)
DEVTRAIL_HOME="$HN2" DEVTRAIL_CONFIG="$HN2/devtrail.config.json" \
  "$DT" undo "$job" --apply >/dev/null 2>&1
# ⚠️ 저널이 생겼는지가 아니라, undo 가 실제로 되돌렸는지를 본다.
t_eq "undo 가 새 파일을 지운다" "no" \
  "$([ -f "$VN2/.obsidian/plugins/$PID/extra.js" ] && echo yes || echo no)"
t_eq "기존 파일이 이전 내용으로 돌아온다" "$oldjs" \
  "$(md5 -q "$VN2/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VN2/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)"
t_eq "버전도 되돌아온다" "0.0.1" \
  "$(jq -r .version "$VN2/.obsidian/plugins/$PID/manifest.json")"
t_start "빈 체크박스를 할 일로 세지 않는다"
cat > "$T_TMP/tasks.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.openTasks !== 'function') { console.log('NOHOOK'); process.exit(0); }
const raw = [
  '# 오늘',
  '- [ ] ',            // 템플릿 자리표시 — 글자 없음
  '- [ ]',             // 공백조차 없음
  '- [ ] 로그인 버그 고치기',
  '- [x] 이미 끝낸 것',
  '  - [ ] 들여쓴 할 일',
  '- [ ]    ',         // 공백만
].join('\n');
const got = f.openTasks(raw);
const want = ['로그인 버그 고치기', '들여쓴 할 일'];
console.log(JSON.stringify(got) === JSON.stringify(want)
  ? 'OK' : 'GOT ' + JSON.stringify(got));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "글자 있는 것만 센다" "OK" "$(node "$T_TMP/tasks.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi
# ⚠️ 이제 볼트 전체에서 모은다 — 그 함수가 openTasks 를 쓴다.
t_contains "볼트 전체 수집이 그 함수를 쓴다" "openTasks(raw)" \
  "$(sed -n '/async function openTasksInVault/,/^}/p' "$RMJS")"

t_start "빈 컬럼이 늘어나지 않는다"
# ⚠️ 계획 중에 카드 4장, 나머지가 0 이면 빈 컬럼이 네 배 높이로 늘어난다.
#    한 줄짜리 안내가 500px 를 차지하면 화면이 망가져 보인다.
t_contains "컬럼이 내용 높이를 갖는다" "align-items: start" \
  "$(sed -n '/^\.devtrail-cc-board {/,/^}/p' "$CSS")"

# ── 거부는 실패로 끝나야 한다 ───────────────────────────────────────────────
#
# ⚠️ die 를 명령 치환 $( ) 안에서 부르면 서브셸만 죽는다. 호출한 쪽은 아무 일도
#    없던 것처럼 계속 실행되고 종료 코드 0 으로 끝난다 — 자동화도 사람도
#    "안전하게 거부됐다" 고 잘못 읽는다.
#
#    이 저장소는 같은 결함을 setup 의 sp_validate 에서 이미 한 번 고쳤다.
#    메시지만 보는 테스트는 이것을 못 잡는다 — 종료 코드를 봐야 한다.
t_start "잘못된 원본은 실패 코드로 끝난다"
VX=$(_vault vx); HX="$T_TMP/hx"; _cfg "$VX" "$HX"
DEVTRAIL_HOME="$HX" DEVTRAIL_CONFIG="$HX/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1
ref=$(md5 -q "$VX/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VX/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)

_bad_src() {
  # $1 = 이름, $2 = manifest 내용, $3 = 파일을 빼면 그 이름
  local d="$T_TMP/bad-$1"; mkdir -p "$d"
  printf '%s' "$2" > "$d/manifest.json"
  cp "$ROOT/plugin/main.js" "$d/main.js"
  [ "$3" = "styles.css" ] || cp "$ROOT/plugin/styles.css" "$d/styles.css"
  # ⚠️ 배포 목록은 항상 넣는다. 목록이 없으면 '목록 없음' 으로 거부되어
  #    정작 시험하려던 것(파일 누락·id 불일치)을 못 본다.
  cp "$ROOT/plugin/files.json" "$d/files.json"
  printf '%s' "$d"
}

for c in \
  "version없음:{\"id\":\"$PID\",\"name\":\"x\"}:" \
  "깨진JSON:{\"id\": broken:" \
  "id불일치:{\"id\":\"someone-else\",\"version\":\"9.9.9\"}:" \
  ; do
  name=${c%%:*}; rest=${c#*:}; body=${rest%:*}
  src=$(_bad_src "$name" "$body" "")
  DT_CC_SRC_OVERRIDE="$src" DEVTRAIL_HOME="$HX" \
    DEVTRAIL_CONFIG="$HX/devtrail.config.json" \
    "$DT" command-center update --apply >/dev/null 2>&1
  t_ne "$name — 0 으로 끝나지 않는다" "0" "$?"
  t_eq "$name — 설치본 그대로" "$ref" \
    "$(md5 -q "$VX/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VX/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)"
done

# 필수 파일 누락도 같다.
src=$(_bad_src "파일누락" "$(cat "$ROOT/plugin/manifest.json")" "styles.css")
DT_CC_SRC_OVERRIDE="$src" DEVTRAIL_HOME="$HX" \
  DEVTRAIL_CONFIG="$HX/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_ne "파일누락 — 0 으로 끝나지 않는다" "0" "$?"
t_eq "파일누락 — 설치본 그대로" "$ref" \
  "$(md5 -q "$VX/.obsidian/plugins/$PID/main.js" 2>/dev/null || md5sum "$VX/.obsidian/plugins/$PID/main.js" | cut -d' ' -f1)"

# 정상 원본은 0 으로 끝난다 — 게이트가 무조건 실패시키는 게 아니어야 한다.
DEVTRAIL_HOME="$HX" DEVTRAIL_CONFIG="$HX/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "정상 원본은 0 으로 끝난다" "0" "$?"

# ── 설계 계약 ──────────────────────────────────────────────────────────────
#
# 대시보드는 읽는 물건이 아니라 훑는 물건이다. 글줄 길이를 위해 폭을 자르면
# 넓은 화면에서 오른쪽이 통째로 죽는다 — 카드가 스스로 폭을 제한한다.
t_start "대시보드가 주어진 폭을 쓴다"
t_eq "본문에 폭 상한이 없다" "0" \
  "$(sed -n '/^\.devtrail-cc-body/,/}/p' "$CSS" | grep -c 'max-width')"
t_start "여백이 하나의 리듬을 따른다"
# ⚠️ 4·6·8·10·12·16 이 섞이면 무엇이 한 묶음인지 눈이 못 읽는다.
#    4 의 배수 하나로 통일한다.
# ⚠️ 디자인 핸드오프(2026-08-22)가 쓰는 눈금이 정본이다:
#    2 4 6 7 8 10 12 14 16 18 20 24 28 40 56
#    그 밖의 값이 끼면 "왜 이 간격인가" 를 아무도 답할 수 없게 된다.
odd=$(grep -oE '(padding|gap|margin[a-z-]*): *[0-9]+px' "$CSS" \
      | grep -oE '[0-9]+' \
      | grep -vxE '1|2|4|6|7|8|10|12|14|16|18|20|24|28|40|56' | sort -u | tr '\n' ' ')
t_eq "핸드오프의 눈금만 쓴다" "" "$odd"

t_start "최근 기록이 한 줄로 늘어지지 않는다"
# ⚠️ 폭 상한을 풀었으므로 목록 한 줄이 화면 끝까지 늘어난다 — 이름은 왼쪽,
#    배지는 저 멀리 오른쪽이 되어 둘을 잇는 눈길이 끊긴다. 여러 열로 접는다.
t_contains "여러 열로 나눈다" "devtrail-cc-recent" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "CSS 가 열을 만든다" "auto-fit" \
  "$(sed -n '/^\.devtrail-cc-recent {/,/^}/p' "$CSS")"

# ── 탭과 동작을 형태로 가른다 ───────────────────────────────────────────────
#
# ⚠️ 위 줄은 노트를 만들고 아래 줄은 화면을 바꾼다. 둘이 똑같이 생기면
#    사용자는 누르기 전까지 무엇이 일어날지 모른다 — 위계가 아니라 종류가
#    다르므로 형태로 갈라야 한다.
# CSS 한 블록을 떼어낸다.
#
# ⚠️ 이중따옴표 안의 {…} 는 브레이스 확장에 걸린다 — "/^\.$sel {/,/^}/p" 가
#    "//p" 와 "/^/p" 두 개로 쪼개져 sed 가 죽는다. 그러면 결과가 빈 문자열이
#    되고, 개수를 세는 단언은 0 을 얻어 **조용히 통과**한다.
#    문자 클래스 [{] [}] 로 감싸 확장을 막고, 비면 그 자리에서 실패시킨다.
_css_block() {
  local sel="$1" out
  out=$(sed -n "/^\.${sel} [{]/,/^[}]/p" "$CSS")
  if [ -z "$out" ]; then
    _t_bad "CSS 블록 .$sel" "그런 블록이 없습니다 — 단언이 아무것도 검사하지 못합니다"
    return 1
  fi
  printf '%s' "$out"
}

t_start "탭이 알약이 아니다"
TAB="$(sed -n '/^\.devtrail-cc-tab {/,/^}/p' "$CSS")"
t_contains "배경 없이 둔다" "background: none" "$TAB"
t_contains "현재 탭에 밑줄" "border-bottom" \
  "$(sed -n '/^\.devtrail-cc-tab.is-active {/,/^}/p' "$CSS")"

t_start "기록 탭을 없앤다"
# ⚠️ 빠른 실행 바가 같은 6개를 항상 보여준다. 같은 일을 두 곳에서 하면
#    한쪽만 고쳐지고, 사용자는 어느 쪽이 진짜인지 모른다.
t_eq "탭은 넷이다" "4" "$(sed -n "/const items = \[/,/\];/p" "$JS" | grep -c "^      \['")"
t_eq "capture 라우트가 없다" "0" "$(grep -c "route === 'capture'" "$JS")"
t_eq "viewCapture 가 없다" "0" "$(grep -c 'viewCapture' "$JS")"

t_start "아이콘이 겹치지 않는다"
# ⚠️ 같은 그림이 두 가지를 뜻하면 그림이 아무것도 뜻하지 않게 된다.
# 나란히 놓인 두 줄 안에서만 본다. 지표가 같은 개념에 같은 아이콘을 쓰는 것은
# 충돌이 아니라 일관성이다 — 개발일지 지표와 개발일지 버튼은 같은 것을 가리킨다.
NAVICONS=$(sed -n '/const items = \[/,/\];/p' "$JS" | grep -oE "'[a-z0-9-]+'\]" | tr -d "']")
LAUNCHICONS=$(sed -n '/const icons = {/,/};/p' "$JS" | grep -oE ": '[a-z0-9-]+'" | sed "s/: '//;s/'//")
dup=$(printf '%s\n%s\n' "$NAVICONS" "$LAUNCHICONS" | grep -v '^$' | sort | uniq -d | tr '\n' ' ')
t_eq "탭과 동작이 같은 그림을 쓰지 않는다" "" "$dup"
t_start "여백을 부모가 준다"
# ⚠️ 각 구역이 자기 margin-bottom 을 들고 있으면 하나가 빠졌을 때 그 구역만
#    아래와 붙는다. 2026-08-22 에 빠른 실행 바가 지표와 겹쳐 보인 이유다.
#    부모가 gap 으로 리듬을 주면 빠뜨릴 자리가 없다.
t_contains "루트가 세로 flex" "flex-direction: column" \
  "$(sed -n '/^\.devtrail-command-center {/,/^}/p' "$CSS")"
t_contains "루트가 gap 을 준다" "gap:" \
  "$(sed -n '/^\.devtrail-command-center {/,/^}/p' "$CSS")"
t_contains "본문도 세로 flex" "flex-direction: column" \
  "$(sed -n '/^\.devtrail-cc-body {/,/^}/p' "$CSS")"

# 최상위 구역들은 세로 margin 을 스스로 갖지 않는다.
stray=""
for sel in devtrail-cc-header devtrail-cc-nav devtrail-cc-panel \
           devtrail-cc-section devtrail-cc-grid-2; do
  m=$(_css_block "$sel" | grep -cE "margin-(top|bottom):")
  [ "$m" = "0" ] || stray="$stray $sel"
done
t_eq "구역이 세로 여백을 들고 있지 않다" "" "$stray"

t_start "죽은 CSS 선언이 없다"
# ⚠️ 한 블록에 같은 속성이 두 번 있으면 앞의 것은 죽은 선언이다. 읽는 사람은
#    앞의 값이 쓰인다고 믿는다 — 블록을 합칠 때 실제로 생겼다.
t_eq "같은 속성을 두 번 쓰지 않는다" "" \
  "$(_run_py "_pyck4" "$CSS")"
# --- _pyck4 ---
# ⚠️ 쓰이지 않는 클래스는 지운다 — 남겨두면 다음 사람이 살아 있다고 믿는다.
t_eq "쓰이지 않는 클래스가 없다" "" \
  "$(for c in $(grep -oE '^\.devtrail-cc-[a-z-]+ [{]' "$CSS" | sed 's/^\.//;s/ [{]//' | sort -u); do
       # ⚠️ JS 가 `devtrail-cc-col--${key}` 처럼 조립하는 이름이 있다.
       # 전체 이름이 없으면 -- 앞 접두사가 쓰이는지 본다.
       grep -q "$c" "$JS" && continue
       # ⚠️ $( ) 안의 case 는 패턴을 (패턴) 으로 감싸야 한다 — 닫는 ) 가
       #    명령 치환을 끊는다.
       # ⚠️ JS 가 `devtrail-cc-lv${l}` · `devtrail-cc-stage-${key}` 처럼
       #    조립하는 이름이 있다. 마지막 조각을 떼고 접두사로도 찾는다.
       case "$c" in
         (*--*) grep -q "${c%%--*}--" "$JS" && continue ;;
       esac
       stem=$(printf '%s' "$c" | sed 's/[0-9]*$//; s/-[a-z0-9]*$/-/')
       grep -q "$stem" "$JS" && continue
       printf '%s ' "$c"
     done)"
t_start "기록 흐름을 센다"
cat > "$T_TMP/flow.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.buildFlow !== 'function') { console.log('NOHOOK'); process.exit(0); }
const DAY = 86400000;
const base = Date.UTC(2026, 7, 22);               // 2026-08-22 토
const mk = (daysAgo, n) => Array.from({ length: n }, () => ({ ctime: base - daysAgo * DAY }));
const files = [].concat(mk(0, 3), mk(1, 1), mk(2, 2), mk(10, 5), mk(90, 4));
const flow = f.buildFlow(files, base, 12);
const bad = [];
// 84일(12주) 격자. 그보다 오래된 것은 들어오지 않는다.
if (flow.cells.length !== 84) bad.push('cells=' + flow.cells.length);
if (flow.cells[flow.cells.length - 1].count !== 3) bad.push('today=' + flow.cells[flow.cells.length - 1].count);
if (flow.total !== 11) bad.push('total=' + flow.total);   // 90일 전 4건은 빠진다
// 연속 기록: 오늘·어제·그제 = 3
if (flow.streak !== 3) bad.push('streak=' + flow.streak);
// 강도는 0~4 다섯 단계.
const lv = flow.cells.map((c) => c.level);
if (Math.min(...lv) < 0 || Math.max(...lv) > 4) bad.push('level range');
if (flow.cells.find((c) => c.count === 0).level !== 0) bad.push('zero must be level 0');
// 요일별 평균 7개.
if (flow.byWeekday.length !== 7) bad.push('weekday=' + flow.byWeekday.length);
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
cat > "$T_TMP/tz.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.buildFlow !== 'function') { console.log('NOHOOK'); process.exit(0); }
// ⚠️ 서울(UTC+9) 기준 2026-08-22 새벽 1시에 만든 노트. UTC 로는 8/21 16시다.
//    UTC 로 자르면 이 노트가 '어제' 칸에 들어간다 — 한국에서 오전에 쓴 것이
//    전날로 밀린다. 로컬 자정이 기준이어야 한다.
const early = new Date(2026, 7, 22, 1, 0, 0).getTime();
const noon  = new Date(2026, 7, 22, 12, 0, 0).getTime();
const flow = f.buildFlow([{ ctime: early }], noon, 12);
const last = flow.cells[flow.cells.length - 1];
const prev = flow.cells[flow.cells.length - 2];
console.log(last.count === 1 && prev.count === 0 ? 'OK'
            : `today=${last.count} yesterday=${prev.count}`);
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "히트맵·연속·요일" "OK" "$(node "$T_TMP/flow.js" "$RMJS" 2>&1 | tail -1)"
  t_eq "로컬 자정으로 자른다" "OK" "$(TZ=Asia/Seoul node "$T_TMP/tz.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "방치 프로젝트를 가려낸다"
cat > "$T_TMP/stale.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.isStale !== 'function') { console.log('NOHOOK'); process.exit(0); }
const DAY = 86400000, now = Date.UTC(2026, 7, 22);
const bad = [];
// ⚠️ 기본 14일. 경계에서 흔들리면 안 된다 — 딱 14일은 아직 방치가 아니다.
if (f.isStale(now - 13 * DAY, now, 14)) bad.push('13일이 방치');
if (f.isStale(now - 14 * DAY, now, 14)) bad.push('14일이 방치');
if (!f.isStale(now - 15 * DAY, now, 14)) bad.push('15일이 방치가 아님');
if (!f.isStale(now - 31 * DAY, now, 14)) bad.push('31일이 방치가 아님');
// 수정 시각을 모르면 방치라고 단정하지 않는다.
if (f.isStale(null, now, 14)) bad.push('모르는데 방치라고 함');
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "14일 경계가 정확하다" "OK" "$(node "$T_TMP/stale.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "설정 두 개만 노출한다"
# ⚠️ 사양: "설정값 2개만 노출하면 충분합니다" — 방치 일수(14), 히트맵 주(12).
t_contains "방치 일수" "STALE_DAYS" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "히트맵 주" "FLOW_WEEKS" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "기본 14" "STALE_DAYS = 14" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "기본 12" "FLOW_WEEKS = 12" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "프로젝트 4주 스파크라인"
cat > "$T_TMP/spark.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.weeklyBars !== 'function') { console.log('NOHOOK'); process.exit(0); }
const DAY = 86400000;
const now = new Date(2026, 7, 22, 12).getTime();
const at = (d) => new Date(2026, 7, 22, 12).getTime() - d * DAY;
// 0~6일 전 = 이번 주(마지막 칸), 7~13 = 지난주, …
const bars = f.weeklyBars([at(1), at(2), at(8), at(22), at(40)], now, 4);
const bad = [];
if (bars.length !== 4) bad.push('len=' + bars.length);
if (bars[3] !== 2) bad.push('이번주=' + bars[3]);   // 1일·2일 전
if (bars[2] !== 1) bad.push('지난주=' + bars[2]);   // 8일 전
if (bars[1] !== 0) bad.push('2주전=' + bars[1]);
if (bars[0] !== 1) bad.push('3주전=' + bars[0]);    // 22일 전 (21~27 구간)
// 40일 전은 4주 밖이라 들어오지 않는다.
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "주 단위로 나눈다" "OK" "$(node "$T_TMP/spark.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "기한을 읽되 지어내지 않는다"
cat > "$T_TMP/due.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.parseDue !== 'function') { console.log('NOHOOK'); process.exit(0); }
const bad = [];
const eq = (l, g, w) => { if (g !== w) bad.push(`${l}: want ${w} got ${g}`); };
eq('이모지', f.parseDue('로그인 고치기 📅 2026-08-25'), '2026-08-25');
eq('due 필드', f.parseDue('정리 [due:: 2026-08-25]'), '2026-08-25');
eq('due 콜론', f.parseDue('정리 due: 2026-08-25'), '2026-08-25');
// ⚠️ 없으면 없다. 오늘 날짜나 아무 날짜를 채워 넣지 않는다 —
//    지어낸 기한은 사람을 잘못된 급함으로 몰아붙인다.
eq('없음', f.parseDue('그냥 할 일'), null);
eq('날짜 아님', f.parseDue('버전 2026-99-99 확인'), null);
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "있는 것만 읽는다" "OK" "$(node "$T_TMP/due.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "시안이 요구한 요소가 다 있다"
# ⚠️ 처음 구현에서 여덟 개를 빠뜨렸다. 사양의 각 요소가 실제로 그려지는지 본다.
# ⚠️ 시안의 그 자리는 이제 로컬 필터가 아니라 전체 검색이다 (§1).
t_contains "상단 검색 입력" "devtrail-cc-searchinput" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "날짜 표시" "devtrail-cc-date" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "만들기 안내" "devtrail-cc-kbd" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "스파크라인" "devtrail-cc-spark" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "이어쓰기 버튼" "continueWrite" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "작업 전체 버튼" "allTasks" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "전체 보기" "seeAll" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "기한 라벨" "devtrail-cc-due" "$(cat "$JS" "$RMJS" "$CMDJS")"
# 표는 5열이다 — 스파크라인 자리가 있어야 한다.
t_contains "표가 5열" "1fr 84px 1fr 100px 96px" "$(cat "$CSS")"

t_start "할 일은 DevTrail 노트에서만 온다"
cat > "$T_TMP/tasksrc.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.bearsTasks !== 'function') { console.log('NOHOOK'); process.exit(0); }
const bad = [];
const eq = (l, g, w) => { if (g !== w) bad.push(`${l}: want ${w} got ${g}`); };

// ⚠️ type 이 없는 노트 = 가져온 레포 문서. 그 안의 체크박스는 설계안의
//    항목이지 사용자의 할 일이 아니다. 이 볼트에 그런 노트가 106개 있고
//    체크박스가 1200개 넘는다 — 세면 화면이 잡음으로 덮인다.
eq('type 없음', f.bearsTasks({}), false);
eq('type 빈값', f.bearsTasks({ type: '' }), false);

// 문서를 설명하는 노트도 아니다. "내 언어로 재작성했다" 는 사용법 안내의
// 확인 목록이지 할 일이 아니다.
eq('guide', f.bearsTasks({ type: 'guide' }), false);
eq('moc',   f.bearsTasks({ type: 'moc' }), false);
eq('doc',   f.bearsTasks({ type: 'doc' }), false);

// 사용자가 실제로 할 일을 적는 곳.
for (const t of ['devlog', 'todo', 'project-home', 'weekly-review', 'worklog', 'trouble']) {
  eq(t, f.bearsTasks({ type: t }), true);
}
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "문서의 체크박스를 세지 않는다" "OK" "$(node "$T_TMP/tasksrc.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi
t_contains "수집이 그 규칙을 쓴다" "bearsTasks(" \
  "$(sed -n '/async function openTasksInVault/,/^}/p' "$RMJS")"

# ── 상단 입력창은 전체 검색이다 ─────────────────────────────────────────────
#
# ⚠️ 지금까지는 화면에 이미 그려진 행만 거르는 로컬 필터였다. 사용자는
#    "제목, 태그로 거르기" 를 보고 볼트 전체를 찾을 거라 기대한다 — 기대와
#    동작이 어긋나면 그 자리는 없느니만 못하다.
t_start "상단 입력창이 전체 검색이다"
t_contains "전체 검색이라고 말한다" "searchPlaceholder" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "거르기라고 하지 않는다" "0" "$(grep -c '태그로 거르기' "$JS" | tr -d ' ')"
NAVSRC="$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS")"
# ⚠️ 날것의 Enter 를 보지 않는다 — 한글 조합 중의 Enter 는 실행이 아니다.
t_contains "Enter 로 실행한다" "isSubmitKey(ev)" "$NAVSRC"
# 검색 실행은 searchRunner 한 곳에 있고, nav 는 그것을 부른다.
t_contains "nav 가 실행기를 만든다" "searchRunner(this.app)" "$NAVSRC"
RESOLVE="$(sed -n '/^function searchRunner(app) {/,/^}/p' "$CMDJS")"
t_contains "검색 명령을 가려 찾는다" "findSearchCommand" "$RESOLVE"
t_contains "기본 검색으로 떨어진다" "CORE_SEARCH" "$RESOLVE"
t_contains "존재를 확인하고 부른다" "commandExists" "$RESOLVE"
# ⚠️ 둘 다 없어도 끄지 않는다 — 왜 안 되는지, 무엇을 하면 되는지 말한다.
t_contains "없으면 안내한다" "searchMissingHelp" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "명령 id 를 박지 않는다" "0" "$(grep -cE '"omnisearch:[a-z-]+"' "$JS" | tr -d ' ')"
# 검색은 아무것도 만들지 않는다.
t_eq "검색이 노트를 만들지 않는다" "0" \
  "$(printf '%s' "$NAVSRC" | grep -cE 'templaterCommandId|vault\.(create|modify)')"

t_start "로컬 필터를 전체 검색과 섞지 않는다"
# ⚠️ 한 입력창이 두 가지를 하면 사용자는 무엇이 일어날지 모른다.
#    이번 범위에서는 필터를 뺀다.
t_eq "필터 클래스가 없다" "0" "$(grep -c 'devtrail-cc-filter' "$JS" | tr -d ' ')"
t_eq "applyFilter 가 없다" "0" "$(grep -c 'applyFilter' "$JS" | tr -d ' ')"
t_eq "data-filter 도 없다" "0" "$(grep -c 'data-filter' "$JS" | tr -d ' ')"

# ── 전체 보기는 목록으로 간다 ───────────────────────────────────────────────
#
# ⚠️ 지금은 최신 노트 하나를 바로 열었다. 사용자는 목록을 기대하고 눌렀는데
#    갑자기 편집기가 열린다 — 무엇이 일어났는지 모르고, 되돌아갈 길도 모른다.
t_start "전체 보기가 목록을 연다"
SEEALL="$(sed -n '/const more = card.createEl/,/});/p' "$JS")"
t_eq "노트를 열지 않는다" "0" "$(printf '%s' "$SEEALL" | grep -c 'openFile')"
t_contains "라우트로 간다" "this.route = 'recent'" "$SEEALL"
t_contains "recent 라우트가 있다" "route === 'recent'" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "목록 화면의 계약"
VIEW="$(sed -n '/^  viewRecent(body, t, model) {/,/^  }/p' "$JS")"
t_ne "화면이 있다" "" "$VIEW"
# ⚠️ 큰 볼트에서 한 번에 다 그리면 화면이 멈춘다. 50개씩 늘린다.
t_contains "처음 50개" "RECENT_PAGE" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "기본 50" "RECENT_PAGE = 50" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "더 보기" "loadMore" "$VIEW"
# ⚠️ 더 보기를 눌러도 볼트를 다시 훑지 않는다 — 이미 모은 것에서 더 꺼낸다.
t_eq "다시 스캔하지 않는다" "0" \
  "$(printf '%s' "$VIEW" | grep -c 'getMarkdownFiles')"
t_contains "수정 시각 내림차순" "recentAll" "$VIEW"
t_contains "행마다 타입" "r.type" "$VIEW"
t_contains "행마다 경로" "r.file.path" "$VIEW"
t_contains "행마다 시각" "localDate(" "$VIEW"
t_contains "행에서만 연다" "openFile" "$VIEW"
t_contains "키보드로도 연다" "ev.key === 'Enter'" "$VIEW"
t_contains "돌아갈 길" "backHome" "$VIEW"

t_start "전체 목록이 전체를 담는다"
# ⚠️ 홈의 '최근 기록' 은 10개만 본다. 전체 보기가 그 10개만 보여주면
#    '전체' 가 거짓말이 된다.
# 축약 표기(recentAll,)로 넘긴다 — collect 가 실제로 만드는지 본다.
t_contains "모델이 전부를 싣는다" "const recentAll = files" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "반환에 실린다" "recentAll," "$(cat "$JS" "$RMJS" "$CMDJS")"
t_eq "홈은 여전히 10개" "1" "$(grep -c 'model.recent.slice(0, 10)' "$JS" | tr -d ' ')"

# ── 노트 만들기는 전용 선택창이다 ───────────────────────────────────────────
#
# ⚠️ 지금은 Obsidian 전체 명령 팔레트를 열었다. 빠른 기록을 하려는 사람에게
#    수백 개 명령을 보여주는 것은 도움이 아니다.
t_start "빠른 기록 선택창"
t_contains "모달을 연다" "QuickCaptureModal" "$(cat "$JS" "$RMJS" "$CMDJS")"
# ⚠️ 일반 명령 팔레트로 빠지지 않는다.
t_eq "팔레트를 열지 않는다" "0" \
  "$(grep -cE "command-palette|app\.setting\.open\(\)" "$JS" | tr -d ' ')"
MODAL="$(sed -n '/^class QuickCaptureModal/,/^}/p' "$JS")"
t_ne "모달이 있다" "" "$MODAL"
# 실제로 등록된 명령만 보여준다 — id 를 짐작하지 않는다.
t_contains "레지스트리를 확인한다" "commandExists" "$MODAL"
t_contains "Templater 로 조립한다" "templaterCommandId" "$MODAL"
t_contains "선택했을 때만 만든다" "executeCommandById" "$MODAL"
# 키보드
t_contains "위아래 이동" "ArrowDown" "$MODAL"
t_contains "Enter 실행" "'Enter'" "$MODAL"
t_contains "Esc 닫기" "close()" "$MODAL"
# 없을 때 안내
t_contains "없으면 이유를 말한다" "actionMissing" "$MODAL"
t_contains "설정 안내" "templaterMissing" "$(cat "$JS" "$RMJS" "$CMDJS")"
# 각 항목의 설명
t_contains "한 줄 설명" "captureHint" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "빠른 기록은 팔레트 대신이다"
NAVSRC2="$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS")"
t_contains "버튼이다" "devtrail-cc-make" "$NAVSRC2"
t_contains "눌러서 연다" "openQuickCapture" "$NAVSRC2"

t_start "날짜를 UTC 로 보여주지 않는다"
# ⚠️ toISOString() 은 UTC 다. 한국(UTC+9)에서 오전 9시 이전에 만든 노트가
#    전날 날짜로 보인다 — 사용자가 "어제 쓴 게 아닌데" 하고 화면을 의심한다.
#    히트맵 툴팁·aria-label 이 특히 그렇다.
# (주석의 설명은 세지 않는다 — 왜 안 쓰는지 적어 둔 자리다.)
t_eq "toISOString 을 쓰지 않는다" "0" \
  "$(grep 'toISOString' "$JS" | grep -vcE '^\s*(\*|//|/\*)' | tr -d ' ')"
t_contains "로컬 날짜 함수가 있다" "function localDate(ms)" "$(cat "$JS" "$RMJS" "$CMDJS")"
cat > "$T_TMP/tzdate.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.localDate !== 'function') { console.log('NOHOOK'); process.exit(0); }
// 서울 새벽 1시 = UTC 로는 전날 16시.
const early = new Date(2026, 7, 22, 1, 0, 0).getTime();
const utc = new Date(early).toISOString().slice(0, 10);
console.log(f.localDate(early) === '2026-08-22' && utc === '2026-08-21'
  ? 'OK' : `local=${f.localDate(early)} utc=${utc}`);
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "서울 새벽이 전날로 밀리지 않는다" "OK" \
    "$(TZ=Asia/Seoul node "$T_TMP/tzdate.js" "$RMJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "검색어가 실려 간다"
# ⚠️ 명령만 부르면 사용자가 친 글자가 버려진다. "devlog" 를 치고 Enter 를
#    눌렀는데 빈 검색창이 열리면, 사용자는 검색이 안 된다고 느낀다 —
#    2026-08-22 에 실제로 그랬다.
cat > "$T_TMP/searchq.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.searchRunner !== 'function') { console.log('NOHOOK'); process.exit(0); }
const bad = [];
let got = null;
// Obsidian 자신이 쓰는 관용구: getEnabledPluginById('global-search').openGlobalSearch(q)
const withCore = {
  internalPlugins: { getEnabledPluginById: (id) =>
    id === 'global-search' ? { openGlobalSearch: (q) => { got = q; } } : null },
  commands: { commands: {}, executeCommandById: () => { got = 'COMMAND'; } },
};
let r = f.searchRunner(withCore);
if (!r) bad.push('core 있는데 null');
else { r('devlog'); if (got !== 'devlog') bad.push('검색어가 안 실렸다: ' + got); }

// 검색어가 비면 그래도 검색 화면은 연다.
got = null; r(''); if (got !== '') bad.push('빈 검색어: ' + got);

// core 가 없고 Omnisearch 명령만 있으면 그것을 부른다(검색어는 못 싣는다).
got = null;
const withOmni = {
  internalPlugins: { getEnabledPluginById: () => null },
  commands: {
    commands: { 'omnisearch:show-modal': { id: 'omnisearch:show-modal', name: 'Vault search' } },
    executeCommandById: (id) => { got = id; },
  },
};
r = f.searchRunner(withOmni);
if (!r) bad.push('omnisearch 있는데 null');
else { r('devlog'); if (got !== 'omnisearch:show-modal') bad.push('omni: ' + got); }

// ⚠️ 둘 다 없으면 null 이다. 아무 명령이나 부르지 않는다.
if (f.searchRunner({ internalPlugins: { getEnabledPluginById: () => null },
                     commands: { commands: {} } }) !== null) bad.push('없는데 뭔가 부른다');
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "친 글자가 그대로 간다" "OK" "$(node "$T_TMP/searchq.js" "$CMDJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi
t_contains "화면이 그 실행기를 쓴다" "searchRunner(this.app)" "$(cat "$JS" "$RMJS" "$CMDJS")"

t_start "단축키 표시가 사실이어야 한다"
# ⚠️ 버튼 옆에 ⌘P 를 박아 뒀는데, ⌘P 는 Obsidian 의 **명령 팔레트** 단축키다.
#    그 버튼은 우리 모달을 여는데 표시는 다른 것을 가리켰다 — 눌러 보면
#    엉뚱한 게 열린다. 화면이 거짓을 말하면 사용자는 화면을 안 믿게 된다.
# ⚠️ 어떤 키캡도 손으로 박지 않는다. ⌘P 하나만 막으면 다음엔 ⌘K 를 박는다.
#    화면에 나오는 단축키는 전부 배정에서 읽어야 한다.
t_eq "키를 손으로 박지 않는다" "0" \
  "$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS" | grep -cE "'(⌘|⇧|⌥|⌃|Ctrl|Cmd)" | tr -d ' ')"
# 실제로 배정된 것을 읽는다 — Obsidian 이 그 API 를 갖고 있다.
t_contains "배정된 단축키를 읽는다" "printHotkeyForCommand" "$(cat "$JS" "$RMJS" "$CMDJS")"
t_contains "우리 명령을 등록한다" "quick-capture" "$(cat "$JS" "$RMJS" "$CMDJS")"
QC="$(sed -n "/quick-capture/,/});/p" "$JS")"
t_contains "그 명령이 모달을 연다" "openQuickCapture" "$QC"

cat > "$T_TMP/hk.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.hotkeyLabel !== 'function') { console.log('NOHOOK'); process.exit(0); }
const bad = [];
const app = (val) => ({ hotkeyManager: { printHotkeyForCommand: () => val } });
if (f.hotkeyLabel(app('⌘⇧U'), 'x') !== '⌘⇧U') bad.push('배정된 것을 못 읽는다');
// ⚠️ 안 배정됐으면 아무것도 보여주지 않는다. 있지도 않은 단축키를 적으면
//    사용자가 눌러 보고 화면을 의심한다.
if (f.hotkeyLabel(app(''), 'x') !== null) bad.push('빈 값인데 뭔가 보여준다');
if (f.hotkeyLabel(app(null), 'x') !== null) bad.push('null 인데 뭔가 보여준다');
if (f.hotkeyLabel({}, 'x') !== null) bad.push('API 없는데 뭔가 보여준다');
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "없으면 안 보여준다" "OK" "$(node "$T_TMP/hk.js" "$CMDJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi

t_start "빠른 기록에 기본 단축키가 있다"
t_contains "프리셋에 등록" "devtrail-command-center:quick-capture" \
  "$(cat "$ROOT/preset/obsidian/hotkeys.tmpl.json")"

# ── 코어 검색 켜기 ─────────────────────────────────────────────────────────
#
# ⚠️ 사용자의 Obsidian 설정을 우리가 건드리는 자리다. 규칙 하나로 못박는다:
#
#      키가 없다  → 정한 적 없다 → 켠다
#      false 다   → 끈 것이다   → **되돌리지 않는다**
#
#    "우리가 필요하니까" 로 남의 결정을 뒤집으면, 다음에 또 뒤집는다.
t_start "코어 검색은 정한 적 없을 때만 켠다"
CPV=$(_vault cp); CPH="$T_TMP/cph"; _cfg "$CPV" "$CPH"
cprun() { DEVTRAIL_HOME="$CPH" DEVTRAIL_CONFIG="$CPH/devtrail.config.json" "$DT" "$@"; }
CPF="$CPV/.obsidian/core-plugins.json"

# ① 파일이 없다 → 만들고 켠다
rm -f "$CPF"
cprun command-center install --apply >/dev/null 2>&1
t_eq "없으면 만들어 켠다" "true" "$(jq -r '."global-search" // false' "$CPF" 2>/dev/null)"

# ② 키가 없다 → 켠다. 다른 키는 건드리지 않는다.
printf '%s' '{"file-explorer":true,"graph":false}' > "$CPF"
cprun command-center install --apply >/dev/null 2>&1
t_eq "정한 적 없으면 켠다" "true" "$(jq -r '."global-search"' "$CPF")"
t_eq "남의 true 를 지키다" "true" "$(jq -r '."file-explorer"' "$CPF")"
t_eq "남의 false 도 지킨다" "false" "$(jq -r '."graph"' "$CPF")"

# ③ ⚠️ false 다 → 사용자가 끈 것이다. 되돌리지 않는다.
printf '%s' '{"global-search":false}' > "$CPF"
cprun command-center install --apply >/dev/null 2>&1
t_eq "끈 것을 되돌리지 않는다" "false" "$(jq -r '."global-search"' "$CPF")"

# ⑤ ⚠️ 옛 Obsidian 은 core-plugins.json 이 **배열**이다. 우리가 모르는 형식을
#    고쳐 쓰면 설정을 망가뜨린다 — 그대로 둔다.
printf '%s' '["file-explorer","graph"]' > "$CPF"
cprun command-center install --apply >/dev/null 2>&1
t_eq "배열은 건드리지 않는다" "true" \
  "$(jq -c '. == ["file-explorer","graph"]' "$CPF" 2>/dev/null)"

# ④ 되돌릴 수 있어야 한다
printf '%s' '{"file-explorer":true}' > "$CPF"
cprun command-center install --apply >/dev/null 2>&1
job=$(ls -1 "$CPH/journal" | tail -1)
cprun undo "$job" --apply >/dev/null 2>&1
t_eq "undo 로 원래대로" "null" "$(jq -r '."global-search" // "null"' "$CPF")"

t_start "검색창이 단축키를 알려준다"
# ⚠️ 여기도 손으로 박지 않는다. 사용자가 ⌘⇧F 를 다른 것으로 바꿨을 수 있고,
#    그러면 화면이 또 거짓을 말한다.
NAVSRC3="$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS")"
t_contains "검색 단축키도 읽는다" "hotkeyLabel(this.app, CORE_SEARCH)" "$NAVSRC3"
t_contains "입력창 안에 둔다" "devtrail-cc-searchkbd" "$NAVSRC3"
t_contains "CSS 도 있다" "devtrail-cc-searchkbd" "$(cat "$CSS")"
# 배정이 없으면 아무것도 안 보여준다 — hotkeyLabel 이 이미 그렇게 한다.
t_eq "검색창에도 키를 박지 않는다" "0" \
  "$(printf '%s' "$NAVSRC3" | grep -cE "'(⌘|⇧|⌥|⌃|Ctrl|Cmd)" | tr -d ' ')"

t_start "한글 조합 중의 Enter 는 실행이 아니다"
# ⚠️ 한글·일본어·중국어는 입력기(IME)가 글자를 **조합**한다. 조합 중에 누르는
#    Enter 는 "글자를 확정" 하라는 뜻이지 "실행하라" 가 아니다.
#    그것을 실행으로 받으면 아직 완성되지 않은 값이 넘어간다 —
#    2026-08-22 에 "가나" 를 치고 Enter 를 눌렀는데 엉뚱한 글자로 검색됐다.
#
#    영문만 쓰는 사람은 평생 못 만나는 버그다. 그래서 더 쉽게 놓친다.
cat > "$T_TMP/ime.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} } };
  return orig(r, p, m);
};
const f = require(process.argv[2]).__test;
if (!f || typeof f.isSubmitKey !== 'function') { console.log('NOHOOK'); process.exit(0); }
const bad = [];
const eq = (l, g, w) => { if (g !== w) bad.push(`${l}: want ${w} got ${g}`); };

// 조합이 끝난 Enter — 실행한다.
eq('평범한 Enter', f.isSubmitKey({ key: 'Enter' }), true);
eq('조합 끝남', f.isSubmitKey({ key: 'Enter', isComposing: false }), true);

// ⚠️ 조합 중 — 실행하지 않는다. 한 번 더 누르면 그때 실행된다.
eq('조합 중', f.isSubmitKey({ key: 'Enter', isComposing: true }), false);
// 일부 입력기·구형 경로는 isComposing 대신 keyCode 229 로 온다.
eq('keyCode 229', f.isSubmitKey({ key: 'Enter', keyCode: 229 }), false);
eq('둘 다', f.isSubmitKey({ key: 'Enter', isComposing: true, keyCode: 229 }), false);

// Enter 가 아니면 애초에 아니다.
eq('다른 키', f.isSubmitKey({ key: 'a' }), false);
eq('빈 이벤트', f.isSubmitKey(null), false);
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "조합 중에는 실행하지 않는다" "OK" "$(node "$T_TMP/ime.js" "$CMDJS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi
# 검색창과 모달 둘 다 그 규칙을 써야 한다.
t_contains "검색창이 쓴다" "isSubmitKey(ev)" \
  "$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS")"
t_eq "Enter 를 날것으로 보지 않는다" "0" \
  "$(sed -n '/^  nav(root, t) {/,/^  }/p' "$JS" | grep -c "ev.key === 'Enter'" | tr -d ' ')"

t_start "모듈 로더가 거짓 성공을 거부한다"
# ⚠️ Obsidian 안에서만 도는 경로라 테스트가 없었고, 변이가 살아남았다.
#    로더는 '파일을 찾았다' 로 만족하면 안 된다 — 있어야 할 것이 실제로
#    있는지 봐야 한다. 반쪽짜리 모듈이 붙으면 화면이 조용히 깨진다.
cat > "$T_TMP/loader.js" <<'JSEOF'
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {}, Modal: class { constructor() {} }, Notice: class {} };
  return orig(r, p, m);
};
const fs = require('fs'), os = require('os'), path = require('path');
const f = require(process.argv[2]).__test;
if (!f || typeof f.loadModules !== 'function') { console.log('NOHOOK'); process.exit(0); }

// ⚠️ 모듈이 둘이 됐다. 둘 다 온전해야 로더가 통과한다.
const mk = (modelBody, cmdBody) => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'dtload-'));
  const dir = path.join(base, 'plugins', 'x');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'read-model.js'), modelBody);
  fs.writeFileSync(path.join(dir, 'commands.js'), cmdBody);
  return {
    app: { vault: { adapter: { getBasePath: () => base } } },
    manifest: { dir: 'plugins/x' },
  };
};
const all = (keys) => 'module.exports = {' + keys.map((k) => `${k}: 1`).join(',') + '};';
const bad = [];
// 온전한 모듈 — 통과해야 한다.
const fullModel = all(f.MODEL_KEYS);
const fullCmds = all(f.COMMAND_KEYS);
try { f.loadModules(mk(fullModel, fullCmds)); } catch (e) { bad.push('온전한데 거부: ' + e.message); }

// ⚠️ 어느 모듈이든 하나만 빠져도 거부해야 한다.
try { f.loadModules(mk(all(f.MODEL_KEYS.slice(1)), fullCmds)); bad.push('모델 빠졌는데 통과'); }
catch (e) { if (!/없습니다/.test(e.message)) bad.push('모델 메시지: ' + e.message); }
try { f.loadModules(mk(fullModel, all(f.COMMAND_KEYS.slice(1)))); bad.push('명령 빠졌는데 통과'); }
catch (e) { if (!/없습니다/.test(e.message)) bad.push('명령 메시지: ' + e.message); }

// 볼트 경로를 모르는 플랫폼(모바일)에서는 분명히 실패한다.
try {
  f.loadModules({ app: { vault: { adapter: {} } }, manifest: { dir: 'x' } });
  bad.push('경로 없는데 통과');
} catch (e) { if (!/데스크톱|볼트 경로/.test(e.message)) bad.push('모바일 메시지: ' + e.message); }
console.log(bad.length === 0 ? 'OK' : bad.join(' | '));
JSEOF
if command -v node >/dev/null 2>&1; then
  t_eq "빠진 것을 잡는다" "OK" "$(node "$T_TMP/loader.js" "$JS" 2>&1 | tail -1)"
else
  dim "   node 없음 — 건너뜀"
fi
# ⚠️ 모듈이 안 붙었을 때 화면이 조용히 비지 않는다.
t_contains "미로드를 화면이 말한다" "if (!RM) {" "$(cat "$JS")"
t_contains "무엇을 하면 되는지" "install --apply" "$(cat "$JS")"

t_end
