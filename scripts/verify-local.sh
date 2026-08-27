#!/usr/bin/env bash
# 로컬 1차 게이트 — PR 을 올리기 전에 여기서 먼저 통과시킨다.
#
# ⚠️ 이 파일은 **검사 목록을 갖지 않는다.** 정본은 tests/run.sh 하나다.
#    여기에 목록을 다시 적으면 세 번째 정본이 되고, 곧 갈라진다 — 이
#    저장소는 dirs.devlog 기본값을 네 곳에, devlog 파일명을 여섯 곳에
#    두고 같은 병을 앓았다. 여기서는 **부르기만** 한다.
#
# ⚠️ /bin/bash 로 부른다. PATH 의 최신 bash(5.x)가 잡히면 macOS 기본
#    bash 3.2 가 한글 첫 바이트를 변수명에 흡수해 죽는 이 프로젝트 고유의
#    함정을 통과시켜 버린다. CI 의 behav 잡이 하는 일이 바로 이것이고,
#    이 맥의 /bin/bash 가 그 3.2 다 — 로컬은 약한 대체가 아니라 같은 것이다.
#
# 역할 분리 (2026-08-23 정책 확정 — 로컬 우선):
#   로컬(여기)      **정식 품질 게이트**. 커밋·PR 전마다 돌린다.
#   사람의 눈        Obsidian 재시작 후 화면 확인. 대체 불가.
#   GitHub Actions  수동 실행과 태그 릴리스 검증만. 일상 PR 에서 돌지 않는다.
#
# ⚠️ "CI 가 잡아 주겠지" 가 통하지 않는다. 여기서 통과시키지 못한 것은
#    아무도 잡아 주지 않는다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MODE=fast
case "${1:-}" in
  ''|--fast) MODE=fast ;;
  --release) MODE=all ;;
  -h|--help)
    cat <<'USAGE'
사용법: ./scripts/verify-local.sh [--fast|--release]

  (기본)      tests/run.sh fast + 작업 트리 공백 검사   약 2분 30초
  --release   tests/run.sh all (swift 빌드) + 격리 QA 볼트  더 걸린다

  ⚠️ --release 도 Obsidian 재시작 후의 실제 로드·렌더는 **확인하지
     못한다**. 그건 사람이 해야 한다 (Phase 2 의 QA 볼트 하니스가
     무엇을 사람에게 남기는지 기록한다).
USAGE
    exit 0 ;;
  *) echo "알 수 없는 인자: $1 (--help 를 보세요)"; exit 2 ;;
esac

FAIL=0
FAILED=""
# ⚠️ 실패했다는 것만 말하면 2800줄을 뒤져야 한다 — 실제로 그랬다.
#    어느 단계가 실패했는지 이름으로 남긴다.
fail() {
  FAIL=1
  FAILED="$FAILED
   - $1"
}

echo "━━ 작업 트리 공백 검사"
# ⚠️ 여기서는 **작업 트리**를 본다. 아직 커밋하지 않은 것을 잡는 게 목적이다.
#    push 될 커밋 범위는 pre-push hook 이 따로 본다 — 둘은 다른 것을 본다.
if git diff --check && git diff --cached --check; then
  echo "  ✓ 공백 오류 없음"
else
  echo "  ✗ 공백 오류가 있습니다 (위 목록)"
  fail "작업 트리 공백"
fi
echo

# ⚠️ 검사 목록을 여기 적지 않는다. run.sh 가 정본이다.
if /bin/bash ./tests/run.sh "$MODE"; then
  :
else
  fail "검사 스위트 (tests/run.sh)"
fi

# ── --release 는 매니페스트·QA 볼트까지 ─────────────────────────────────
if [ "$MODE" = all ]; then
  echo
  echo "━━ 릴리즈 매니페스트"
  # ⚠️ 만들 수 있다고 **주장하지 않는다. 만들어 본다.** 릴리스 직전에
  #    "매니페스트 생성이 깨져 있었다" 를 알게 되면 늦다.
  if ./scripts/make-release-manifest.sh "$ROOT/release.json"; then
    :
  else
    echo "  ✗ 매니페스트를 만들지 못했습니다"
    fail "릴리즈 매니페스트"
  fi

  echo
  echo "━━ QA 볼트 (격리)"
  # ⚠️ 실제 사용자 볼트는 건드리지 않는다. qa-vault.sh 가 Obsidian 이 아는
  #    볼트 경로를 거부한다.
  if ./scripts/qa-vault.sh; then
    :
  else
    fail "QA 볼트 (격리)"
  fi

  echo
  echo "━━ QA 볼트 — 배포되는 .app 으로 (M4-3)"
  # ⚠️ 위 실행은 **저장소의** CLI 로 돌았다. 사용자가 받는 것은 .app 안의
  #    CLI 다 — 둘은 다를 수 있고, 다를 때 아무도 모른다.
  #
  #    여기서는 .app 사본의 bin/devtrail 과 그 안의 plugin 으로 같은 19건을
  #    다시 돌린다. DT_CC_SRC_OVERRIDE 를 쓰지 않으므로
  #    `$DEVTRAIL_ROOT/plugin` 해석 자체가 시험된다.
  if ./scripts/qa-vault.sh --bundle; then
    :
  else
    fail "QA 볼트 (배포되는 .app)"
  fi
fi

echo
if [ "$FAIL" = 0 ]; then
  echo "✅ 로컬 게이트 통과 — PR 을 올려도 됩니다"
  echo "   ⚠️ 이것이 **정식 게이트**입니다. GitHub Actions 는 일상 PR 에서"
  echo "      돌지 않습니다 (태그·수동만). 화면은 사람이 확인해야 합니다:"
  echo "      Obsidian ⌘Q → 재시작 → ⌘⇧Y"
  exit 0
fi
echo "❌ 로컬 게이트 실패 — 아래 단계를 고치고 다시 실행하세요"
printf '%s\n' "$FAILED"
exit 1
