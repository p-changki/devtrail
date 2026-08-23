#!/usr/bin/env bash
# python3 없이 어디까지 도는가 (ADR 0006 D7-B).
#
# ⚠️ 왜 필요한가
#
#    생성기 8종은 Swift 헬퍼로 이관됐다(M2·M3). 그런데 가드는 계속 python3 을
#    요구하고 있었다 — **돌 수 있는 기능을 막고 있었다.** 사용자에게는
#    그냥 버그다.
#
# ⚠️ 문서로 주장하지 않는다. **python3 이 없는 PATH** 를 만들어 실제로 돌린다.
#
# ⚠️ 반대 방향도 본다: 헬퍼가 없고 python3 만 있는 환경(폴백)도 그대로
#    돌아야 한다. 한쪽을 고치며 다른 쪽을 깨는 것이 이 저장소의 단골 결함이다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── python3 이 없는 PATH 를 만든다 ──────────────────────────────────────────
#
# ⚠️ 실제 시스템은 건드리지 않는다. 필요한 도구만 심볼릭 링크한 디렉터리다.
NOPY="$TMP/nopy"
mkdir -p "$NOPY"
for t in bash sh awk sed grep cut head tail tr cat dirname basename printf \
         mktemp rm date sort uniq wc find ls cp mv chmod mkdir id od stat \
         jq git md5 shasum readlink env touch rmdir diff cmp comm expr \
         xargs sleep test true false pwd rsync; do
  tp=$(command -v "$t" 2>/dev/null) && ln -sf "$tp" "$NOPY/$t"
done

t_start "전제 — 이 PATH 에 python3 이 없다"
# ⚠️ 이게 깨지면 아래 전부가 헛돈다.
t_eq "python3 을 못 찾는다" "" \
  "$(env -i PATH="$NOPY" "$NOPY/bash" -c 'command -v python3' 2>/dev/null)"
t_eq "jq 는 있다" "0" \
  "$(env -i PATH="$NOPY" "$NOPY/bash" -c 'jq --version >/dev/null' 2>/dev/null; echo $?)"

HELPER=$(cd "$ROOT" && . lib/common.sh >/dev/null 2>&1; dt_helper 2>/dev/null)
t_eq "헬퍼가 있다" "yes" "$([ -n "$HELPER" ] && [ -x "$HELPER" ] && echo yes || echo no)"

if [ -z "$HELPER" ]; then
  dim "   헬퍼가 없어 건너뜁니다 — (cd app && swift build)"
  t_end
  exit 0
fi

VAULT="$TMP/vault"
HOME_D="$TMP/home"
CFG="$TMP/config.json"
mkdir -p "$VAULT/notes" "$VAULT/.obsidian" "$HOME_D"
printf '# 노트\n' > "$VAULT/notes/a.md"
jq -n --arg v "$VAULT" '{
  version: 3, vault: { backend: "local", path: $v, root: "notes" },
  dirs: {}, headings: { issues_pr: "## Issues / PRs", worklog: "## Work log" },
  github: { user: "qa", repos: [], project_groups: {} },
  ai: { provider: "claude", summary_enabled: false },
  install: { mode: "new", modules: ["devlog"] }
}' > "$CFG"

# python3 없이 devtrail 을 돌린다.
nopy() {
  env -i PATH="$NOPY" HOME="$HOME_D" \
    DEVTRAIL_HOME="$HOME_D/.devtrail" DEVTRAIL_CONFIG="$CFG" \
    DT_HELPER_OVERRIDE="$HELPER" \
    "$NOPY/bash" "$ROOT/bin/devtrail" "$@" 2>&1
}

t_start "⚠️ python3 없이 돈다"
# ⚠️ 종료코드만 보지 않는다. "도구 없음" 으로 막힌 것인지 구별한다 —
#    그 메시지가 나오면 가드가 여전히 막고 있다는 뜻이다.
for c in "version" "scan" "augment" "path"; do
  # shellcheck disable=SC2086
  out=$(nopy $c); rc=$?
  t_eq "$c — 'python3 없음' 으로 막히지 않는다" "0" \
    "$(printf '%s' "$out" | grep -c 'python3' | tr -d ' ')"
  case "$c" in
    version|scan|path)
      t_eq "$c — 성공한다" "0" "$rc" ;;
  esac
done

t_start "⚠️ obsidian apply 가 python3 없이 **실제로 쓴다**"
# ⚠️ 종료코드 0 으로는 부족하다. 병합기들이 dt_gen 을 거치므로, 헬퍼가
#    돌지 않으면 아무것도 안 만들고도 0 으로 끝날 수 있다 — **산출물을 본다.**
OUT=$(nopy obsidian); RC=$?
t_eq "성공한다" "0" "$RC"
t_eq "'python3 없음' 으로 막히지 않는다" "0" \
  "$(printf '%s' "$OUT" | grep -c 'python3' | tr -d ' ')"
