#!/usr/bin/env bash
# `devtrail setup quick` — 앱의 간단 온보딩이 타는 길 (ADR 0006 M4-4c).
#
# ⚠️ 왜 이 명령이 있나
#
#    DMG 로 받은 비개발자에게 터미널 대화 13단계를 시키는 것이 지금 남은
#    가장 큰 벽이다. 앱이 언어·볼트만 받아 여기로 넘긴다.
#
# ⚠️ 지켜야 할 것은 **"앱으로 하면 다르다" 가 없는 것**이다. 적용 경로를 새로
#    만들지 않고 setup apply 에 넘긴다 — 대화형 init 이 타는 길과 같다.
#
# ⚠️ 실제 사용자 볼트·설정은 건드리지 않는다. 전부 임시 디렉터리다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

DT="$ROOT/bin/devtrail"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REAL_CFG="$HOME/.devtrail/devtrail.config.json"
if [ -f "$REAL_CFG" ]; then REAL_BEFORE=$(shasum -a 256 "$REAL_CFG" | cut -d' ' -f1)
else REAL_BEFORE="none"; fi

mkvault() {   # mkvault <이름> [노트수]
  local v="$TMP/$1" n="${2:-0}" i=0
  mkdir -p "$v"
  while [ "$i" -lt "$n" ]; do printf '# n%s\n' "$i" > "$v/n$i.md"; i=$((i + 1)); done
  printf '%s' "$v"
}
q() {   # q <볼트> <추가인자…>
  local v="$1"; shift
  DEVTRAIL_HOME="$TMP/home/.devtrail" DEVTRAIL_CONFIG="$TMP/cfg-$(basename "$v").json" \
    "$DT" setup quick --vault "$v" "$@" 2>&1 < /dev/null
}

t_start "스펙을 CLI 가 만든다 (앱이 조립하지 않는다)"
# ⚠️ 앱이 JSON 을 직접 만들면 스펙의 모양이 두 벌이 된다. 앱은 값 세 개만
#    넘기고, 완전한 스펙은 여기서 나와야 한다.
V1=$(mkvault v1)
SPEC=$(q "$V1" --lang ko --json)
t_eq "spec_version 이 붙는다" "1" "$(printf '%s' "$SPEC" | jq -r '.spec_version')"
t_eq "언어가 반영된다" "ko" "$(printf '%s' "$SPEC" | jq -r '.lang')"
t_eq "볼트 경로가 반영된다" "$V1" "$(printf '%s' "$SPEC" | jq -r '.vault.path')"
t_eq "기본 모듈이 채워진다" "devlog" "$(printf '%s' "$SPEC" | jq -r '.modules | join(",")')"
t_eq "AI 는 기본이 none" "none" "$(printf '%s' "$SPEC" | jq -r '.ai.provider')"

t_start "선택한 전체 설정을 같은 스펙 경로로 받는다"
FULL=$(q "$V1" --lang ko --mode existing --root 창기 --modules devlog,review,personal \
  --github-user qa-user --ai claude --src-root "$TMP" --sync-repos app-a,app-b \
  --projects app-a --json)
t_eq "루트가 반영된다" "창기" "$(printf '%s' "$FULL" | jq -r '.vault.root')"
t_eq "모듈이 반영된다" "devlog,personal,review" "$(printf '%s' "$FULL" | jq -r '.modules | sort | join(",")')"
t_eq "GitHub 사용자가 반영된다" "qa-user" "$(printf '%s' "$FULL" | jq -r '.github.user')"
t_eq "동기화 레포가 반영된다" "app-a,app-b" "$(printf '%s' "$FULL" | jq -r '.github.repos | join(",")')"
t_eq "AI가 반영된다" "claude" "$(printf '%s' "$FULL" | jq -r '.ai.provider')"

t_start "⚠️ 플러그인을 받지 않는다"
# ⚠️ 플러그인 설치는 GitHub 에서 내려받는다. **사용자 승인 없는 네트워크
#    요청을 하지 않는다** 는 약속이 있다. 그리고 대화형 경로는 여기서
#    묻는데(confirm), 터미널이 붙어 있으면 답을 기다리고 없으면 건너뛴다 —
#    tty 유무로 결과가 갈리는 길을 앱에 주지 않는다.
t_eq "bootstrap_plugins 가 false" "false" \
  "$(printf '%s' "$SPEC" | jq -r '.bootstrap_plugins')"
# ⚠️ 값만 보지 않는다. **묻지 않는 것**까지 본다 — 적용 출력에 설치 동의를
#    구하는 화면이 나오면 안 된다.
VP=$(mkvault vplug)
POUT=$(q "$VP" --lang ko --apply)
t_eq "설치 동의를 묻지 않는다" "0" \
  "$(printf '%s\n' "$POUT" | grep -c '설치할까요' | tr -d ' ')"
