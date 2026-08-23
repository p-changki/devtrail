#!/usr/bin/env bash
# git hook 을 **원할 때만** 설치한다.
#
# ⚠️ 조용히 덮어쓰지 않는다. 사람마다 자기 hook 설정이 있고, husky·lefthook
#    같은 도구가 core.hooksPath 를 잡고 있을 수도 있다. 남의 설정을 말없이
#    가져가는 도구는 한 번 신뢰를 잃으면 끝이다.
#
#    현황과 충돌을 먼저 보여 주고, 명시 동의가 있을 때만 설치한다.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SRC="$ROOT/scripts/hooks/pre-push"
YES=0
UNINSTALL=0
case "${1:-}" in
  --yes) YES=1 ;;
  --uninstall) UNINSTALL=1 ;;
  -h|--help)
    cat <<'USAGE'
사용법: ./scripts/install-git-hooks.sh [--yes|--uninstall]

  (기본)        현황을 보여 주고 물어본다
  --yes         묻지 않고 설치 (충돌이 있으면 그래도 멈춘다)
  --uninstall   우리가 설치한 것만 지운다

설치되는 것: pre-push — lint + guard + push 범위 공백 검사 (약 8초)
우회: git push --no-verify   (실수 방지 장치이지 보안 경계가 아닙니다)
USAGE
    exit 0 ;;
  '') ;;
  *) echo "알 수 없는 인자: $1"; exit 2 ;;
esac

[ -f "$SRC" ] || { echo "❌ $SRC 이 없습니다"; exit 1; }

HOOKS_PATH=$(git config --get core.hooksPath || true)
GITDIR=$(git rev-parse --git-dir)
DEST_DIR="${HOOKS_PATH:-$GITDIR/hooks}"
DEST="$DEST_DIR/pre-push"
MARK="# DevTrail pre-push"

# ── 현황 ────────────────────────────────────────────────────────────────
echo "▶ 현재 상태"
if [ -n "$HOOKS_PATH" ]; then
  echo "   core.hooksPath : $HOOKS_PATH  ⚠️ 다른 도구가 잡고 있을 수 있습니다"
else
  echo "   core.hooksPath : (설정 없음 — 기본 $GITDIR/hooks)"
fi
if [ -e "$DEST" ]; then
  if grep -q "$MARK" "$DEST" 2>/dev/null; then
    echo "   pre-push       : DevTrail 이 설치한 것이 이미 있습니다"
    OURS=1
  else
    echo "   pre-push       : ⚠️ **남의 hook 이 있습니다** ($DEST)"
    echo "                    첫 줄: $(head -1 "$DEST")"
    OURS=0
  fi
else
  echo "   pre-push       : 없음"
  OURS=none
fi
echo

# ── 지우기 ──────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  if [ "$OURS" = 1 ]; then
    rm -f "$DEST" && echo "✅ 지웠습니다: $DEST"
  elif [ "$OURS" = 0 ]; then
    # ⚠️ 우리가 설치하지 않은 것은 지우지 않는다.
    echo "❌ DevTrail 이 설치한 hook 이 아닙니다. 건드리지 않습니다."
    exit 1
  else
    echo "   지울 것이 없습니다"
  fi
  exit 0
fi

# ── 충돌이면 멈춘다 ─────────────────────────────────────────────────────
if [ "$OURS" = 0 ]; then
  echo "❌ 이미 다른 pre-push hook 이 있습니다. **덮어쓰지 않습니다.**"
  echo "   직접 합치시려면 참고할 파일: $SRC"
  exit 1
fi

# ── 동의 ────────────────────────────────────────────────────────────────
echo "설치할 것: $DEST"
echo "  - lint + guard + push 범위 공백 검사 (약 8초)"
echo "  - 실패하면 push 를 막습니다"
echo "  - git push --no-verify 로 우회 가능 (실수 방지 장치이지 보안 경계 아님)"
echo
if [ "$YES" != 1 ]; then
  # ⚠️ 파이프로 실행되면 stdin 이 없다. 그때는 설치하지 않는다 — 대답을
  #    받지 못한 것을 동의로 읽지 않는다.
  if [ ! -t 0 ]; then
    echo "❌ 대화형 입력이 없습니다. 뜻이 분명하면 --yes 를 붙여 주세요."
    exit 1
  fi
  printf '설치할까요? [y/N] '
  read -r ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "   설치하지 않았습니다"; exit 0 ;;
  esac
fi

mkdir -p "$DEST_DIR" || { echo "❌ $DEST_DIR 을 만들 수 없습니다"; exit 1; }
cp "$SRC" "$DEST" || { echo "❌ 복사 실패"; exit 1; }
chmod +x "$DEST"
echo "✅ 설치했습니다: $DEST"
echo "   지우기: ./scripts/install-git-hooks.sh --uninstall"
