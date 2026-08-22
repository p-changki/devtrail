#!/usr/bin/env bash
# plugin/files.json — 배포물의 단일 정본 (ADR 0004)
#
# ⚠️ 글롭으로 훑지 않는다. 글롭은 새 파일을 우연히 포함할 수는 있어도
#    **제거된 파일**을 다루지 못한다 — 모듈을 지운 릴리스에서 그 파일은
#    배포에서 빠질 뿐, 사용자 폴더엔 영원히 남는다.
#
# ⚠️ 설치본에도 files.json 을 복사한다. 그것이 "이전 릴리스가 무엇을 깔았나"
#    의 기록이고, 그 기록이 있어야 사라진 파일을 안전하게 지울 수 있다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
DT="$ROOT/bin/devtrail"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT
export DEVTRAIL_OBSIDIAN_REGISTRY="$T_TMP/reg.json"
PID="devtrail-command-center"
F="$ROOT/plugin/files.json"

_vault() { local v="$T_TMP/$1"; mkdir -p "$v/.obsidian" "$v/notes"; printf '%s' "$v"; }
_cfg() {
  local v="$1" h="$2"; mkdir -p "$h"
  jq -n --arg v "$v" '{version:3, lang:"ko", vault:{backend:"local", path:$v, root:"notes"},
    dirs:{}, github:{user:"t", repos:[], project_groups:{}},
    install:{mode:"new", modules:["devlog"]}}' > "$h/devtrail.config.json"
}

t_start "정본이 있고 형식이 맞다"
t_eq "files.json 이 있다" "yes" "$([ -f "$F" ] && echo yes || echo no)"
t_json "유효한 JSON" "$F"
t_ne "스키마 버전이 있다" "null" "$(jq -r '.schema // "null"' "$F")"
t_eq "files 가 배열이다" "array" "$(jq -r '.files | type' "$F")"
t_contains "manifest 가 있다" "manifest.json" "$(jq -r '.files[]' "$F")"
t_contains "main 이 있다" "main.js" "$(jq -r '.files[]' "$F")"
t_contains "styles 가 있다" "styles.css" "$(jq -r '.files[]' "$F")"

t_start "경로가 안전하다"
# ⚠️ 절대 경로·상위 이동·중복·숨김·심볼릭 링크를 거부한다. 배포 목록이
#    볼트 밖을 가리키면 설치가 남의 파일을 덮어쓴다.
t_eq "절대 경로가 없다" "0" "$(jq -r '[.files[] | select(startswith("/"))] | length' "$F")"
t_eq "상위 이동이 없다" "0" "$(jq -r '[.files[] | select(test("\\.\\."))] | length' "$F")"
t_eq "숨김 파일이 없다" "0" "$(jq -r '[.files[] | select(test("(^|/)\\."))] | length' "$F")"
t_eq "중복이 없다" "true" "$(jq -r '(.files | length) == (.files | unique | length)' "$F")"
t_eq "심볼릭 링크가 없다" "0" \
  "$(jq -r '.files[]' "$F" | while read -r f; do [ -L "$ROOT/plugin/$f" ] && echo x; done | wc -l | tr -d ' ')"

t_start "목록과 실물이 일치한다"
# ⚠️ 목록에 있는데 없는 파일 → 설치가 깨진다.
missing=$(jq -r '.files[]' "$F" | while read -r f; do [ -f "$ROOT/plugin/$f" ] || printf '%s ' "$f"; done)
t_eq "목록의 파일이 다 있다" "" "$missing"
# ⚠️ 실물인데 목록에 없는 런타임 파일 → 배포에서 빠져 조용히 죽는다.
stray=$(cd "$ROOT/plugin" && for f in *.js *.css *.json; do
          [ -f "$f" ] || continue
          jq -e --arg f "$f" '.files | index($f)' "$F" >/dev/null 2>&1 || printf '%s ' "$f"
        done)
t_eq "런타임 파일이 다 등록돼 있다" "" "$stray"

t_start "셸이 목록을 박아 두지 않는다"
# ⚠️ 목록이 두 곳에 있으면 반드시 갈라진다 — 이 저장소가 dirs.devlog 로
#    네 번 겪은 병이다.
t_eq "commandcentercmd 에 하드코딩이 없다" "0" \
  "$(grep -c 'manifest.json main.js styles.css' "$ROOT/lib/commandcentercmd.sh" | tr -d ' ')"
t_contains "files.json 을 읽는다" "files.json" "$(cat "$ROOT/lib/commandcentercmd.sh")"

