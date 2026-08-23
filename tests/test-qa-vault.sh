#!/usr/bin/env bash
# QA 하니스가 **실제 사용자 볼트를 거부하는가**.
#
# ⚠️ 여기서 지키는 것은 하나다: 이 도구가 남의 볼트에 손대지 않는다는 약속.
#    나머지(설치·업데이트·undo)는 하니스 자신이 19건을 단언한다. 여기서는
#    그 하니스가 **애초에 어디서 돌아도 되는지**를 본다.
#
# ⚠️ 개발자 머신의 obsidian.json 을 읽지 않는다. HOME 을 임시 경로로 바꿔
#    가짜 목록을 준다 — 그래야 이 테스트가 CI 에서도, 볼트가 없는 사람의
#    기계에서도 같은 답을 낸다. 진짜 파일을 읽으면 ubuntu 러너에서는
#    파일이 없어 함수가 곧바로 통과하고, 단언이 **공허해진다.**
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

HARNESS="$ROOT/scripts/qa-vault.sh"

t_start "하니스가 있고 문법이 성립한다"
t_file "scripts/qa-vault.sh 이 있다" "$HARNESS"
/bin/bash -n "$HARNESS" 2>"$T_TMP/syn.txt"
t_eq "bash 3.2 문법 통과" "0" "$?"

# 함수만 떼어 온다.
sed -n '/^_qa_refuse_real() {/,/^}/p' "$HARNESS" > "$T_TMP/refuse.sh"
t_start "거부 함수를 실제로 떼어 왔다"
# ⚠️ sed 가 아무것도 못 찾으면 빈 파일이 되고, 아래 단언이 전부 공허하게
#    통과한다. 이 저장소가 이미 네 번 당한 부류다 — 먼저 확인한다.
t_contains "함수 정의가 들어 있다" "_qa_refuse_real() {" "$(cat "$T_TMP/refuse.sh")"
t_contains "return 으로 끝난다 (exit 아님)" "return 9" "$(cat "$T_TMP/refuse.sh")"

# 가짜 HOME + 가짜 볼트 목록
FAKE_HOME="$T_TMP/home"
mkdir -p "$FAKE_HOME/Library/Application Support/obsidian"
REALV="$T_TMP/pretend-real-vault"
OTHER="$T_TMP/somewhere-else"
mkdir -p "$REALV/.obsidian" "$OTHER"
python3 - "$FAKE_HOME/Library/Application Support/obsidian/obsidian.json" "$REALV" <<'PYEOF'
import io, json, sys
io.open(sys.argv[1], 'w', encoding='utf-8').write(json.dumps({
    'vaults': {'abc123': {'path': sys.argv[2], 'ts': 1}}
}, ensure_ascii=False))
PYEOF

# ⚠️ 함수를 부르고 **종료 코드**를 본다. 메시지만 보면, 거부한다고 말하면서
#    실제로는 계속 가는 구조를 놓친다 — 파이프 안 서브셸에서 exit 하던
#    _cc_validate_src 가 정확히 그랬다(2026-08-22, codex High).
rc() {
  HOME="$FAKE_HOME" /bin/bash -c '
    . "$1"
    _qa_refuse_real "$2" >/dev/null 2>&1
    echo $?
  ' _ "$T_TMP/refuse.sh" "$1"
}

t_start "⚠️ 알려진 볼트를 거부한다"
t_eq "볼트 자체 → 9" "9" "$(rc "$REALV")"
t_eq "볼트 안의 하위 경로 → 9" "9" "$(rc "$REALV/.obsidian")"

t_start "무관한 경로는 통과시킨다"
t_eq "다른 임시 경로 → 0" "0" "$(rc "$OTHER")"

t_start "목록이 없거나 깨져도 막히지 않는다"
# ⚠️ obsidian.json 이 없는 기계(CI ubuntu)에서 하니스가 못 돌면 안 된다.
EMPTY_HOME="$T_TMP/empty-home"; mkdir -p "$EMPTY_HOME"
t_eq "목록 파일이 없으면 → 0" "0" \
  "$(HOME="$EMPTY_HOME" /bin/bash -c '. "$1"; _qa_refuse_real "$2" >/dev/null 2>&1; echo $?' \
     _ "$T_TMP/refuse.sh" "$OTHER")"
BROKEN="$T_TMP/broken-home"
mkdir -p "$BROKEN/Library/Application Support/obsidian"
printf 'not json' > "$BROKEN/Library/Application Support/obsidian/obsidian.json"
t_eq "목록이 깨졌으면 → 0" "0" \
  "$(HOME="$BROKEN" /bin/bash -c '. "$1"; _qa_refuse_real "$2" >/dev/null 2>&1; echo $?' \
     _ "$T_TMP/refuse.sh" "$OTHER")"

t_start "하니스가 저장소 plugin/ 을 고치지 않는다"
# ⚠️ 예전 판은 원본을 고쳤다 되돌렸다. 중간에 끊기면 저장소가 더럽혀진 채
#    남는다. DT_CC_SRC_OVERRIDE 로 사본을 쓰는지 소스에서 확인한다.
SRC=$(cat "$HARNESS")
t_contains "DT_CC_SRC_OVERRIDE 를 쓴다" "DT_CC_SRC_OVERRIDE=" "$SRC"
t_eq "\$ROOT/plugin 을 고치는 자리가 없다" "0" \
  "$(printf '%s' "$SRC" | grep -cE '^[^#]*python3 - "\$ROOT/plugin"' | tr -d ' ')"

t_start "확인하지 않은 것을 확인했다고 말하지 않는다"
# ⚠️ 이 하니스의 존재 이유다. 파일이 맞다는 것과 화면이 뜬다는 것은 다르다 —
#    2026-08-23 에 테스트 300개가 녹색인 채로 화면이 세 번 죽었다.
t_contains "restart_verified 를 False 로 쓴다" "'restart_verified': False" "$SRC"
t_contains "requires_human 을 남긴다" "requires_human" "$SRC"
t_eq "restart_verified 를 True 로 쓰는 자리가 없다" "0" \
  "$(printf '%s' "$SRC" | grep -c "'restart_verified': True" | tr -d ' ')"

t_start "Obsidian 을 강제 종료하지 않는다"
# ⚠️ 남의 편집 중인 창을 닫는 도구는 두 번 쓰이지 않는다.
t_eq "kill/pkill/quit 을 부르지 않는다" "0" \
  "$(printf '%s' "$SRC" | grep -cE '^[^#]*(pkill|killall|osascript.*quit)' | tr -d ' ')"
t_contains "떠 있으면 안내만 한다" "강제 종료하지 않습니다" "$SRC"

t_end
