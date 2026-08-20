#!/usr/bin/env bash
# DevTrail 설치 스크립트
#
#   curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash
#
# 하는 일: 저장소를 받고 devtrail 명령을 PATH에 연결한다.
# 하지 않는 일: 볼트·Obsidian·Claude 설정은 건드리지 않는다(그건 devtrail init/obsidian).

set -euo pipefail

REPO="${DEVTRAIL_REPO:-https://github.com/p-changki/devtrail.git}"
BRANCH="${DEVTRAIL_BRANCH:-main}"
INSTALL_DIR="${DEVTRAIL_INSTALL_DIR:-$HOME/.devtrail/src}"
BIN_DIR="${DEVTRAIL_BIN_DIR:-$HOME/.local/bin}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

# ── 플랫폼 ───────────────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  red "❌ 현재 macOS만 지원합니다 (감지: $(uname -s))"
  dim "   launchd 기반 스케줄링에 의존합니다. Linux/Windows 지원은 계획에 있습니다."
  exit 1
fi

# ── 필수 도구 ────────────────────────────────────────────────────────────────
missing=()
for b in git jq rsync python3; do
  command -v "$b" >/dev/null 2>&1 || missing+=("$b")
done
if [ ${#missing[@]} -gt 0 ]; then
  red "❌ 필수 도구가 없습니다: ${missing[*]}"
  dim "   brew install ${missing[*]}"
  exit 1
fi

# gh 는 없어도 설치는 되지만 핵심 기능이 죽는다. 조용히 넘어가지 않는다.
if ! command -v gh >/dev/null 2>&1; then
  printf '\033[33m⚠️  gh (GitHub CLI) 가 없습니다\033[0m\n'
  dim "   PR/이슈 수집이 동작하지 않습니다. 나중에: brew install gh && gh auth login"
fi

# ── 받기 ─────────────────────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "▶ 기존 설치 갱신: $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --quiet --hard "origin/$BRANCH"
else
  echo "▶ 내려받는 중: $REPO"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --quiet --depth 1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/bin/devtrail" "$INSTALL_DIR/tests/scan-secrets.sh" 2>/dev/null || true

# ── PATH 연결 ────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/devtrail" "$BIN_DIR/devtrail"
green "✅ 설치 완료: $BIN_DIR/devtrail"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    printf '\033[33m⚠️  %s 가 PATH에 없습니다\033[0m\n' "$BIN_DIR"
    dim "   셸 설정에 아래를 추가하세요:"
    dim "     echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

cat <<EOF

다음 단계
  1) devtrail init             볼트·GitHub·AI 설정
  2) Obsidian에서 볼트 열기    (.obsidian/ 폴더가 이때 생깁니다)
  3) 플러그인 3개 설치 후 재시작
       Shell commands · Templater · Dataview
  4) devtrail obsidian         셸커맨드 병합 · 노트 템플릿 설치
  5) devtrail doctor           진단 (여기서 ❌ 가 없어야 합니다)
  6) devtrail install-schedule 자동 실행 등록

  ⚠️ 순서를 지키세요. 2~3을 건너뛰고 4를 실행하면 셸커맨드 병합이 조용히
     건너뛰어집니다(Obsidian에 DevTrail 명령이 나타나지 않습니다).

EOF
