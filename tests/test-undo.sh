#!/usr/bin/env bash
# devtrail undo · 설정 마이그레이션.
#
# 이 두 기능은 남의 파일을 지우고 덮어쓴다. 여기가 틀리면 사용자가
# 노트를 잃는다 — 다른 어떤 검사보다 이쪽이 아프다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT

DT="$ROOT/bin/devtrail"

# 저널은 DEVTRAIL_HOME 아래에 산다. t_vault 가 home 을 격리하므로
# 저널도 자동으로 격리된다 — 다만 바깥에서 새어들어온 값은 지운다.
unset DEVTRAIL_JOURNAL
_jrdir() { printf '%s/journal' "$DEVTRAIL_HOME"; }
_last()  { ls -1 "$(_jrdir)" 2>/dev/null | tail -1; }

# ── 저널이 없으면 이력도 없다 ────────────────────────────────────────────────
t_start "빈 이력"
t_vault j0
t_config notes
t_contains "기록이 없다고 말한다" "기록이 없습니다" "$("$DT" undo 2>&1)"
t_exit "종료코드 0" 0 "$DT" undo

# ── augment 가 저널을 남긴다 ─────────────────────────────────────────────────
t_start "augment 가 저널을 남긴다"
t_vault j1
t_config notes

"$DT" augment --apply >/dev/null 2>&1
job=$(_last)
t_ne "작업이 하나 생겼다" "" "$job"
t_file "저널 항목" "$(_jrdir)/$job/entries.tsv"
t_json "메타가 유효한 JSON" "$(_jrdir)/$job/meta.json"
t_eq "명령 이름" "augment" "$(jq -r '.command' "$(_jrdir)/$job/meta.json")"

# 만든 것을 전부 기록해야 한다 — 하나라도 빠지면 undo 가 쓰레기를 남긴다
made=$(find "$T_VAULT" -mindepth 1 | wc -l | tr -d ' ')
logged=$(wc -l < "$(_jrdir)/$job/entries.tsv" | tr -d ' ')
t_eq "만든 것을 모두 기록" "$made" "$logged"

# ── dry-run 은 아무것도 안 바꾼다 ────────────────────────────────────────────
t_start "undo dry-run"
before=$(find "$T_VAULT" | wc -l | tr -d ' ')
out=$("$DT" undo "$job" 2>&1)
after=$(find "$T_VAULT" | wc -l | tr -d ' ')
t_eq "파일이 그대로" "$before" "$after"
t_contains "적용 방법을 안내" "--apply" "$out"

# ── --apply 가 실제로 되돌린다 ───────────────────────────────────────────────
t_start "undo --apply"
"$DT" undo "$job" --apply >/dev/null 2>&1
t_eq "볼트가 비었다" "0" "$(find "$T_VAULT" -mindepth 1 | wc -l | tr -d ' ')"
t_dir "볼트 자체는 남는다" "$T_VAULT"

# ── 사용자 노트는 절대 지우지 않는다 ─────────────────────────────────────────
# 이게 이 파일에서 가장 중요한 검사다.
t_start "사용자 노트 보존"
t_vault j2
t_config notes

"$DT" augment --apply >/dev/null 2>&1
# 경로를 박지 않는다 — 루트 이름은 설정에서 온다.
mine="$("$DT" path devnote)/내메모.md"
printf '# 내 노트\n' > "$mine"

out=$("$DT" undo "$(_last)" --apply 2>&1)
t_file "내 노트가 살아 있다" "$mine"
t_eq "내용이 그대로" "# 내 노트" "$(cat "$mine")"
t_contains "남겨뒀다고 말한다" "남겨둡니다" "$out"

# ── 없는 ID ──────────────────────────────────────────────────────────────────
t_start "없는 작업 ID"
t_exit "종료코드 1" 1 "$DT" undo 20990101-000000-1 --apply

# ── 설정 마이그레이션 ────────────────────────────────────────────────────────
t_start "스키마 마이그레이션"
t_vault m1
# 0.1.x 모양 — install 블록이 없다
printf '{"version":1,"vault":{"path":"%s","root":"창기"}}\n' "$T_VAULT" > "$DEVTRAIL_CONFIG"

