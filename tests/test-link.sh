#!/usr/bin/env bash
# `devtrail link` — 터미널 연결 (ADR 0006 M4-4b).
#
# ⚠️ 이 명령은 **사용자 홈에 파일을 만든다.** 그래서 규칙이 하나다:
#    **덮어쓰지 않는다.** 이미 있는 devtrail 은 그 사람이 만든 것이고,
#    말없이 바꿔치기하면 터미널에서 쓰던 버전이 달라진다 (D4 공존).
#
# ⚠️ 이 시험은 **실제 ~/.local/bin 을 절대 건드리지 않는다.**
#    DEVTRAIL_BIN_DIR 로 임시 디렉터리를 준다. 아래 첫 단언이 그것부터
#    확인한다 — 격리가 깨진 채로 도는 시험은 시험이 아니라 사고다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

DT="$ROOT/bin/devtrail"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
REAL="$HOME/.local/bin/devtrail"

# 실제 홈의 상태를 미리 찍어 둔다. 끝에 그대로인지 본다.
if [ -L "$REAL" ]; then REAL_BEFORE="link:$(readlink "$REAL")"
elif [ -e "$REAL" ]; then REAL_BEFORE="file"
else REAL_BEFORE="none"; fi

run() { DEVTRAIL_BIN_DIR="$BIN" "$DT" link "$@" 2>&1; }
jstate() { DEVTRAIL_BIN_DIR="$BIN" "$DT" link status --json 2>/dev/null | jq -r '.state'; }

t_start "격리 확인 (실제 홈을 안 본다)"
t_eq "임시 경로를 쓴다" "$BIN/devtrail" \
  "$(DEVTRAIL_BIN_DIR="$BIN" "$DT" link status --json 2>/dev/null | jq -r '.path')"

t_start "없을 때 — 만들 수 있다"
t_eq "상태가 absent" "absent" "$(jstate)"
run create >/dev/null
t_eq "만들어졌다" "yes" "$([ -L "$BIN/devtrail" ] && echo yes || echo no)"
t_eq "우리를 가리킨다" "$ROOT/bin/devtrail" "$(readlink "$BIN/devtrail")"
t_eq "상태가 linked_here" "linked_here" "$(jstate)"

t_start "두 번 해도 안전하다"
t_eq "다시 create 해도 성공" "0" "$(run create >/dev/null 2>&1; echo $?)"
t_eq "여전히 우리를 가리킨다" "$ROOT/bin/devtrail" "$(readlink "$BIN/devtrail")"

t_start "⚠️ 남의 devtrail 은 덮어쓰지 않는다 (D4)"
# 다른 devtrail 이 이미 연결된 상황을 만든다.
OTHER="$TMP/other/bin/devtrail"
mkdir -p "$(dirname "$OTHER")"
printf '#!/bin/sh\necho other\n' > "$OTHER"; chmod +x "$OTHER"
rm -f "$BIN/devtrail"; ln -s "$OTHER" "$BIN/devtrail"

t_eq "상태가 linked_other" "linked_other" "$(jstate)"
t_eq "create 가 실패한다" "1" "$(run create >/dev/null 2>&1; echo $?)"
# ⚠️ 여기가 핵심이다. 거부만 하고 **그대로 두어야** 한다.
t_eq "남의 링크가 그대로다" "$OTHER" "$(readlink "$BIN/devtrail")"
t_eq "그 devtrail 이 아직 돈다" "other" "$("$BIN/devtrail" 2>/dev/null)"

t_start "⚠️ 링크가 아닌 파일도 덮어쓰지 않는다"
rm -f "$BIN/devtrail"
printf '#!/bin/sh\necho mine\n' > "$BIN/devtrail"; chmod +x "$BIN/devtrail"
SUM=$(shasum -a 256 "$BIN/devtrail" | cut -d' ' -f1)
t_eq "상태가 occupied" "occupied" "$(jstate)"
t_eq "create 가 실패한다" "1" "$(run create >/dev/null 2>&1; echo $?)"
t_eq "파일이 한 바이트도 안 바뀌었다" "$SUM" \
  "$(shasum -a 256 "$BIN/devtrail" | cut -d' ' -f1)"

t_start "⚠️ 끊어진 링크는 '남의 것' 이 아니다"
# ⚠️ 2026-08-24 실물 QA. 이 기계의 ~/.local/bin/devtrail 이 죽은 대상을
#    가리키고 있었는데, 예전 판은 그것을 linked_other 로 보고 create 를
#    거부했다 — **사용자가 스스로 고칠 방법이 없었다.**
rm -rf "$BIN"; mkdir -p "$BIN"
ln -s "$TMP/사라진/devtrail" "$BIN/devtrail"
t_eq "상태가 broken 이다" "broken" "$(jstate)"
t_eq "create 가 성공한다 (되살린다)" "0" "$(run create >/dev/null 2>&1; echo $?)"
t_eq "이제 우리를 가리킨다" "$ROOT/bin/devtrail" "$(readlink "$BIN/devtrail")"