t_eq "hotkeys.json 이 생겼다" "yes" \
  "$([ -f "$VAULT/.obsidian/hotkeys.json" ] && echo yes || echo no)"
t_eq "그 내용이 올바른 JSON 이다" "0" \
  "$(jq -e . "$VAULT/.obsidian/hotkeys.json" >/dev/null 2>&1; echo $?)"
t_eq "되돌릴 수 있게 기록됐다" "1" \
  "$(printf '%s\n' "$OUT" | grep -c '되돌리기: devtrail undo' | tr -d ' ')"

t_start "⚠️ 캡처 렌더가 python3 없이 돈다"
# ⚠️ 이건 생성기가 아니라 인라인 python 이었다. awk 로 옮겼다.
TPL="$ROOT/preset/templates/ko/유튜브 노트 템플릿.md"
if [ -f "$TPL" ]; then
  RENDER=$(env -i PATH="$NOPY" HOME="$HOME_D" "$NOPY/bash" -c '
    . "$1/lib/common.sh" >/dev/null 2>&1
    . "$1/lib/capturecmd.sh" >/dev/null 2>&1
    _cap_render "$2" "제목 & 특수문자" "https://y/x?a=1&b=2" "채널" 2026-08-24 "2026-08-24 14:30"
  ' _ "$ROOT" "$TPL" 2>&1)
  RC=$?
  t_eq "성공한다" "0" "$RC"
  t_eq "제목이 들어갔다" "1" \
    "$(printf '%s\n' "$RENDER" | grep -c '제목 & 특수문자' | tr -d ' ')"
  t_eq "날짜가 치환됐다" "0" \
    "$(printf '%s\n' "$RENDER" | grep -c 'tp\.date\.now' | tr -d ' ')"
  t_eq "url 이 채워졌다" "1" \
    "$(printf '%s\n' "$RENDER" | grep -c '^url: https://y/x?a=1&b=2$' | tr -d ' ')"
fi

t_start "⚠️ URL 인코딩이 python3 없이 된다"
# ⚠️ 예전에는 python3 만 이 일을 했고, 없으면 **볼트를 지정하지 못한 채**
#    Obsidian 만 열렸다.
t_eq "jq 로 인코딩한다" "%2FUsers%2Fa%2F%ED%95%9C%EA%B8%80%20%EB%B3%BC%ED%8A%B8" \
  "$(env -i PATH="$NOPY" "$NOPY/jq" -rn --arg s '/Users/a/한글 볼트' '$s|@uri')"
# ⚠️ 소스가 실제로 jq 를 쓰는지 본다 (명령 자리).
t_eq "obsidian_app.sh 가 jq 를 쓴다" "1" \
  "$(grep -vE '^\s*#' "$ROOT/lib/obsidian_app.sh" | grep -c "jq -rn --arg s" | tr -d ' ')"

t_start "⚠️ 폴백도 회귀하지 않는다 (헬퍼 없이 python3 만)"
# ⚠️ 한쪽을 고치며 다른 쪽을 깨는 것이 이 저장소의 단골 결함이다.
#    헬퍼가 없는 기계에서는 여전히 python3 으로 돌아야 한다.
FAKEROOT="$TMP/fakeroot"
mkdir -p "$FAKEROOT"
cp -R "$ROOT/bin" "$ROOT/lib" "$ROOT/preset" "$ROOT/VERSION" "$FAKEROOT/" 2>/dev/null
# ⚠️ app/.build 가 없는 뿌리다 — dt_helper 의 3순위가 안 걸린다.
t_eq "이 뿌리에는 헬퍼가 없다" "1" \
  "$(DT_HELPER_OVERRIDE= DEVTRAIL_ROOT="$FAKEROOT" bash -c \
      '. "$1/lib/common.sh" >/dev/null 2>&1; dt_helper >/dev/null 2>&1; echo $?' _ "$FAKEROOT")"
t_eq "python3 폴백으로 scan 이 돈다" "0" \
  "$(DEVTRAIL_HOME="$HOME_D/.devtrail" DEVTRAIL_CONFIG="$CFG" DT_HELPER_OVERRIDE= \
     "$FAKEROOT/bin/devtrail" scan >/dev/null 2>&1; echo $?)"

t_start "⚠️ 헬퍼도 python3 도 없으면 분명히 말한다"
# ⚠️ 조용히 실패하지 않는다. 무엇이 없는지 말해야 사용자가 고칠 수 있다.
MSG=$(env -i PATH="$NOPY" HOME="$HOME_D" \
  DEVTRAIL_HOME="$HOME_D/.devtrail" DEVTRAIL_CONFIG="$CFG" DT_HELPER_OVERRIDE= \
  "$NOPY/bash" "$FAKEROOT/bin/devtrail" scan 2>&1)
RC=$?
t_eq "실패로 끝난다" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
t_eq "무엇이 없는지 말한다" "1" \
  "$(printf '%s\n' "$MSG" | grep -c '헬퍼도 python3 도 없습니다\|생성기가 없습니다' | tr -d ' ')"

t_end
