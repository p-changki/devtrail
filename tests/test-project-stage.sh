#!/usr/bin/env bash
# 프로젝트 단계 (ADR 0006 · 2026-08-24 실물 QA).
#
# ⚠️ 왜 생겼나
#
#    대시보드는 frontmatter 의 `stage` 로 칸을 나눈다. 그런데 사용자가 자기
#    Templater 템플릿으로 만든 프로젝트에는 그 키가 없어서 **"단계 미지정"**
#    으로만 쌓였고, 고치려면 노트를 직접 열어 손으로 적어야 했다.
#
#    `stage` 는 이미 계약에 있다 — 없던 것은 **그 키를 채워 넣을 수단**이다.
#
# ⚠️ 실제 사용자 볼트는 건드리지 않는다. 전부 임시 디렉터리다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

DT="$ROOT/bin/devtrail"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
V="$TMP/vault"; H="$TMP/home"; C="$TMP/c.json"
mkdir -p "$V/.obsidian" "$H"

dt() { DEVTRAIL_HOME="$H/.devtrail" DEVTRAIL_CONFIG="$C" "$DT" "$@" < /dev/null; }
dt setup quick --vault "$V" --lang ko --apply >/dev/null 2>&1

stage_of() { awk '/^stage:/{sub(/^stage:[[:space:]]*/,""); print; exit}' "$1"; }
note_of()  { find "$V" -path "*$1*" -name '*.md' 2>/dev/null | head -1; }

t_start "새 프로젝트는 단계를 갖고 태어난다"
# ⚠️ 단계가 없으면 대시보드에서 곧바로 '단계 미지정' 으로 빠진다.
dt project add proj-a --apply >/dev/null 2>&1
t_eq "기본은 planning" "planning" "$(stage_of "$(note_of proj-a)")"

t_start "만들 때 단계를 고를 수 있다"
dt project add proj-b --stage in-progress --apply >/dev/null 2>&1
t_eq "--stage 가 반영된다" "in-progress" "$(stage_of "$(note_of proj-b)")"

t_start "⚠️ 모르는 단계를 막는다"
# ⚠️ 막지 않으면 대시보드에서 조용히 '단계 미지정' 으로 빠진다 —
#    사용자는 적었는데 안 잡힌다고 느낀다.
t_eq "add 가 거부한다" "1" \
  "$(dt project add proj-x --stage 아무거나 --apply >/dev/null 2>&1; echo $?)"
t_eq "stage 가 거부한다" "1" \
  "$(dt project stage proj-a 아무거나 --apply >/dev/null 2>&1; echo $?)"
t_eq "거부했으면 만들지도 않는다" "" "$(note_of proj-x)"

t_start "⚠️ dry-run 이 기본이다"
dt project stage proj-a done >/dev/null 2>&1
t_eq "--apply 없이는 안 바뀐다" "planning" "$(stage_of "$(note_of proj-a)")"
dt project stage proj-a done --apply >/dev/null 2>&1
t_eq "--apply 로 바뀐다" "done" "$(stage_of "$(note_of proj-a)")"

t_start "⚠️ 키가 없던 노트에도 넣는다 (기존 볼트)"
# ⚠️ 이게 이번 QA 에서 막힌 자리다 — 사용자 템플릿으로 만든 노트에는
#    stage 키 자체가 없었다.
D="$(dirname "$(dirname "$(note_of proj-a)")")/proj-d"
mkdir -p "$D"
printf -- '---\ntype: project-home\nstatus: active\n---\n# proj-d\n본문에 stage: 라고 써 있어도 안 건드린다\n' \
  > "$D/README.md"
dt project stage proj-d blocked --apply >/dev/null 2>&1
t_eq "키가 생긴다" "blocked" "$(stage_of "$D/README.md")"
t_eq "frontmatter 가 온전하다" "1" \
  "$(awk 'NR==1 && $0=="---"{a=1} a && /^---$/{n++} END{print (n>=2)?1:0}' "$D/README.md")"
# ⚠️ 본문의 같은 글자를 건드리면 안 된다.
t_eq "본문을 건드리지 않는다" "1" \
  "$(grep -c '본문에 stage: 라고' "$D/README.md" | tr -d ' ')"
t_eq "stage 키가 하나뿐이다" "1" "$(grep -c '^stage:' "$D/README.md" | tr -d ' ')"

t_start "⚠️ 되돌릴 수 있다"
# ⚠️ 사용자 노트를 고치는 일이다. 저널에 남아야 한다.
BEFORE=$(stage_of "$D/README.md")
JOB=$(ls -1 "$H/.devtrail/journal" 2>/dev/null | LC_ALL=C sort -r | head -1)
t_eq "저널에 남았다" "yes" "$([ -n "$JOB" ] && echo yes || echo no)"
dt undo "$JOB" --apply >/dev/null 2>&1
t_eq "되돌리면 키가 사라진다" "" "$(stage_of "$D/README.md")"
t_eq "되돌려도 본문은 그대로다" "1" \
  "$(grep -c '본문에 stage: 라고' "$D/README.md" | tr -d ' ')"

t_start "⚠️ frontmatter 밖의 같은 글자는 건드리지 않는다"
# ⚠️ 본문에 `stage:` 로 **시작하는** 줄이 있고, frontmatter 에도 키가 있는
#    경우다. 앵커만 보고 바꾸면 본문까지 고쳐진다 — 사용자 노트를 망친다.
#    (첫 판에서 이 갈래에 닿지 않아 변이가 살아남았다.)
E="$(dirname "$D")/proj-e"
mkdir -p "$E"
printf -- '---\ntype: project-home\nstatus: active\nstage: planning\n---\n# proj-e\nstage: 본문에 있는 줄\n' \
  > "$E/README.md"
dt project stage proj-e done --apply >/dev/null 2>&1
t_eq "frontmatter 의 stage 만 바뀐다" "done" "$(stage_of "$E/README.md")"
t_eq "본문의 stage: 줄은 그대로다" "1" \
  "$(grep -c '^stage: 본문에 있는 줄$' "$E/README.md" | tr -d ' ')"
t_eq "stage 로 시작하는 줄이 둘이다" "2" \
  "$(grep -c '^stage:' "$E/README.md" | tr -d ' ')"

t_start "단계 목록의 정본이 하나다"
# ⚠️ 화면·템플릿·검증이 각자 목록을 가지면 언젠가 한쪽만 늘어난다.
t_eq "DT_PJ_STAGES 가 정본이다" "1" \
  "$(grep -c '^DT_PJ_STAGES=' "$ROOT/lib/projectcmd.sh" | tr -d ' ')"
for s in planning in-progress blocked done; do
  t_eq "$s 가 목록에 있다" "1" \
    "$(grep '^DT_PJ_STAGES=' "$ROOT/lib/projectcmd.sh" | grep -c "$s" | tr -d ' ')"
done

t_end