t_start "⚠️ 떼어낼 수 있는 볼륨에서는 연결하지 않는다"
# ⚠️ DMG 를 열면 앱이 /Volumes/… 에서 그대로 잘 돈다 — 설치된 줄 알기 쉽다.
#    그 상태에서 연결하면 링크가 DMG 안을 가리키고, **빼는 순간 죽는다.**
#
#    마운트된 것이 있느냐에 기대지 않는다. **읽기전용 볼륨을 직접 만들어**
#    확인한다.
RODMG="$TMP/ro.dmg"
ROSRC="$TMP/rosrc"
mkdir -p "$ROSRC/bin"
cp "$ROOT/bin/devtrail" "$ROSRC/bin/devtrail" 2>/dev/null
cp -R "$ROOT/lib" "$ROSRC/" 2>/dev/null
if hdiutil create -quiet -volname LinkTestRO -srcfolder "$ROSRC" \
     -ov -format UDZO "$RODMG" 2>/dev/null; then
  MNT=$(hdiutil attach "$RODMG" -nobrowse -readonly 2>/dev/null \
        | tail -1 | awk '{$1="";$2="";sub(/^ +/,"");print}')
  if [ -n "$MNT" ] && [ -d "$MNT" ]; then
    # 전제: 정말 읽기전용인가.
    t_eq "전제 — 이 볼륨은 읽기전용이다" "1" \
      "$(touch "$MNT/.w" 2>/dev/null && echo 0 || echo 1)"

    RM_BIN="$TMP/robin"
    rm -rf "$RM_BIN"; mkdir -p "$RM_BIN"
    ROUT=$(DEVTRAIL_BIN_DIR="$RM_BIN" "$MNT/bin/devtrail" link create 2>&1); RRC=$?
    t_eq "create 가 실패한다" "1" "$([ "$RRC" -ne 0 ] && echo 1 || echo 0)"
    t_eq "왜 안 되는지 말한다" "1" \
      "$(printf '%s\n' "$ROUT" | grep -c '응용 프로그램\|removable volume' | tr -d ' ')"
    # ⚠️ 그리고 **아무것도 만들지 않았어야** 한다.
    t_eq "링크를 만들지 않았다" "no" \
      "$([ -e "$RM_BIN/devtrail" ] || [ -L "$RM_BIN/devtrail" ] && echo yes || echo no)"
    # status 는 사실을 싣는다 — 화면이 그것만 보고 그린다.
    t_eq "status 가 self_readonly 를 말한다" "true" \
      "$(DEVTRAIL_BIN_DIR="$RM_BIN" "$MNT/bin/devtrail" link status --json 2>/dev/null \
         | jq -r '.self_readonly')"
    hdiutil detach "$MNT" -quiet 2>/dev/null
  else
    dim "   읽기전용 볼륨을 붙이지 못했습니다 — 건너뜀"
  fi
else
  dim "   읽기전용 이미지를 만들지 못했습니다 — 건너뜀"
fi

# ⚠️ 일반 설치 경로는 걸리지 않아야 한다. 안 그러면 아무도 연결 못 한다.
rm -rf "$BIN"; mkdir -p "$BIN"
t_eq "저장소에서는 self_readonly 가 false" "false" \
  "$(DEVTRAIL_BIN_DIR="$BIN" "$DT" link status --json 2>/dev/null | jq -r '.self_readonly')"

t_start "PATH 에 있는지 말해 준다"
# ⚠️ 링크를 만들어도 PATH 에 없으면 소용이 없다. 그 사실을 감추지 않는다.
rm -f "$BIN/devtrail"
t_eq "PATH 에 없으면 false" "false" \
  "$(PATH="/usr/bin:/bin" DEVTRAIL_BIN_DIR="$BIN" "$DT" link status --json 2>/dev/null | jq -r '.on_path')"
t_eq "PATH 에 있으면 true" "true" \
  "$(PATH="$BIN:/usr/bin:/bin" DEVTRAIL_BIN_DIR="$BIN" "$DT" link status --json 2>/dev/null | jq -r '.on_path')"

t_start "status 는 아무것도 쓰지 않는다"
# ⚠️ 앱이 주기적으로 부르는 명령이다. 부르는 것만으로 상태가 바뀌면 안 된다.
rm -rf "$BIN"
run status >/dev/null 2>&1
t_eq "디렉터리를 만들지 않는다" "no" "$([ -d "$BIN" ] && echo yes || echo no)"

t_start "⚠️ 실제 홈이 그대로다"
# 이 시험 전체가 끝난 뒤에도 사용자의 진짜 devtrail 은 손대지 않았어야 한다.
if [ -L "$REAL" ]; then REAL_AFTER="link:$(readlink "$REAL")"
elif [ -e "$REAL" ]; then REAL_AFTER="file"
else REAL_AFTER="none"; fi
t_eq "~/.local/bin/devtrail 이 그대로다" "$REAL_BEFORE" "$REAL_AFTER"

t_end
