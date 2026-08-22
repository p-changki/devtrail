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
# ⚠️ --apply 없이 부르면 plan 과 같은 화면을 낸다. dry-run 화면을 따로
#    만들면 "미리 본 것" 과 "실제로 되는 것" 이 갈린다.
# ⚠️ L 은 CLI 안에서만 사는 함수다. 테스트에서 부르면 빈 문자열이 되어
#    단언이 아무것도 검사하지 않는다 — 실제 문구를 그대로 적는다.
t_contains "무엇이 바뀌는지 보여준다" "적용하면 이렇게 됩니다" "$out"
t_contains "적용 방법을 알려준다" "--apply" "$out"
t_no_file "설정을 쓰지 않는다" "$H0/devtrail.config.json"
t_no_file "볼트를 만들지 않는다" "$V0/notes"

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

# ── plan ─────────────────────────────────────────────────────────────────────
#
# 앱은 "무엇이 바뀌는가" 를 사용자에게 보여준 뒤 동의를 받는다. 그 판단의
# 근거가 이 출력이다.
#
# ⚠️ plan 은 아무것도 쓰지 않는다. 여기서 파일이 생기면 "먼저 보여준다" 는
#    약속이 거짓이 된다.
t_start "plan 은 아무것도 쓰지 않는다"
VP="$T_TMP/vp"; HP="$T_TMP/hp"; mkdir -p "$HP"
jq -n --arg v "$VP" '{spec_version:1, lang:"ko",
  vault:{backend:"local", path:$v, root:"notes", mode:"new"},
  modules:["devlog"], github:{user:"t"}, ai:{provider:"none"},
  bootstrap_plugins:false}' > "$T_TMP/plan-spec.json"

out=$(DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
      "$DT" setup plan --input "$T_TMP/plan-spec.json" --json 2>/dev/null)
printf '%s' "$out" > "$T_TMP/plan.json"
t_json "유효한 JSON" "$T_TMP/plan.json"
t_no_file "설정을 쓰지 않는다" "$HP/devtrail.config.json"
t_no_file "볼트를 만들지 않는다" "$VP/notes"
t_no_file "스크립트를 만들지 않는다" "$HP/scripts"

t_start "plan 이 무엇이 바뀌는지 말한다"
t_eq "valid"           "true"  "$(jq -r '.valid' "$T_TMP/plan.json")"
t_eq "undo_available"  "true"  "$(jq -r '.undo_available' "$T_TMP/plan.json")"
t_eq "설치 방식"       "new"   "$(jq -r '.mode' "$T_TMP/plan.json")"

# 빈 볼트에 새로 설치하면 만들 폴더가 있어야 한다.
t_eq "폴더를 만들 계획이 있다" "true" \
  "$(jq '(.changes.folders_create | length) > 0' "$T_TMP/plan.json")"
t_contains "개발일지 폴더가 들어 있다" "개발일지" \
  "$(jq -r '.changes.folders_create | join(",")' "$T_TMP/plan.json")"
t_eq "템플릿을 깔 계획이 있다" "true" \
  "$(jq '(.changes.templates_create | length) > 0' "$T_TMP/plan.json")"
# 프로파일이 병합하는 대상이 그대로 나와야 한다.
t_contains "app.json 병합" "app.json" \
  "$(jq -r '.changes.settings_merge | join(",")' "$T_TMP/plan.json")"
# ⚠️ 자동 이동은 새로 만든 노트에만 적용된다. 기존 노트를 옮기지 않는다.
t_eq "노트를 옮기지 않는다" "0" \
  "$(jq '.changes.notes_move | length' "$T_TMP/plan.json")"
# bootstrap_plugins:false 면 받을 것이 없다.
t_eq "플러그인을 받지 않는다" "0" \
  "$(jq '.changes.plugins_install | length' "$T_TMP/plan.json")"

# ⚠️ 이미 있는 것을 '만들 것' 으로 세면 계획이 규모를 부풀린다. 사용자는
#    멀쩡한 볼트를 보고 "이게 다 새로 생긴다고?" 하며 겁을 먹는다.
t_start "plan 은 이미 있는 것을 세지 않는다"
VQ="$T_TMP/vq"; mkdir -p "$VQ/notes"
jq --arg v "$VQ" '.vault.path = $v' "$T_TMP/plan-spec.json" > "$T_TMP/plan-q.json"

# 먼저 계획을 받아 '만들 폴더' 하나를 고른다.
q1=$(DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
     "$DT" setup plan --input "$T_TMP/plan-q.json" --json 2>/dev/null)
printf '%s' "$q1" > "$T_TMP/q1.json"
first=$(jq -r '.changes.folders_create[0]' "$T_TMP/q1.json")
n1=$(jq '.changes.folders_create | length' "$T_TMP/q1.json")
t_ne "만들 폴더가 있다" "" "$first"

# 그 폴더를 미리 만들어 두고 다시 계획을 받는다.
mkdir -p "$VQ/$first"
q2=$(DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
     "$DT" setup plan --input "$T_TMP/plan-q.json" --json 2>/dev/null)
printf '%s' "$q2" > "$T_TMP/q2.json"
n2=$(jq '.changes.folders_create | length' "$T_TMP/q2.json")