# ⚠️ 목표 버전을 박지 않는다. 스키마를 올릴 때마다 테스트가 깨지면,
#    고치는 김에 단언을 느슨하게 만들게 된다. 코드에서 읽는다.
SCHEMA=$(grep -E '^DT_SCHEMA=' "$ROOT/lib/migrate.sh" | head -1 | cut -d= -f2)

out=$("$DT" config migrate 2>&1)
t_contains "올릴 것을 알린다" "1 → ${SCHEMA}" "$out"
t_eq "dry-run 은 안 바꾼다" "1" "$(jq -r '.version' "$DEVTRAIL_CONFIG")"

"$DT" config migrate --apply >/dev/null 2>&1
t_eq "버전이 올라간다" "$SCHEMA" "$(jq -r '.version' "$DEVTRAIL_CONFIG")"
t_eq "mode 기본값은 안전한 쪽" "existing" "$(jq -r '.install.mode' "$DEVTRAIL_CONFIG")"
t_eq "modules 기본값" "devlog" "$(jq -r '.install.modules[0]' "$DEVTRAIL_CONFIG")"
# 기존 볼트는 전부 한국어다 — 여기서 로케일을 보면 한국어 볼트 옆에
# 영어 폴더가 생긴다.
t_eq "lang 은 로케일과 무관하게 ko" "ko" "$(jq -r '.lang' "$DEVTRAIL_CONFIG")"
t_contains "최신이라고 말한다" "최신입니다" "$("$DT" config migrate 2>&1)"

t_start "영어 로케일에서도 ko 로 채운다"
t_vault m1b
_iso_cfg() { printf '{"version":1,"vault":{"path":"%s","root":"창기"}}\n' "$T_VAULT" > "$DEVTRAIL_CONFIG"; }
_iso_cfg
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 DEVTRAIL_LANG= "$DT" config migrate --apply >/dev/null 2>&1
t_eq "그래도 ko" "ko" "$(jq -r '.lang' "$DEVTRAIL_CONFIG")"

# ── 기존 값을 덮어쓰지 않는다 (jq // 함정) ───────────────────────────────────
t_start "기존 값 보존"
t_vault m2
printf '{"version":1,"install":{"mode":"isolated","modules":[]},"dirs":{"devlog":"Daily"},"vault":{"path":"%s","root":"창기"}}\n' \
  "$T_VAULT" > "$DEVTRAIL_CONFIG"

"$DT" config migrate --apply >/dev/null 2>&1
t_eq "mode 를 지킨다" "isolated" "$(jq -r '.install.mode' "$DEVTRAIL_CONFIG")"
t_eq "빈 배열을 지킨다" "0" "$(jq -r '.install.modules | length' "$DEVTRAIL_CONFIG")"
t_eq "dirs 를 지킨다" "Daily" "$(jq -r '.dirs.devlog' "$DEVTRAIL_CONFIG")"

# ── 마이그레이션도 되돌릴 수 있다 ────────────────────────────────────────────
t_start "마이그레이션 되돌리기"
"$DT" undo "$(_last)" --apply >/dev/null 2>&1
t_eq "설정이 v1 로 돌아온다" "1" "$(jq -r '.version' "$DEVTRAIL_CONFIG")"

# ── augment 가 init 의 모듈 선택을 존중한다 ──────────────────────────────────
# install.modules 를 저장만 하고 읽지 않아, 거절한 모듈이 되살아났다.
t_start "모듈 선택 존중"
t_vault m3
printf '{"version":2,"install":{"mode":"new","modules":["devlog"]},"dirs":{},"vault":{"path":"%s","root":"창기"}}\n' \
  "$T_VAULT" > "$DEVTRAIL_CONFIG"

out=$("$DT" augment 2>&1)
t_contains "고른 모듈은 대상" "devlog" "$out"
t_not_contains "고르지 않은 모듈은 제외" "pkm" "$(printf '%s' "$out" | grep '대상 모듈')"

# ── 중첩 ─────────────────────────────────────────────────────────────────────
#
# ⚠️ 회귀: 중첩은 실제로 일어난다 — setup apply 가 내부에서 augment 를 부르고
#    augment 도 자기 작업을 연다. 예전에는 자식이 DT_JOB_DIR 을 덮어써서
#    부모가 기록한 백업이 미아가 됐고, "되돌리기" 안내가 두 번 찍혔다.
#    한 번의 명령은 하나의 되돌림 단위여야 한다.
t_start "저널 작업은 중첩되지 않는다"
t_vault nest
t_config notes

