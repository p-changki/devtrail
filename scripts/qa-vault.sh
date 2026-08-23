#!/usr/bin/env bash
# 격리 QA 볼트에서 설치 → 업데이트 → undo 를 실제로 돌려 본다.
#
# ⚠️ 이 스크립트가 확인하는 것과 **못 하는 것**을 먼저 적는다.
#
#    확인한다:  파일 배치 · files.json 과 설치본 일치 · 고아 파일 제거 ·
#               undo 후 바이트 단위 복구 · 설정 파일과 사용자 노트 불변
#
#    확인 못 한다:  Obsidian 을 재시작한 뒤 플러그인이 **실제로 로드되고
#                   화면이 그려지는가.** 그건 Obsidian 안에서만 일어난다
#                   (ADR 0004). 2026-08-23 에 테스트 300개가 녹색인 채로
#                   화면이 세 번 죽었다 — 파일이 맞다는 것과 뜬다는 것은
#                   다른 문제다.
#
#    그래서 결과 JSON 에 restart_verified: false 를 쓰고, requires_human 에
#    사람이 해야 할 일을 남긴다. **확인하지 않은 것을 확인했다고 말하지
#    않는 것**이 이 하니스의 존재 이유다.
#
# ⚠️ 실제 사용자 볼트는 절대 건드리지 않는다. 아래 _qa_refuse_real 이
#    Obsidian 이 아는 볼트 경로를 거부한다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

DT="$ROOT/bin/devtrail"
OUTDIR="$ROOT/qa-results"
KEEP=0
VAULT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --out) shift; OUTDIR="${1:-$OUTDIR}" ;;
    -h|--help)
      cat <<'USAGE'
사용법: ./scripts/qa-vault.sh [--keep] [--out <디렉터리>]

  격리된 임시 볼트를 만들어 설치·업데이트·undo 를 돌리고,
  사람이 읽는 요약과 기계가 읽는 JSON 을 남깁니다.

  --keep   끝나고 볼트를 지우지 않습니다 (Obsidian 으로 직접 열어 보려면)
  --out    결과를 남길 디렉터리 (기본 ./qa-results, .gitignore 처리됨)

⚠️ Obsidian 재시작 후의 실제 로드·렌더는 **확인하지 못합니다.**
   결과 JSON 의 requires_human 을 보세요.
USAGE
      exit 0 ;;
    *) echo "알 수 없는 인자: $1"; exit 2 ;;
  esac
  shift
done

# ── 실제 볼트 거부 ───────────────────────────────────────────────────────────
#
# ⚠️ 경로 문자열만 비교하지 않는다. Obsidian 이 아는 볼트 목록을 읽어
#    그중 하나면 거부한다. "qa" 라는 이름이 들어갔다고 안전한 게 아니다.
_qa_refuse_real() {
  local target="$1" rt
  rt=$(cd "$target" 2>/dev/null && pwd -P) || return 0

  local list="$HOME/Library/Application Support/obsidian/obsidian.json"
  [ -f "$list" ] || return 0

  local known
  known=$(python3 - "$list" <<'PY' 2>/dev/null || true
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding='utf-8'))
except Exception:
    raise SystemExit
for v in (d.get('vaults') or {}).values():
    p = v.get('path')
    if p:
        print(p)