t_eq "하나 줄어든다" "$((n1 - 1))" "$n2"
t_not_contains "이미 있는 폴더는 빠진다" "$first" \
  "$(jq -r '.changes.folders_create | join("\n")' "$T_TMP/q2.json")"

# 템플릿도 같다.
tdir=$(jq -r '.changes.templates_create[0]' "$T_TMP/q1.json")
if [ -n "$tdir" ] && [ "$tdir" != "null" ]; then
  mkdir -p "$VQ/$(dirname "$tdir")"; printf 'x' > "$VQ/$tdir"
  q3=$(DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
       "$DT" setup plan --input "$T_TMP/plan-q.json" --json 2>/dev/null)
  printf '%s' "$q3" > "$T_TMP/q3.json"
  t_not_contains "이미 있는 템플릿은 빠진다" "$tdir" \
    "$(jq -r '.changes.templates_create | join("\n")' "$T_TMP/q3.json")"
fi

t_start "plan 이 위험을 말한다"
# 새로 시작 = 자동 이동 Automatic. 사용자가 알아야 한다.
t_eq "위험을 하나 이상 말한다" "true" \
  "$(jq '(.risks | length) > 0' "$T_TMP/plan.json")"

# 기존 볼트에 얹으면 자동 이동이 Manual 로 시작한다 — 다른 위험이다.
jq '.vault.mode = "existing"' "$T_TMP/plan-spec.json" > "$T_TMP/plan-ex.json"
ex=$(DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
     "$DT" setup plan --input "$T_TMP/plan-ex.json" --json 2>/dev/null)
printf '%s' "$ex" > "$T_TMP/plan-ex-out.json"
t_eq "얹기 모드로 읽힌다" "existing" "$(jq -r '.mode' "$T_TMP/plan-ex-out.json")"
t_contains "Manual 이라고 밝힌다" "Manual" \
  "$(jq -r '.risks | join(" ")' "$T_TMP/plan-ex-out.json")"

t_start "plan 이 잘못된 스펙을 거절한다"
t_exit "spec_version 이 틀리면 실패" 1 \
  env DEVTRAIL_HOME="$HP" DEVTRAIL_CONFIG="$HP/devtrail.config.json" \
  "$DT" setup plan --input "$BAD"

# ── env: Wizard 화면 0 이 쓸 환경 확인 ──────────────────────────────────────
#
# 앱이 "지금 무엇이 준비됐나" 를 물을 때 쓴다.
#
# ⚠️ 앱이 Obsidian.app 존재나 gh 인증을 직접 확인하기 시작하면 판정이 두 곳이
#    된다. CLI 가 답하고 앱은 화면만 그린다.
t_start "setup env --json"
e=$(DEVTRAIL_HOME="$T_TMP/none" DEVTRAIL_CONFIG="$T_TMP/none/x.json" \
    "$DT" setup env --json 2>/dev/null)
printf '%s' "$e" > "$T_TMP/env.json"
t_json "유효한 JSON" "$T_TMP/env.json"

# 앱이 화면 0 에서 판단할 것들
for k in obsidian_installed obsidian_running configured; do
  t_ne "$k 가 있다" "null" "$(jq -r ".$k" "$T_TMP/env.json")"
done
t_ne "필수 도구 상태가 있다" "null" "$(jq -r '.tools' "$T_TMP/env.json")"
for t in jq git python3; do
  t_ne "도구 $t" "null" "$(jq -r ".tools.\"$t\"" "$T_TMP/env.json")"
done
t_eq "설정이 없으면 configured=false" "false" "$(jq -r '.configured' "$T_TMP/env.json")"
t_ne "볼트 후보 목록이 있다" "null" "$(jq -r '.vaults' "$T_TMP/env.json")"

# ⚠️ 레지스트리를 갈아끼울 수 있어야 테스트가 실행 머신의 진짜 볼트를 읽지 않는다.
REG="$T_TMP/reg.json"
mkdir -p "$T_TMP/vv1" "$T_TMP/vv2"
jq -n --arg a "$T_TMP/vv1" --arg b "$T_TMP/vv2" --arg c "$T_TMP/gone" \
  '{vaults: {a: {path: $a, ts: 3}, b: {path: $b, ts: 2}, c: {path: $c, ts: 1}}}' > "$REG"
e2=$(DEVTRAIL_OBSIDIAN_REGISTRY="$REG" DEVTRAIL_HOME="$T_TMP/none" \
     DEVTRAIL_CONFIG="$T_TMP/none/x.json" "$DT" setup env --json 2>/dev/null)
printf '%s' "$e2" > "$T_TMP/env2.json"
t_eq "있는 볼트만 센다" "2" "$(jq '.vaults | length' "$T_TMP/env2.json")"
t_contains "볼트 경로가 나온다" "vv1" "$(jq -r '.vaults[].path' "$T_TMP/env2.json")"
# 화면 1 은 "노트 몇 개인지" 를 보여준다.
t_ne "노트 수를 센다" "null" "$(jq -r '.vaults[0].notes' "$T_TMP/env2.json")"
# 사라진 볼트를 목록에 보여주면 고르고 나서 실패한다.
t_not_contains "사라진 볼트는 빠진다" "gone" "$(jq -r '.vaults[].path' "$T_TMP/env2.json")"

t_end