before=$(ls -1 "$(_jrdir)" 2>/dev/null | wc -l | tr -d ' ')
(
  . "$ROOT/lib/common.sh"
  jr_begin parent
  parent_dir="$DT_JOB_DIR"
  jr_begin child            # 안쪽 명령이 자기 작업을 연다
  printf '%s' "$DT_JOB_DIR" > "$T_TMP/child-dir"
  jr_created "$T_VAULT/from-child"
  jr_end                    # 자식이 끝나도 부모는 살아 있어야 한다
  printf '%s' "$DT_JOB_DIR" > "$T_TMP/after-child"
  jr_created "$T_VAULT/from-parent"
  jr_end
  printf '%s' "$parent_dir" > "$T_TMP/parent-dir"
)
t_eq "자식이 부모 작업을 빼앗지 않는다" \
  "$(cat "$T_TMP/parent-dir")" "$(cat "$T_TMP/child-dir")"
t_eq "자식이 끝나도 부모가 살아 있다" \
  "$(cat "$T_TMP/parent-dir")" "$(cat "$T_TMP/after-child")"

after=$(ls -1 "$(_jrdir)" 2>/dev/null | wc -l | tr -d ' ')
t_eq "작업이 하나만 생긴다" "$((before + 1))" "$after"

job=$(_last)
t_eq "명령 이름은 부모 것" "parent" "$(jq -r '.command' "$(_jrdir)/$job/meta.json")"
t_eq "양쪽 기록이 한 작업에" "2" \
  "$(grep -c . "$(_jrdir)/$job/entries.tsv" | tr -d ' ')"

# ── 잡 이름이 곧 정렬 순서다 ─────────────────────────────────────────────────
#
# ⚠️ 예전에는 <시각>-<PID> 였다. PID 는 자릿수가 달라서 **같은 초에 만든 둘이
#    문자순으로 뒤집힌다** — 20260828-030603-9999 가 -21089 보다 뒤에 온다
#    ('9' > '2'). 그래서 `ls | tail -1` 로 "방금 만든 잡" 을 고르는 테스트가
#    간헐적으로 깨졌고(2026-08-28 에 두 건 관측), `devtrail undo` 목록의
#    순서도 가끔 틀렸다 — 사용자가 맨 위를 고르면 엉뚱한 것을 되돌린다.
t_start "잡 이름이 만든 순서대로 정렬된다"
ids=""
for i in 1 2 3 4 5; do
  # 매번 새 저널이 열리는 명령이어야 한다 — 개발일지는 두 번째부터
  # "이미 있습니다" 로 끝나 저널을 만들지 않는다.
  out=$("$DT" project add "seq-$i" --apply 2>&1)
  id=$(printf '%s' "$out" | sed -n 's/.*devtrail undo \([0-9-]*\).*/\1/p' | tail -1)
  [ -n "$id" ] && ids="$ids$id
"
done
# 같은 초 안에서 여러 개가 만들어져야 의미가 있다 — 위 루프는 순식간에 돈다.
t_ne "잡이 여러 개 만들어졌다" "" "$ids"
# ⚠️ 이 단언은 우연히 통과할 수 있다 — 한 번의 실행에서 PID 자릿수가 같으면
#    옛 이름 규칙으로도 순서가 맞는다. 실제 결함은 요구에 따라 재현되지 않는다.
#    **실질적인 방어선은 아래 구조 단언**이다: 이름에 PID 를 쓰지 않는다.
t_eq "만든 순서 == 문자순" "yes" \
  "$([ "$(printf '%s' "$ids" | sed '/^$/d')" = "$(printf '%s' "$ids" | sed '/^$/d' | LC_ALL=C sort)" ] && echo yes || echo no)"
t_eq "PID 를 이름에 쓰지 않는다" "0" \
  "$(grep -c 'date +%Y%m%d-%H%M%S)-\$\$' "$ROOT/lib/journal.sh" | tr -d ' ')"

t_end
