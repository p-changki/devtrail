#!/usr/bin/env bash
# DevTrail 설치 스크립트 / installer
#
#   curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash
#
# 하는 일: 저장소를 받고 devtrail 명령을 PATH에 연결한다.
# 하지 않는 일: 볼트·Obsidian·Claude 설정은 건드리지 않는다(그건 devtrail init/obsidian).
#
# ⚠️ 이 파일은 저장소가 받아지기 전에 돈다(curl | bash). 그래서 lib/i18n 의
#    메시지 카탈로그를 쓸 수 없다 — 양쪽 문구를 여기 직접 둔다.

set -euo pipefail

REPO="${DEVTRAIL_REPO:-https://github.com/p-changki/devtrail.git}"
BRANCH="${DEVTRAIL_BRANCH:-main}"
INSTALL_DIR="${DEVTRAIL_INSTALL_DIR:-$HOME/.devtrail/src}"
BIN_DIR="${DEVTRAIL_BIN_DIR:-$HOME/.local/bin}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

# 언어. devtrail init 이 다시 물어보므로 여기서는 로케일만 본다.
case "${DEVTRAIL_LANG:-${LC_ALL:-${LANG:-}}}" in
  en) LANG_EN=1 ;;
  ko|ko_*|*_KR*|'') LANG_EN=0 ;;
  *) LANG_EN=1 ;;
esac
# L <한국어> <English>
L() { [ "$LANG_EN" = 1 ] && printf '%s' "$2" || printf '%s' "$1"; }

# ── 플랫폼 ───────────────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  red "❌ $(L "현재 macOS만 지원합니다" "macOS only for now") ($(uname -s))"
  dim "   $(L "launchd 기반 스케줄링에 의존합니다. Linux/Windows 지원은 계획에 있습니다." \
              "It relies on launchd for scheduling. Linux/Windows support is planned.")"
  exit 1
fi

# ── 필수 도구 ────────────────────────────────────────────────────────────────
missing=()
for b in git jq rsync python3; do
  command -v "$b" >/dev/null 2>&1 || missing+=("$b")
done
if [ ${#missing[@]} -gt 0 ]; then
  red "❌ $(L "필수 도구가 없습니다" "Missing required tools"): ${missing[*]}"
  dim "   brew install ${missing[*]}"
  exit 1
fi

# gh 는 없어도 설치는 되지만 핵심 기능이 죽는다. 조용히 넘어가지 않는다.
if ! command -v gh >/dev/null 2>&1; then
  printf '\033[33m⚠️  %s\033[0m\n' "$(L "gh (GitHub CLI) 가 없습니다" "gh (GitHub CLI) not found")"
  dim "   $(L "PR/이슈 수집이 동작하지 않습니다. 나중에:" \
              "Pulling PRs and issues will not work. Later:") brew install gh && gh auth login"
fi

# ── 받기 ─────────────────────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "▶ $(L "기존 설치 갱신" "Updating existing install"): $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --quiet --hard "origin/$BRANCH"
else
  echo "▶ $(L "내려받는 중" "Downloading"): $REPO"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --quiet --depth 1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/bin/devtrail" "$INSTALL_DIR/tests/scan-secrets.sh" 2>/dev/null || true

# ── PATH 연결 ────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/devtrail" "$BIN_DIR/devtrail"
green "✅ $(L "설치 완료" "Installed"): $BIN_DIR/devtrail"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    printf '\033[33m⚠️  %s %s\033[0m\n' "$BIN_DIR" "$(L "가 PATH에 없습니다" "is not on your PATH")"
    dim "   $(L "셸 설정에 아래를 추가하세요:" "Add this to your shell config:")"
    dim "     echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

if [ "$LANG_EN" = 1 ]; then
cat <<'EOF'

Next steps
  1) devtrail init             vault · GitHub · AI setup (asks for language first)
  2) Open the vault in Obsidian   (this is when .obsidian/ appears)
  3) Install 4 plugins, then restart
       Shell commands · Templater · Dataview · Auto Note Mover
  4) devtrail obsidian         merge shell commands · install note templates
  5) devtrail doctor           diagnose (you want no ❌ here)
  6) devtrail install-schedule register automatic runs

  ⚠️ Keep the order. Running 4 before 2–3 skips the shell-command merge
     silently — DevTrail commands never show up inside Obsidian.

EOF
else
cat <<'EOF'

다음 단계
  1) devtrail init             언어·볼트·GitHub·AI 설정
  2) Obsidian에서 볼트 열기    (.obsidian/ 폴더가 이때 생깁니다)
  3) 플러그인 4개 설치 후 재시작
       Shell commands · Templater · Dataview · Auto Note Mover
  4) devtrail obsidian         셸커맨드 병합 · 노트 템플릿 설치
  5) devtrail doctor           진단 (여기서 ❌ 가 없어야 합니다)
  6) devtrail install-schedule 자동 실행 등록

  ⚠️ 순서를 지키세요. 2~3을 건너뛰고 4를 실행하면 셸커맨드 병합이 조용히
     건너뛰어집니다(Obsidian에 DevTrail 명령이 나타나지 않습니다).

EOF
fi
