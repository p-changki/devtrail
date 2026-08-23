#!/usr/bin/env bash
# 설정의 언어가 python 생성기까지 **실제로 전달되는가**.
#
# ⚠️ 왜 생겼나 (2026-08-23, ADR 0006 D6)
#
#    python 생성기들은 DEVTRAIL_LANG 환경변수로만 언어를 안다
#    (lib/gen/i18n.py: os.environ.get("DEVTRAIL_LANG", "ko")). 설정 파일을
#    인자로 받지만 거기서 lang 을 읽지 않는다.
#
#    그런데 그 변수를 export 하던 곳은 init.sh 와 setup/spec.sh 둘뿐이었다.
#    `devtrail obsidian apply` 처럼 그 둘을 안 거치는 경로에서는:
#
#      셸  : dt_lang() → 설정을 읽어 en
#      python: 기본값 ko
#
#    결과 — 영어 사용자의 Templater 설정에 templates_folder 가 "템플릿" 으로
#    박혔다. 그 볼트에 **없는 폴더**다. 에러는 나지 않는다.
#
# ⚠️ 여기서는 문자열이 아니라 **실제 서브프로세스에 전달되는 값**을 본다.
#    "export 하는 줄이 있다" 는 단언은 그 줄이 도는지 말해 주지 않는다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"

# 설정만 다른 두 집을 만든다.
mk_home() {   # mk_home <언어>
  # ⚠️ local a=$1 b=$a 로 쓰지 않는다. 같은 local 문 안에서 앞 변수를
  #    참조하면 값이 안 잡힌다 — 이 저장소가 lint 로 막는 패턴이고,
  #    2026-08-23 에 이 테스트에서 실제로 당했다.
  local lang="$1"
  local home="$T_TMP/home-$lang"
  mkdir -p "$home" "$T_TMP/vault-$lang/notes"
  jq -n --arg v "$T_TMP/vault-$lang" --arg l "$lang" '{
    version: 3, lang: $l,
    vault: { backend: "local", path: $v, root: "notes" },
    dirs: {}, headings: { issues_pr: "## Issues / PRs", worklog: "## Work log" },
    github: { user: "t", repos: [], project_groups: {} },
    ai: { provider: "claude", summary_enabled: false },
    install: { mode: "new", modules: ["devlog"] }
  }' > "$home/devtrail.config.json"
  printf '%s' "$home"
}

# ⚠️ 자식이 **실제로 받는** DEVTRAIL_LANG 을 찍는다. CLI 를 그대로 태우되
#    명령 하나를 실행시켜 그 안에서 환경을 들여다본다.
seen_lang() {   # seen_lang <home>
  local home="$1"
  env -u DEVTRAIL_LANG \
    DEVTRAIL_HOME="$home" DEVTRAIL_CONFIG="$home/devtrail.config.json" \
    /bin/bash -c '
      . "$1/lib/common.sh" >/dev/null 2>&1
      # 서브프로세스가 보는 값 — python 이 보는 것과 같은 경로다.
      python3 -c "import os; print(os.environ.get(\"DEVTRAIL_LANG\", \"(없음)\"))"
    ' _ "$ROOT" 2>/dev/null
}

t_start "설정 언어가 서브프로세스까지 전달된다"
HKO=$(mk_home ko)
HEN=$(mk_home en)
t_eq "설정이 ko 면 자식도 ko" "ko" "$(seen_lang "$HKO")"
t_eq "설정이 en 이면 자식도 en" "en" "$(seen_lang "$HEN")"

t_start "바깥에서 넘긴 일회성 지정을 덮어쓰지 않는다"
# ⚠️ dt_lang 은 DEVTRAIL_LANG 을 1순위로 읽는다. 그 계약을 깨면 안 된다 —
#    `DEVTRAIL_LANG=en devtrail …` 로 한 번만 확인하는 길이 막힌다.
OVERRIDE=$(DEVTRAIL_LANG=en DEVTRAIL_HOME="$HKO" \
  DEVTRAIL_CONFIG="$HKO/devtrail.config.json" \
  /bin/bash -c '
    . "$1/lib/common.sh" >/dev/null 2>&1
    python3 -c "import os; print(os.environ[\"DEVTRAIL_LANG\"])"
  ' _ "$ROOT" 2>/dev/null)
t_eq "설정이 ko 여도 넘긴 en 이 이긴다" "en" "$OVERRIDE"

t_start "생성기가 실제로 그 언어로 만든다"
# ⚠️ 환경변수가 전달되는 것과 **출력이 달라지는 것**은 다른 문제다.
#    hotkeys 의 templater 모드는 templates_folder 를 언어에 따라 정한다.
PATHS="$T_TMP/paths.json"
printf '%s' '{"templates":"notes/템플릿","devlog":"notes/d","weekly":"notes/w","projects":"notes/p"}' > "$PATHS"
TMPL="$ROOT/preset/obsidian/hotkeys.tmpl.json"

folder() {   # folder <home>
  local home="$1"
  env -u DEVTRAIL_LANG \
    DEVTRAIL_HOME="$home" DEVTRAIL_CONFIG="$home/devtrail.config.json" \
    /bin/bash -c '
      . "$1/lib/common.sh" >/dev/null 2>&1
      python3 "$1/lib/gen/hotkeys.py" templater "$2" "$3" "" 2>/dev/null \
        | jq -r ".templates_folder // \"(없음)\""
    ' _ "$ROOT" "$TMPL" "$PATHS" 2>/dev/null
}

KO_F=$(folder "$HKO")
EN_F=$(folder "$HEN")
t_eq "ko 설정 → 한국어 폴더" "템플릿" "$KO_F"
t_eq "en 설정 → 영어 폴더" "Templates" "$EN_F"
# ⚠️ 둘이 같으면 위 두 단언 중 하나가 우연히 맞은 것이다.
t_eq "두 언어가 다른 결과를 낸다" "different" \
  "$([ "$KO_F" = "$EN_F" ] && echo same || echo different)"

t_end