PY
)
  # ⚠️ 파이프로 while 에 넣지 않는다. 파이프 오른쪽은 **서브셸**에서 돌고,
  #    거기서 exit/return 해도 바깥은 살아서 계속 간다 — 이 저장소가
  #    _cc_validate_src 에서 이미 당한 결함이다(2026-08-22, codex High).
  #    here-doc 으로 붙여 현재 셸에서 돌린다.
  local p rp
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rp=$(cd "$p" 2>/dev/null && pwd -P) || continue
    # 대상이 알려진 볼트이거나, 그 **안**이면 거부한다.
    case "$rt" in
      "$rp"|"$rp"/*)
        echo "❌ 실제 사용자 볼트입니다. QA 하니스는 여기서 아무것도 하지 않습니다."
        echo "   $rp"
        return 9 ;;
    esac
  done <<KNOWN_VAULTS
$known
KNOWN_VAULTS
  return 0
}

# ── 준비 ─────────────────────────────────────────────────────────────────────
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devtrail-qa.XXXXXX") || { echo "❌ 임시 디렉터리 실패"; exit 1; }
VAULT="$TMP/vault"
QHOME="$TMP/home"
mkdir -p "$VAULT/notes" "$QHOME"

_qa_refuse_real "$VAULT" || exit 9

cleanup() {
  if [ "$KEEP" = 1 ]; then
    echo
    echo "   볼트를 남겼습니다: $VAULT"
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

DOT="$VAULT/.obsidian"
DEST="$DOT/plugins/devtrail-command-center"
mkdir -p "$DOT"

# 사용자가 이미 갖고 있을 법한 것들 — 이것들이 **변하지 않아야** 한다.
printf '%s' '{"file-explorer":true,"graph":false}' > "$DOT/core-plugins.json"
printf '%s' '["dataview"]' > "$DOT/community-plugins.json"
printf '%s' '[{"modifiers":["Mod"],"key":"J"}]' > "$DOT/hotkeys.json"
printf -- '---\ntype: devlog\n---\n# 내 노트\n손대면 안 된다\n' > "$VAULT/notes/mine.md"

CFG="$QHOME/devtrail.config.json"
jq -n --arg v "$VAULT" '{
  version: 3, lang: "ko",
  vault: { backend: "local", path: $v, root: "notes" },
  dirs: {}, headings: { issues_pr: "## Issues / PRs", worklog: "## Work log" },
  github: { user: "qa", repos: [], project_groups: {} },
  ai: { provider: "claude", summary_enabled: false },
  install: { mode: "new", modules: ["devlog"] }
}' > "$CFG"

# ⚠️ 저장소의 plugin/ 을 **건드리지 않는다.** 사본을 만들어 그것만 고친다.
#    예전 판은 원본을 고쳤다 되돌렸는데, 중간에 끊기면 저장소가 더럽혀진
#    채로 남는다. DT_CC_SRC_OVERRIDE 가 있으니 쓸 이유가 없다.
SRC="$TMP/plugin-src"
cp -R "$ROOT/plugin" "$SRC"

run() {
  DEVTRAIL_HOME="$QHOME" DEVTRAIL_CONFIG="$CFG" \
  DT_CC_SRC_OVERRIDE="$SRC" "$DT" "$@"
}

# ── 검사 기록 ────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
RESULTS=""

chk() {   # chk <이름> <기대> <실제>
  local name="$1" want="$2" got="$3" ok=false
  if [ "$want" = "$got" ]; then ok=true; PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
  if [ "$ok" = true ]; then
    printf '  ✓ %s\n' "$name"
  else
    printf '  ✗ %s\n     기대: %s\n     실제: %s\n' "$name" "$want" "$got"
  fi
  # ⚠️ 값을 한 줄로 편다. jq 가 쓴 core-plugins.json 은 **여러 줄**이라
  #    그대로 넣으면 TSV 한 줄이 여러 줄로 쪼개지고, 그 기록이 통째로
  #    사라진다 — 2026-08-23 에 19건 중 1건이 그렇게 없어졌다.
  local fw fg
  fw=$(printf '%s' "$want" | tr '\n\t' '  ')
  fg=$(printf '%s' "$got"  | tr '\n\t' '  ')
  RESULTS="$RESULTS$(printf '%s\t%s\t%s\t%s\n' "$name" "$ok" "$fw" "$fg")"
  RESULTS="$RESULTS
"
}

hashdir() {   # 디렉터리 안 파일들의 내용 해시 — 순서 고정
  local d="$1"
  [ -d "$d" ] || { echo "(없음)"; return; }
  (cd "$d" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"
  done) | shasum -a 256 | cut -d' ' -f1
}

manifest_files() {
  python3 -c "import json,io,sys;print('\n'.join(json.load(io.open(sys.argv[1],encoding='utf-8'))['files']))" "$1" 2>/dev/null
}

echo "▶ QA 볼트: $VAULT"
echo

# ── ① 빈 볼트에 새로 설치 ────────────────────────────────────────────────────
echo "① 빈 볼트에 새로 설치"
CORE_BEFORE=$(cat "$DOT/core-plugins.json")
COMM_BEFORE=$(cat "$DOT/community-plugins.json")
HOTK_BEFORE=$(cat "$DOT/hotkeys.json")
NOTE_BEFORE=$(shasum -a 256 "$VAULT/notes/mine.md" | cut -d' ' -f1)

run command-center install --apply >/dev/null 2>&1
chk "플러그인 디렉터리가 생겼다" "yes" "$([ -d "$DEST" ] && echo yes || echo no)"

# files.json 이 선언한 것이 전부 있는가 — 그리고 그 밖의 것은 없는가.
MISSING=""
for f in $(manifest_files "$SRC/files.json"); do
  [ -f "$DEST/$f" ] || MISSING="$MISSING $f"
done
chk "files.json 이 선언한 파일이 전부 있다" "" "$MISSING"

EXTRA=$( (cd "$DEST" 2>/dev/null && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$TMP/have.txt"
  manifest_files "$SRC/files.json" | LC_ALL=C sort > "$TMP/want.txt"
  comm -23 "$TMP/have.txt" "$TMP/want.txt" | tr '\n' ' ' )
chk "선언하지 않은 파일이 없다" "" "$(printf '%s' "$EXTRA" | sed 's/ *$//')"

# 내용이 저장소와 같은가
DIFFER=""
for f in $(manifest_files "$SRC/files.json"); do
  cmp -s "$SRC/$f" "$DEST/$f" || DIFFER="$DIFFER $f"
done
chk "설치본이 저장소와 바이트 단위로 같다" "" "$DIFFER"

# ⚠️ 설치가 남의 설정을 건드리지 않았는가. 이것이 이 하니스의 핵심이다.
chk "community-plugins.json 이 그대로다" "$COMM_BEFORE" "$(cat "$DOT/community-plugins.json")"
chk "hotkeys.json 이 그대로다" "$HOTK_BEFORE" "$(cat "$DOT/hotkeys.json")"
chk "사용자 노트가 그대로다" "$NOTE_BEFORE" "$(shasum -a 256 "$VAULT/notes/mine.md" | cut -d' ' -f1)"
# core-plugins 는 **의도적으로** 검색을 켠다. 남의 값은 지켜야 한다.
chk "남의 true 를 지킨다" "true" "$(jq -r '."file-explorer"' "$DOT/core-plugins.json")"
chk "남의 false 를 지킨다" "false" "$(jq -r '."graph"' "$DOT/core-plugins.json")"
chk "검색은 켠다" "true" "$(jq -r '."global-search"' "$DOT/core-plugins.json")"
echo

# ── ② 업데이트 — 새 파일 추가 ────────────────────────────────────────────────
echo "② 업데이트 — files.json 에 파일을 더한다"
python3 - "$SRC" <<'PY'
import io, json, sys, os
d = sys.argv[1]
p = os.path.join(d, 'files.json')
m = json.load(io.open(p, encoding='utf-8'))
if 'qa-extra.js' not in m['files']:
    m['files'].append('qa-extra.js')
io.open(p, 'w', encoding='utf-8').write(json.dumps(m, ensure_ascii=False, indent=2) + '\n')
io.open(os.path.join(d, 'qa-extra.js'), 'w', encoding='utf-8').write("'use strict';\n// QA 하니스가 만든 파일\n")
mp = os.path.join(d, 'manifest.json')
mf = json.load(io.open(mp, encoding='utf-8'))
a = mf['version'].split('.'); a[2] = str(int(a[2]) + 1); mf['version'] = '.'.join(a)
io.open(mp, 'w', encoding='utf-8').write(json.dumps(mf, ensure_ascii=False, indent=2) + '\n')
PY

run command-center update --apply >/dev/null 2>&1
chk "새 파일이 설치됐다" "yes" "$([ -f "$DEST/qa-extra.js" ] && echo yes || echo no)"
chk "설치본 files.json 도 갱신됐다" "1" \
  "$(manifest_files "$DEST/files.json" | grep -c '^qa-extra\.js$' | tr -d ' ')"
echo

# ── ③ 업데이트 — 파일 제거 (고아) ────────────────────────────────────────────
echo "③ 업데이트 — files.json 에서 빼면 설치본에서도 사라진다"
python3 - "$SRC" <<'PY'
import io, json, sys, os
d = sys.argv[1]
p = os.path.join(d, 'files.json')
m = json.load(io.open(p, encoding='utf-8'))
m['files'] = [f for f in m['files'] if f != 'qa-extra.js']
io.open(p, 'w', encoding='utf-8').write(json.dumps(m, ensure_ascii=False, indent=2) + '\n')
try:
    os.remove(os.path.join(d, 'qa-extra.js'))
except FileNotFoundError:
    pass
mp = os.path.join(d, 'manifest.json')
mf = json.load(io.open(mp, encoding='utf-8'))
a = mf['version'].split('.'); a[2] = str(int(a[2]) + 1); mf['version'] = '.'.join(a)
io.open(mp, 'w', encoding='utf-8').write(json.dumps(mf, ensure_ascii=False, indent=2) + '\n')
PY

run command-center update --apply >/dev/null 2>&1
chk "고아 파일이 지워졌다" "no" "$([ -f "$DEST/qa-extra.js" ] && echo yes || echo no)"
echo

# ── ④ undo — 바이트 단위로 되돌아가는가 ──────────────────────────────────────
echo "④ undo — 직전 상태로 정확히 되돌린다"
BEFORE=$(hashdir "$DEST")
BEFORE_CORE=$(cat "$DOT/core-plugins.json")

# 되돌릴 대상을 하나만 만든다.
# ⚠️ 작업 ID 는 `초단위시각-PID` 라 같은 초에 둘이 생기면 이름순이 PID 순이
#    되고, PID 는 시간순이 아니다. 고를 여지를 없앤다.
rm -rf "$QHOME/journal"
python3 - "$SRC" <<'PY'
import io, json, sys, os
mp = os.path.join(sys.argv[1], 'manifest.json')
mf = json.load(io.open(mp, encoding='utf-8'))
a = mf['version'].split('.'); a[2] = str(int(a[2]) + 1); mf['version'] = '.'.join(a)
io.open(mp, 'w', encoding='utf-8').write(json.dumps(mf, ensure_ascii=False, indent=2) + '\n')
PY
run command-center update --apply >/dev/null 2>&1
AFTER=$(hashdir "$DEST")
chk "업데이트가 실제로 내용을 바꿨다" "different" \
  "$([ "$BEFORE" != "$AFTER" ] && echo different || echo same)"

JOBS=$(ls -1 "$QHOME/journal" 2>/dev/null | wc -l | tr -d ' ')
chk "작업이 하나만 기록됐다" "1" "$JOBS"
JOB=$(ls -1 "$QHOME/journal" 2>/dev/null | head -1)
run undo "$JOB" --apply >/dev/null 2>&1
chk "undo 로 바이트 단위 복구됐다" "$BEFORE" "$(hashdir "$DEST")"
chk "undo 가 core-plugins.json 을 망가뜨리지 않았다" "$BEFORE_CORE" "$(cat "$DOT/core-plugins.json")"
chk "사용자 노트는 여전히 그대로다" "$NOTE_BEFORE" "$(shasum -a 256 "$VAULT/notes/mine.md" | cut -d' ' -f1)"

# ⚠️ 저장소를 건드리지 않았음을 **확인한다**. 안 건드렸다고 믿지 않는다.
chk "저장소 plugin/ 을 건드리지 않았다" "" \
  "$(git -C "$ROOT" status --short plugin/ | tr '\n' ' ' | sed 's/ *$//')"
echo

# ── ⑤ Obsidian 이 떠 있으면 안내만 한다 ──────────────────────────────────────
echo "⑤ Obsidian 상태"
# ⚠️ 자동으로 종료시키지 않는다. 남의 편집 중인 창을 닫는 도구는 쓰이지 않는다.
if pgrep -x Obsidian >/dev/null 2>&1; then
  OBS=running
  echo "  ⚠️ Obsidian 이 실행 중입니다. **강제 종료하지 않습니다.**"
  echo "     직접 ⌘Q 로 완전히 끄고 다시 여셔야 새 코드가 로드됩니다."
else
  OBS=not-running
  echo "  Obsidian 이 실행 중이 아닙니다"
fi
echo

# ── 결과 ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTDIR"
JSON="$OUTDIR/qa-vault.qa.json"

# ⚠️ 파이프로 넘기지 않는다. `python3 - ... <<'PY'` 는 heredoc 이 stdin 을
#    가져가므로 파이프 데이터가 파이썬에 **도달하지 않는다.** 2026-08-23 에
#    실제로 그랬다 — checks 배열이 통째로 빈 채로 passed:19 만 찍혀서,
#    JSON 은 멀쩡해 보이는데 아무 상세도 없었다. 파일로 넘긴다.
printf '%s' "$RESULTS" > "$TMP/results.tsv"
python3 - "$JSON" "$PASS" "$FAIL" "$OBS" "$VAULT" "$TMP/results.tsv" <<'PY'
import io, json, sys

path, npass, nfail, obs, vault, tsv = sys.argv[1:7]
checks = []
for line in io.open(tsv, encoding='utf-8').read().split('\n'):
    if not line.strip():
        continue
    parts = line.split('\t')
    if len(parts) < 4:
        continue
    checks.append({
        'name': parts[0],
        'ok': parts[1] == 'true',
        'expected': parts[2],
        'actual': parts[3],
    })

out = {
    'schema': 1,
    'vault': vault,
    'passed': int(npass),
    'failed': int(nfail),
    'checks': checks,
    # ⚠️ 이 하니스는 파일만 본다. Obsidian 안에서 실제로 로드되고 화면이
    #    그려지는지는 **확인하지 못한다** (ADR 0004). 여기에 true 를 쓰는
    #    것은 사람이 눈으로 본 뒤여야 한다.
    'restart_verified': False,
    'obsidian_process': obs,
    'requires_human': [
        'Obsidian 을 ⌘Q 로 완전히 종료한 뒤 다시 연다',
        '⌘⇧Y 로 Command Center 를 열어 헤더·탭만이 아니라 본문까지 그려지는지 본다',
        '개발자 콘솔(⌘⌥I)에 [DevTrail] 오류가 없는지 본다',
        '확인했다면 이 파일의 restart_verified 를 사람이 true 로 바꾼다',
    ],
}
io.open(path, 'w', encoding='utf-8').write(
    json.dumps(out, ensure_ascii=False, indent=2) + '\n')
PY

# ⚠️ 쓴 것을 **읽어서 확인한다.** 파일을 만들었다는 것과 그 안에 내용이
#    있다는 것은 다른 문제다.
NREC=$(python3 -c "import json,io,sys;print(len(json.load(io.open(sys.argv[1],encoding='utf-8'))['checks']))" "$JSON" 2>/dev/null || echo 0)
if [ "$NREC" != "$((PASS + FAIL))" ]; then
  echo "❌ JSON 에 기록된 검사가 $NREC 건인데 실제로는 $((PASS + FAIL)) 건입니다"
  echo "   결과 파일을 믿을 수 없습니다: $JSON"
  FAIL=$((FAIL + 1))
fi

echo "━━ 결과"
echo "  통과 ${PASS}건 · 실패 ${FAIL}건 · JSON 기록 ${NREC}건"
echo "  JSON: $JSON"
echo
echo "  ⚠️ 이 하니스는 **파일만** 봅니다. Obsidian 안에서 실제로 로드되고"
echo "     화면이 그려지는지는 확인하지 못합니다 (restart_verified: false)."
echo "     사람이 해야 할 일은 JSON 의 requires_human 에 있습니다."

[ "$FAIL" = 0 ] || exit 1
exit 0
