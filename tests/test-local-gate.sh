#!/usr/bin/env bash
# 로컬 게이트가 **약속한 대로 거절하는가**.
#
# ⚠️ 여기서 지키는 것은 "설치가 된다" 가 아니다. 설치되는 건 쉽다.
#    지켜야 할 것은 **하지 않겠다고 약속한 것을 정말 하지 않는가** 다:
#
#      - 남의 hook 을 덮어쓰지 않는다
#      - 대답을 받지 못한 것을 동의로 읽지 않는다
#      - 우리가 설치하지 않은 것을 지우지 않는다
#
#    이 셋 중 하나만 어겨도 도구는 신뢰를 잃는다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

# ⚠️ 실제 저장소의 .git 을 건드리지 않는다. 복제본에서만 시험한다.
REPO="$T_TMP/repo"
mkdir -p "$REPO"
git init -q "$REPO"
mkdir -p "$REPO/scripts/hooks" "$REPO/tests"
cp "$ROOT/scripts/install-git-hooks.sh" "$REPO/scripts/"
cp "$ROOT/scripts/hooks/pre-push" "$REPO/scripts/hooks/"
chmod +x "$REPO/scripts/install-git-hooks.sh" "$REPO/scripts/hooks/pre-push"

inst() { (cd "$REPO" && ./scripts/install-git-hooks.sh "$@" </dev/null 2>&1); }
code() { (cd "$REPO" && ./scripts/install-git-hooks.sh "$@" </dev/null >/dev/null 2>&1); echo $?; }
HOOK="$REPO/.git/hooks/pre-push"

t_start "설치 전 — 없는 상태를 정확히 말한다"
OUT=$(inst)
t_contains "pre-push 가 없다고 말한다" "pre-push       : 없음" "$OUT"
t_no_file "묻기만 하고 설치하지 않았다" "$HOOK"

t_start "대답을 못 받으면 설치하지 않는다"
# ⚠️ 파이프 실행이면 stdin 이 없다. 침묵을 동의로 읽으면 안 된다.
t_contains "대화형 입력이 없다고 말한다" "대화형 입력이 없습니다" "$OUT"
t_eq "종료 코드 1" "1" "$(code)"

t_start "--yes 로 설치한다"
OUT=$(inst --yes)
t_file "hook 이 생겼다" "$HOOK"
t_contains "설치했다고 말한다" "설치했습니다" "$OUT"
t_eq "실행 권한이 있다" "yes" "$([ -x "$HOOK" ] && echo yes || echo no)"
t_eq "우리 것임을 표시한다" "1" "$(grep -c '# DevTrail pre-push' "$HOOK" | tr -d ' ')"

t_start "다시 설치해도 우리 것은 알아본다"
OUT=$(inst --yes)
t_contains "이미 있다고 말한다" "DevTrail 이 설치한 것이 이미 있습니다" "$OUT"

t_start "지운다"
OUT=$(inst --uninstall)
t_no_file "hook 이 사라졌다" "$HOOK"

t_start "⚠️ 남의 hook 을 덮어쓰지 않는다"
printf '#!/bin/sh\n# husky\nexit 0\n' > "$HOOK"; chmod +x "$HOOK"
OUT=$(inst --yes)
t_contains "남의 hook 이라고 경고한다" "남의 hook 이 있습니다" "$OUT"
t_contains "덮어쓰지 않는다고 말한다" "덮어쓰지 않습니다" "$OUT"
t_eq "종료 코드 1" "1" "$(code --yes)"
t_eq "내용이 그대로다" "1" "$(grep -c husky "$HOOK" | tr -d ' ')"

t_start "⚠️ 우리가 설치하지 않은 것을 지우지 않는다"
OUT=$(inst --uninstall)
t_contains "거절한다" "DevTrail 이 설치한 hook 이 아닙니다" "$OUT"
t_file "파일이 남아 있다" "$HOOK"
t_eq "내용이 그대로다" "1" "$(grep -c husky "$HOOK" | tr -d ' ')"
rm -f "$HOOK"