t_eq "플러그인 목록 화면이 안 뜬다" "0" \
  "$(printf '%s\n' "$POUT" | grep -c 'obsidian-dataview' | tr -d ' ')"

t_start "⚠️ dry-run 이 기본이다"
# ⚠️ --apply 없이 아무것도 바꾸지 않아야 한다. 앱이 "무엇이 될지" 를 먼저
#    보여줄 수 있어야 하고, 실수로 볼트가 바뀌면 안 된다.
V2=$(mkvault v2)
q "$V2" --lang ko >/dev/null 2>&1
t_eq "설정 파일을 만들지 않는다" "no" \
  "$([ -f "$TMP/cfg-v2.json" ] && echo yes || echo no)"
t_eq "볼트를 건드리지 않는다" "0" \
  "$(find "$V2" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"

t_start "--apply 가 실제로 만든다"
V3=$(mkvault v3)
OUT=$(q "$V3" --lang ko --apply)
t_eq "설정 파일이 생긴다" "yes" "$([ -f "$TMP/cfg-v3.json" ] && echo yes || echo no)"
t_eq "볼트 구조가 생긴다" "yes" \
  "$([ "$(find "$V3" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" -gt 5 ] && echo yes || echo no)"
# ⚠️ 되돌릴 수 있어야 한다. 되돌릴 수 없는 변경을 앱 버튼 하나에 걸지 않는다.
t_eq "되돌리기 안내가 나온다" "1" \
  "$(printf '%s\n' "$OUT" | grep -c '되돌리기: devtrail undo' | tr -d ' ')"
# ⚠️ 플러그인은 정말로 안 받았는가 (말이 아니라 산출물로)
t_eq "플러그인을 받지 않았다" "0" \
  "$(find "$V3/.obsidian/plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

t_start "⚠️ 설치 방식을 노트 수로 제안한다 (대화형과 같은 기준)"
# ⚠️ 대화형 _init_mode 는 노트 10개를 경계로 쓴다. 기준이 갈리면 "앱으로
#    하면 다르게 잡힌다" 가 된다.
VE=$(mkvault vempty 0)
VF=$(mkvault vfull 12)
t_eq "빈 볼트 → new" "new" "$(q "$VE" --json | jq -r '.vault.mode')"
t_eq "노트 12개 → existing" "existing" "$(q "$VF" --json | jq -r '.vault.mode')"
# 사용자가 정하면 그것을 따른다.
t_eq "--mode 로 덮어쓸 수 있다" "isolated" \
  "$(q "$VE" --mode isolated --json | jq -r '.vault.mode')"

t_start "잘못된 입력을 분명히 막는다"
t_eq "볼트 없이 부르면 실패" "1" \
  "$(DEVTRAIL_HOME="$TMP/home/.devtrail" "$DT" setup quick >/dev/null 2>&1; echo $?)"
t_eq "상대경로를 막는다" "1" \
  "$(DEVTRAIL_HOME="$TMP/home/.devtrail" "$DT" setup quick --vault relative/path >/dev/null 2>&1; echo $?)"
t_eq "모르는 언어를 막는다" "1" \
  "$(q "$VE" --lang fr >/dev/null 2>&1; echo $?)"
t_eq "모르는 모드를 막는다" "1" \
  "$(q "$VE" --mode 아무거나 >/dev/null 2>&1; echo $?)"

t_start "⚠️ 기본값이 두 벌이 아니다"
# ⚠️ quick 이 자기 기본값을 갖기 시작하면 대화형과 갈린다. 손으로 만든
#    최소 스펙을 sp_normalize 에 먹인 결과와 **같아야** 한다.
HAND="$TMP/hand.json"
jq -n --arg p "$V1" '{spec_version:1, lang:"ko",
  vault:{backend:"local", path:$p, root:"", mode:"new"}, bootstrap_plugins:false}' > "$HAND"
NORM=$(DEVTRAIL_HOME="$TMP/home/.devtrail" bash -c '
  . "$1/lib/common.sh" >/dev/null 2>&1
  . "$1/lib/setup/spec.sh" >/dev/null 2>&1
  sp_normalize "$2"' _ "$ROOT" "$HAND")
t_eq "quick 의 스펙 == 정규화한 최소 스펙" \
  "$(printf '%s' "$NORM" | jq -S -c .)" \
  "$(printf '%s' "$SPEC" | jq -S -c .)"

t_start "⚠️ 실제 사용자 설정이 그대로다"
if [ -f "$REAL_CFG" ]; then REAL_AFTER=$(shasum -a 256 "$REAL_CFG" | cut -d' ' -f1)
else REAL_AFTER="none"; fi
t_eq "~/.devtrail/devtrail.config.json 이 그대로다" "$REAL_BEFORE" "$REAL_AFTER"

t_end
