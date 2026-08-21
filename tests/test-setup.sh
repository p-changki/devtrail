#!/usr/bin/env bash
# devtrail setup — 비대화형 셋업 계약.
#
# 여기서 지키는 것은 하나다:
#
#   같은 입력이면 대화형 init 과 비대화형 setup apply 가 같은 결과를 낸다.
#
# 앱·CI·테스트가 쓸 통로를 만들면서 적용 로직을 두 벌로 나누면, 언젠가
# 한쪽만 고쳐지고 사용자는 "앱으로 하면 다르다" 를 만난다. 2026-08-22 QA 에서
# 잡은 결함 9건 중 4건이 정확히 그 유형이었다 — 같은 것이 두 곳에 있었다.
#
# ⚠️ 이 테스트가 잡는 것과 못 잡는 것:
#
#   잡는다  두 적용 경로가 갈리는 것 (init 만 뭔가 더/덜 하는 것)
#   잡는다  스펙과 실제 적용값이 어긋나는 것
#   못 잡는다  대화형 '수집' 이 답을 스펙으로 잘못 옮기는 것
#
#   마지막 것은 키 입력 순서를 세야 확인되는데, 질문이 하나 늘거나 조건부로
#   건너뛰면 테스트가 엉뚱한 답을 먹고 조용히 다른 것을 비교한다(실제로 그랬다).
#   그래서 흔들리지 않는 답 네 가지(볼트 경로·루트·언어·설치 방식)만 값으로
#   못박고, 나머지는 '스펙과 결과가 서로를 설명하는가' 로 확인한다.
#
# ⚠️ 네트워크를 쓰지 않는다. 플러그인 설치는 bootstrap_plugins:false 로 끈다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"
export DEVTRAIL_ROOT="$ROOT"
unset DEVTRAIL_JOURNAL

# 실행 머신의 진짜 Obsidian 볼트 목록을 읽지 않도록 고정한다.
export DEVTRAIL_OBSIDIAN_REGISTRY="$T_TMP/no-registry.json"

# ── 스펙 ─────────────────────────────────────────────────────────────────────
_spec() {
  local vault="$1"
  jq -n --arg v "$vault" '{
    spec_version: 1,
    lang: "ko",
    vault: { backend: "local", path: $v, root: "notes", mode: "new" },
    dirs: {},
    modules: ["devlog"],
    github: { user: "tester", src_root: "/tmp", repos: [], project_groups: {} },
    ai: { provider: "none" },
    bootstrap_plugins: false
  }'
}

# 비교 대상에서 빼야 하는 것 — 시각·머신 경로처럼 매번 다른 값.
_normalize_config() {
  jq -S 'del(.bin) | del(.backup.repo_path) | .vault.path = "<VAULT>"' "$1"
}

_tree() {
  ( cd "$1" && find . -mindepth 1 | sed "s|^\./||" | LC_ALL=C sort )
}

# ── 명령 표면 ────────────────────────────────────────────────────────────────
t_start "명령 표면"
t_contains "usage 에 있다" "devtrail setup" "$("$DT" help 2>&1)"
t_contains "알 수 없는 하위 명령 거절" "알 수 없는 하위 명령" \
  "$(DEVTRAIL_CONFIG=/dev/null "$DT" setup nonsense 2>&1)"

# ── 스펙 검증 ────────────────────────────────────────────────────────────────
#
# ⚠️ 잘못된 스펙으로 절반만 적용되면 사용자는 반쯤 망가진 볼트를 갖게 된다.
#    검증에 실패하면 아무것도 쓰지 않는다.
t_start "스펙 검증"
BAD="$T_TMP/bad.json"

printf '%s' 'not json' > "$BAD"
t_exit "JSON 이 아니면 거절" 1 "$DT" setup apply --input "$BAD"