t_start "core.hooksPath 를 존중한다"
# ⚠️ husky·lefthook 이 잡고 있을 수 있다. 우리가 임의로 옮기지 않는다.
ALT="$T_TMP/alt-hooks"; mkdir -p "$ALT"
(cd "$REPO" && git config core.hooksPath "$ALT")
OUT=$(inst --yes)
t_contains "현황에 hooksPath 를 보여준다" "core.hooksPath : $ALT" "$OUT"
t_file "그 경로에 설치했다" "$ALT/pre-push"
t_no_file "기본 경로에는 만들지 않았다" "$HOOK"
(cd "$REPO" && git config --unset core.hooksPath)

t_start "hook 이 push 될 범위를 본다"
# ⚠️ `git diff --check` 만 쓰면 **이미 커밋된** 공백 오류를 놓친다.
#    hook 이 stdin 의 remote sha 를 실제로 읽는지 본다.
t_contains "remotesha 를 읽는다" "remotesha" "$(cat "$ROOT/scripts/hooks/pre-push")"
t_contains "범위로 검사한다" 'diff --check "$range"' "$(cat "$ROOT/scripts/hooks/pre-push")"

t_start "verify-local 은 정본을 부르기만 한다"
VL=$(cat "$ROOT/scripts/verify-local.sh")
t_contains "/bin/bash 로 run.sh 를 부른다" '/bin/bash ./tests/run.sh "$MODE"' "$VL"
t_contains "작업 트리 공백을 본다" "git diff --check" "$VL"
t_contains "--release 가 있다" "--release" "$VL"
# ⚠️ 개별 테스트 파일을 직접 부르면 목록이 둘로 갈린다.
t_eq "개별 테스트를 직접 부르지 않는다" "0" \
  "$(printf '%s' "$VL" | grep -cE '^[^#]*\./tests/test-' | tr -d ' ')"

t_start "⚠️ 실제 push 흐름 — 이미 커밋된 공백 오류를 막는다"
# ⚠️ 위의 단언들은 hook 을 **읽기만** 한다. git 이 stdin 으로 넘기는
#    <local sha> <remote sha> 를 실제로 받아 범위를 계산하는지는 진짜로
#    밀어 봐야만 안다. 임시 bare 원격 안에서만 민다 — 실제 원격은
#    건드리지 않는다.
E2E="$T_TMP/e2e"
mkdir -p "$E2E"
git init -q --bare "$E2E/remote.git"
git init -q "$E2E/work"
(
  cd "$E2E/work" || exit 1
  git remote add origin ../remote.git
  git config user.email t@t
  git config user.name t
  mkdir -p scripts/hooks tests
  cp "$ROOT/scripts/install-git-hooks.sh" scripts/
  cp "$ROOT/scripts/hooks/pre-push" scripts/hooks/
  chmod +x scripts/install-git-hooks.sh scripts/hooks/pre-push
  # run.sh 를 모의한다 — 항상 통과. 여기서 보려는 것은 **범위 검사**뿐이다.
  printf '#!/usr/bin/env bash\nexit 0\n' > tests/run.sh
  chmod +x tests/run.sh
  git add -A && git commit -qm init
  ./scripts/install-git-hooks.sh --yes >/dev/null 2>&1

  printf 'ok\n' > clean.txt
  git add -A && git commit -qm clean
  git push origin main >/dev/null 2>&1 && echo CLEAN_OK || echo CLEAN_BAD

  # 커밋해 버린 뒤라 작업 트리에는 흔적이 없다.
  printf 'trailing   \n' > dirty.txt
  git add -A && git commit -qm dirty
  echo "WORKTREE=$(git diff --check | wc -l | tr -d ' ')"
  git push origin main >/dev/null 2>&1 && echo DIRTY_PASSED || echo DIRTY_BLOCKED
  git push --no-verify origin main >/dev/null 2>&1 && echo BYPASS_OK || echo BYPASS_BAD
) > "$T_TMP/e2e.out" 2>&1
E2EOUT=$(cat "$T_TMP/e2e.out")

t_contains "깨끗한 커밋은 통과한다" "CLEAN_OK" "$E2EOUT"
# ⚠️ 이 줄이 이 테스트의 요점이다. 작업 트리 검사는 0줄 — 아무것도 못 잡는다.
t_contains "작업 트리 검사로는 안 잡힌다" "WORKTREE=0" "$E2EOUT"
t_contains "그런데 push 는 막힌다" "DIRTY_BLOCKED" "$E2EOUT"
t_contains "--no-verify 로 우회된다" "BYPASS_OK" "$E2EOUT"

t_end