# ── 설치·업데이트·복구 ──────────────────────────────────────────────────────
V=$(_vault v); H="$T_TMP/h"; _cfg "$V" "$H"
run() { DEVTRAIL_HOME="$H" DEVTRAIL_CONFIG="$H/devtrail.config.json" "$DT" "$@"; }
D="$V/.obsidian/plugins/$PID"

t_start "목록에 있는 것만 설치한다"
run command-center install --apply >/dev/null 2>&1
for f in $(jq -r '.files[]' "$F"); do
  t_eq "설치됨: $f" "yes" "$([ -f "$D/$f" ] && echo yes || echo no)"
done
# ⚠️ 설치본에도 목록을 남긴다 — 다음 업데이트가 "우리가 뭘 깔았나" 를 안다.
t_eq "설치본에 files.json 이 있다" "yes" "$([ -f "$D/files.json" ] && echo yes || echo no)"
# 목록에 없는 것이 딸려가지 않았다.
extra=$(cd "$D" && for f in *; do
          [ "$f" = "data.json" ] && continue
          jq -e --arg f "$f" '.files | index($f)' "$F" >/dev/null 2>&1 || printf '%s ' "$f"
        done)
t_eq "목록에 없는 것이 없다" "" "$extra"

t_start "모듈이 늘면 함께 배포된다"
SRC="$T_TMP/src-add"; mkdir -p "$SRC"
for f in $(jq -r '.files[]' "$F"); do cp "$ROOT/plugin/$f" "$SRC/$f"; done
printf '%s\n' "module.exports = { M: 'new-module' };" > "$SRC/read-model.js"
jq '.files += ["read-model.js"]' "$F" > "$SRC/files.json"
python3 - "$SRC/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '99.0.0'
json.dump(d, io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
DT_CC_SRC_OVERRIDE="$SRC" run command-center update --apply >/dev/null 2>&1
t_eq "새 모듈이 깔린다" "yes" "$([ -f "$D/read-model.js" ] && echo yes || echo no)"
t_eq "설치본 목록도 갱신된다" "true" \
  "$(jq -e '.files | index("read-model.js") != null' "$D/files.json" 2>/dev/null || echo false)"

t_start "모듈이 사라지면 지운다 — 백업하고"
# ⚠️ 이게 글롭으로는 불가능한 것이다. 우리가 깔았던 파일만, 백업한 뒤에 지운다.
SRC2="$T_TMP/src-del"; mkdir -p "$SRC2"
for f in $(jq -r '.files[]' "$F"); do cp "$ROOT/plugin/$f" "$SRC2/$f"; done
cp "$F" "$SRC2/files.json"
python3 - "$SRC2/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '99.1.0'
json.dump(d, io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
DT_CC_SRC_OVERRIDE="$SRC2" run command-center update --apply >/dev/null 2>&1
t_eq "사라진 모듈이 지워진다" "no" "$([ -f "$D/read-model.js" ] && echo yes || echo no)"
job=$(ls -1 "$H/journal" | tail -1)
t_contains "저널에 남는다" "command-center-update" "$(jq -r '.command' "$H/journal/$job/meta.json")"
run undo "$job" --apply >/dev/null 2>&1
t_eq "undo 가 되살린다" "yes" "$([ -f "$D/read-model.js" ] && echo yes || echo no)"

t_start "남의 파일은 건드리지 않는다"
printf 'user data\n' > "$D/data.json"
printf 'someone else\n' > "$D/not-ours.txt"
DT_CC_SRC_OVERRIDE="$SRC2" run command-center update --apply >/dev/null 2>&1
t_eq "data.json 그대로" "user data" "$(cat "$D/data.json")"
# ⚠️ 우리가 깔지 않은 파일은 목록에 없어도 지우지 않는다.
t_eq "남의 파일 그대로" "someone else" "$(cat "$D/not-ours.txt")"

t_start "옛 설치본에서 넘어온다"
# ⚠️ files.json 이 없던 시절에 깔린 볼트. 기록이 없으므로 아무것도 지우지
#    않는다 — 모르는 것을 지우느니 남기는 게 낫다.
V2=$(_vault v2); H2="$T_TMP/h2"; _cfg "$V2" "$H2"
D2="$V2/.obsidian/plugins/$PID"; mkdir -p "$D2"
cp "$ROOT/plugin/manifest.json" "$ROOT/plugin/main.js" "$ROOT/plugin/styles.css" "$D2/"
printf 'old\n' > "$D2/legacy-module.js"
python3 - "$D2/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '0.0.1'
json.dump(d, io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
DEVTRAIL_HOME="$H2" DEVTRAIL_CONFIG="$H2/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "새 파일이 들어온다" "yes" "$([ -f "$D2/files.json" ] && echo yes || echo no)"
t_eq "모르는 옛 파일은 남긴다" "yes" "$([ -f "$D2/legacy-module.js" ] && echo yes || echo no)"

t_start "설치본의 목록이 오염돼도 밖을 지우지 않는다"
# ⚠️ _cc_orphans 는 **설치본**의 files.json 을 읽는다. 그 파일은 사용자
#    폴더에 있고 누구나 고칠 수 있다. 거기에 ../../ 가 들어 있으면 우리가
#    볼트 밖 파일을 지우게 된다 — 정적 검사(우리 목록)만으로는 못 막는다.
V3=$(_vault v3); H3="$T_TMP/h3"; _cfg "$V3" "$H3"
D3="$V3/.obsidian/plugins/$PID"
DEVTRAIL_HOME="$H3" DEVTRAIL_CONFIG="$H3/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1

# 볼트 밖에 건드리면 안 되는 파일을 둔다.
CANARY="$T_TMP/canary.txt"; printf 'do not touch\n' > "$CANARY"
# 설치본 목록을 오염시킨다.
python3 - "$D3/files.json" <<'PYEOF'
import json, io, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding='utf-8'))
d['files'] = d['files'] + ['../../../../canary.txt', '/etc/hosts', '.ssh/id_rsa']
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
python3 - "$D3/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '0.0.1'
json.dump(d, io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
DEVTRAIL_HOME="$H3" DEVTRAIL_CONFIG="$H3/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "볼트 밖 파일이 무사하다" "do not touch" "$(cat "$CANARY" 2>/dev/null)"
t_eq "시스템 파일이 무사하다" "yes" "$([ -f /etc/hosts ] && echo yes || echo no)"

t_start "심볼릭 링크로 밖을 지우지 못한다"
# ⚠️ 이름 필터(..)를 **통과하면서도** 밖을 가리키는 길이 있다: 설치 폴더 안의
#    심볼릭 링크 디렉터리. 'sub/thing.js' 는 이름만 보면 멀쩡하지만 sub 가
#    밖을 가리키면 남의 파일을 지우게 된다.
#
#    이름을 거르는 것과 **실제 경로**를 거르는 것은 다른 일이다.
V4=$(_vault v4); H4="$T_TMP/h4"; _cfg "$V4" "$H4"
D4="$V4/.obsidian/plugins/$PID"
DEVTRAIL_HOME="$H4" DEVTRAIL_CONFIG="$H4/devtrail.config.json" \
  "$DT" command-center install --apply >/dev/null 2>&1

OUT="$T_TMP/outside"; mkdir -p "$OUT"
printf 'precious\n' > "$OUT/thing.js"
ln -s "$OUT" "$D4/sub"
# 설치본 목록이 그 링크 너머를 가리킨다 — 이름엔 .. 가 없다.
python3 - "$D4/files.json" <<'PYEOF'
import json, io, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding='utf-8'))
d['files'] = d['files'] + ['sub/thing.js']
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
python3 - "$D4/manifest.json" <<'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8')); d['version'] = '0.0.1'
json.dump(d, io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PYEOF
DEVTRAIL_HOME="$H4" DEVTRAIL_CONFIG="$H4/devtrail.config.json" \
  "$DT" command-center update --apply >/dev/null 2>&1
t_eq "링크 너머 파일이 무사하다" "precious" "$(cat "$OUT/thing.js" 2>/dev/null)"

t_start "설치 폴더 밖인지 직접 판정한다"
# ⚠️ 목록 필터에만 기대지 않는다. 지우는 자리에서 한 번 더 본다 —
#    필터가 언젠가 느슨해져도 여기서 막힌다.
cat > "$T_TMP/inside.sh" <<'SHEOF'
. "$1/lib/common.sh" >/dev/null 2>&1 || true
. "$1/lib/commandcentercmd.sh"
d="$2"
bad=0
chk() { if _cc_inside "$d" "$2"; then got=yes; else got=no; fi
        [ "$got" = "$3" ] || { echo "MISMATCH $1 want $3 got $got"; bad=1; }; }
chk "안쪽 파일"     "$d/main.js"                 yes
chk "상위로 탈출"   "$d/../../../../canary.txt"  no
chk "절대 경로"     "/etc/hosts"                 no
chk "없는 파일"     "$d/nope.js"                 no
chk "형제 폴더"     "$d/../other/x.js"           no
[ $bad = 0 ] && echo OK || echo FAIL
SHEOF
printf 'x\n' > "$T_TMP/canary.txt"
t_eq "안쪽만 참이다" "OK" "$(bash "$T_TMP/inside.sh" "$ROOT" "$D" 2>&1 | tail -1)"

t_end