jq -n '{spec_version: 1, lang: "ko"}' > "$BAD"
t_contains "볼트 경로가 없으면 말해준다" "vault" \
  "$("$DT" setup apply --input "$BAD" 2>&1)"

jq -n --arg v "$T_TMP/v-bad" '{spec_version: 99, lang: "ko",
  vault: {backend:"local", path:$v, root:"notes", mode:"new"}}' > "$BAD"
t_contains "모르는 spec_version 은 거절" "spec_version" \
  "$("$DT" setup apply --input "$BAD" 2>&1)"
t_no_file "거절되면 아무것도 안 만든다" "$T_TMP/v-bad/notes"

t_start "apply 는 dry-run 이 기본"
V0="$T_TMP/v0"; H0="$T_TMP/h0"; mkdir -p "$V0" "$H0"
_spec "$V0" > "$T_TMP/spec0.json"
out=$(DEVTRAIL_HOME="$H0" DEVTRAIL_CONFIG="$H0/devtrail.config.json" \
      "$DT" setup apply --input "$T_TMP/spec0.json" 2>&1)
t_contains "dry-run 이라고 밝힌다" "dry-run" "$out"
t_no_file "설정을 쓰지 않는다" "$H0/devtrail.config.json"

# ── 계약: init == setup apply ────────────────────────────────────────────────
#
# 이 테스트가 이 파일의 존재 이유다.
#
# ⚠️ 키 입력을 세어 두 경로를 재현하지 않는다. 질문이 하나 늘거나 조건부로
#    건너뛰면 테스트가 엉뚱한 답을 먹고 조용히 다른 것을 비교한다 —
#    실제로 그랬다(레포 목록 질문이 gh 를 타서 답이 한 칸씩 밀렸다).
#
# 대신 라운드트립으로 확인한다:
#    ① 대화형 init 을 돌린다 → init 이 쓴 스펙이 남는다
#    ② 그 스펙을 setup apply 에 그대로 먹인다
#    ③ 두 결과가 같아야 한다
# 두 경로가 갈리면 여기서 잡힌다.
t_start "대화형 init 과 결과가 같다"

VA="$T_TMP/va"; HA="$T_TMP/ha"; mkdir -p "$VA" "$HA"
VB="$T_TMP/vb"; HB="$T_TMP/hb"; mkdir -p "$VB" "$HB"

# ① 대화형. 답이 밀려도 상관없다 — 무엇을 골랐든 그 선택이 스펙에 남는다.
{ printf '1\n1\n%s\n2\nnotes\n1\n\n/tmp\n\n\nnone\n\n\n\n\n' "$VA"; } \
  | DEVTRAIL_HOME="$HA" DEVTRAIL_CONFIG="$HA/devtrail.config.json" \
    DEVTRAIL_SKILL_DIR="$HA/skills" \
    "$DT" init --no-bootstrap >/dev/null 2>&1

t_file "① 설정 생성" "$HA/devtrail.config.json"
t_file "① 스펙을 남긴다" "$HA/setup-spec.json"
t_json "① 스펙이 유효한 JSON" "$HA/setup-spec.json"

# ② 같은 스펙을 비대화형으로. 볼트 경로만 바꾼다.
jq --arg v "$VB" '.vault.path = $v | .bootstrap_plugins = false' \
  "$HA/setup-spec.json" > "$T_TMP/spec.json"
DEVTRAIL_HOME="$HB" DEVTRAIL_CONFIG="$HB/devtrail.config.json" \
  DEVTRAIL_SKILL_DIR="$HB/skills" \
  "$DT" setup apply --input "$T_TMP/spec.json" --apply >/dev/null 2>&1

t_file "② 설정 생성" "$HB/devtrail.config.json"

# ⚠️ 설정이 같아야 한다. 여기가 갈리면 앱과 CLI 가 다른 볼트를 만든다.
t_eq "설정 JSON 이 같다" \
  "$(_normalize_config "$HA/devtrail.config.json")" \
  "$(_normalize_config "$HB/devtrail.config.json")"

# ⚠️ 폴더 트리도 같아야 한다. 설정만 같고 산출물이 다르면 의미가 없다.
t_eq "볼트 트리가 같다" "$(_tree "$VA")" "$(_tree "$VB")"
t_eq "스크립트가 같다" \
  "$(cd "$HA/scripts" && ls | LC_ALL=C sort)" \
  "$(cd "$HB/scripts" && ls | LC_ALL=C sort)"

# 스펙도 다시 남아야 한다 — 비대화형으로 만든 볼트도 재현 가능해야 한다.
t_file "② 스펙을 남긴다" "$HB/setup-spec.json"

# ⚠️ 라운드트립만으로는 부족하다. init 이 스펙을 남긴 뒤 '스펙에 없는 것' 을
#    적용하면 두 결과가 같아도 계약은 깨진 것이다. 스펙과 설정이 서로를
#    설명하는지 확인한다 — 스펙이 곧 그 볼트의 근거여야 한다.
t_start "스펙이 결과를 설명한다"
SP="$HA/setup-spec.json"; CF="$HA/devtrail.config.json"
t_eq "spec_version"  "1"                        "$(jq -r '.spec_version' "$SP")"
t_eq "언어"          "$(jq -r '.lang' "$SP")"   "$(jq -r '.lang' "$CF")"
t_eq "볼트 경로"     "$(jq -r '.vault.path' "$SP")" "$(jq -r '.vault.path' "$CF")"
t_eq "루트"          "$(jq -r '.vault.root' "$SP")" "$(jq -r '.vault.root' "$CF")"
t_eq "백엔드"        "$(jq -r '.vault.backend' "$SP")" "$(jq -r '.vault.backend' "$CF")"
t_eq "설치 방식"     "$(jq -r '.vault.mode' "$SP")" "$(jq -r '.install.mode' "$CF")"
t_eq "모듈"          "$(jq -cS '.modules' "$SP")" "$(jq -cS '.install.modules' "$CF")"
t_eq "GitHub 계정"   "$(jq -r '.github.user' "$SP")" "$(jq -r '.github.user' "$CF")"

# 사용자가 실제로 답한 값이 스펙에 들어갔는가 — 여기가 흔들리면
# 앱이 같은 값을 줘도 다른 볼트가 만들어진다.
t_eq "답한 볼트 경로가 스펙에" "$VA"     "$(jq -r '.vault.path' "$SP")"
t_eq "답한 루트가 스펙에"      "notes"   "$(jq -r '.vault.root' "$SP")"
t_eq "답한 언어가 스펙에"      "ko"      "$(jq -r '.lang' "$SP")"
t_eq "답한 설치 방식이 스펙에" "new"     "$(jq -r '.vault.mode' "$SP")"

# ── status ───────────────────────────────────────────────────────────────────
t_start "status --json"
s=$(DEVTRAIL_HOME="$HB" DEVTRAIL_CONFIG="$HB/devtrail.config.json" \
    "$DT" setup status --json 2>/dev/null)
t_json_str() { printf '%s' "$1" > "$T_TMP/s.json"; t_json "$2" "$T_TMP/s.json"; }
t_json_str "$s" "유효한 JSON"
t_eq "설정됨으로 본다" "true"  "$(printf '%s' "$s" | jq -r '.configured')"
t_eq "볼트 경로"       "$VB"   "$(printf '%s' "$s" | jq -r '.vault.path')"
t_eq "언어"            "ko"    "$(printf '%s' "$s" | jq -r '.lang')"

s2=$(DEVTRAIL_HOME="$T_TMP/none" DEVTRAIL_CONFIG="$T_TMP/none/x.json" \
     "$DT" setup status --json 2>/dev/null)
t_eq "설정이 없으면 configured=false" "false" \
  "$(printf '%s' "$s2" | jq -r '.configured')"

t_end
