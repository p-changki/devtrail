#!/usr/bin/env bash
# 생성기의 **출력 계약**을 골든 파일로 고정한다.
#
# ⚠️ 왜 이게 먼저인가 (M1 — ADR 0006)
#
#    python3 를 Swift 헬퍼로 대체하기로 했다(D2 = B). 1,827줄을 다시 쓴다는
#    뜻이고, 재현이 정확하지 않으면 **생성되는 설정이 조용히 달라진다** —
#    사용자 볼트의 단축키·폴더매핑·제외 규칙이 어긋나는데 아무 에러도 안 난다.
#
#    그래서 이관 **전에** 지금 동작을 바이트로 못 박는다. M2 에서 Swift
#    헬퍼가 이 골든을 그대로 통과해야 한다. 통과하지 못하면 이관이 아니라
#    변경이다.
#
# ⚠️ 골든은 **현재 동작**을 고정할 뿐 옳음을 증명하지 않는다. 여기서 지키는
#    것은 "바뀌지 않았다" 하나다. 의도한 변경이라면 골든을 다시 만들고
#    **왜 바뀌었는지 커밋에 적는다.**
#
#    골든 재생성:  UPDATE_GOLDEN=1 ./tests/test-gen-contract.sh
#
# ⚠️ 숨은 입력을 전부 고정한다. DEVTRAIL_LANG 을 안 박으면 기계마다 다른
#    골든이 나온다 (i18n.py 가 환경변수를 읽는다). LC_ALL 도 같다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

GOLDEN="$ROOT/tests/golden/gen"
mkdir -p "$GOLDEN"

if ! command -v python3 >/dev/null 2>&1; then
  t_start "생성기 계약"
  dim "   python3 없음 — 건너뜀"
  t_end
  exit 0
fi

# ── 고정 입력 ────────────────────────────────────────────────────────────────
# ⚠️ 실물 preset 을 쓴다. 지어낸 픽스처는 실제로 도는 경로를 안 지난다.
TREE="$ROOT/preset/tree.json"
TMPL="$ROOT/preset/obsidian/hotkeys.tmpl.json"

# 볼트 경로가 출력에 새면 기계마다 골든이 달라진다. 고정 경로를 쓴다.
FIXED_VAULT="/tmp/devtrail-golden-vault"

CFG="$T_TMP/config.json"
cat > "$CFG" <<JSON
{
  "version": 3,
  "lang": "ko",
  "vault": { "backend": "local", "path": "$FIXED_VAULT", "root": "notes" },
  "dirs": {},
  "headings": { "issues_pr": "## Issues / PRs", "worklog": "## Work log" },
  "github": { "user": "golden", "repos": [], "project_groups": {} },
  "ai": { "provider": "claude", "summary_enabled": false },
  "install": { "mode": "new", "modules": ["devlog"] }
}
JSON

PATHS="$T_TMP/paths.json"
cat > "$PATHS" <<JSON
{
  "templates": "notes/템플릿",
  "devlog": "notes/개발/개발일지",
  "weekly": "notes/개발/주간리뷰",
  "projects": "notes/개발/프로젝트"
}
JSON

IDS="$T_TMP/ids.json"
printf '%s' '{}' > "$IDS"

# 기존 설정이 있는 경우 — 병합 가지를 태운다.
EXIST_HK="$T_TMP/existing-hotkeys.json"
printf '%s' '{"editor:toggle-bold":[{"modifiers":["Mod"],"key":"B"}]}' > "$EXIST_HK"
EXIST_ANM="$T_TMP/existing-anm.json"
printf '%s' '{"folder_tag_pattern":[{"folder":"기존","tag":"#keep"}]}' > "$EXIST_ANM"
EXIST_SE="$T_TMP/existing-smartenv.txt"
printf '%s\n' 'existing/excluded/**' > "$EXIST_SE"

# ── 실행 ─────────────────────────────────────────────────────────────────────
FAILED=0

# gen <이름> <언어> -- <python 인자…>
#
# ⚠️ 환경을 통째로 고정한다. 여기서 새는 값이 하나라도 있으면 골든이
#    "이 기계에서만 맞는" 파일이 된다.
CASES=0
gen() {
  local name="$1" lang="$2"; shift 3
  CASES=$((CASES + 1))
  local out="$T_TMP/$name.out" err="$T_TMP/$name.err" rc=0
  # ⚠️ lang 이 'unset' 이면 DEVTRAIL_LANG 을 **넘기지 않는다.**
  #
  #    2026-08-23 이전에는 이게 실제 운영 경로였다 — `devtrail obsidian apply`
  #    가 이 변수를 export 하지 않아 영어 사용자도 python 쪽에서 ko 를 받았다.
  #    그 결함은 lib/common.sh 에서 고쳤다(D6). 이제 CLI 를 거치면 항상
  #    설정 언어가 전달된다.
  #
  #    그래도 이 케이스를 **남긴다**: python 을 직접 부르는 경로가 남아 있고,
  #    Swift 헬퍼도 같은 기본값(ko)을 지켜야 한다. 그리고 이걸 빼면 i18n 의
  #    기본 언어를 바꿔도 테스트가 통과한다(실제로 변이가 생존했다).
  if [ "$lang" = unset ]; then
    env -u DEVTRAIL_LANG LC_ALL=C.UTF-8 TZ=UTC \
      python3 "$@" > "$out" 2> "$err" || rc=$?
  else
    DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC \
      python3 "$@" > "$out" 2> "$err" || rc=$?
  fi

  local g="$GOLDEN/$name.json"
  case "$name" in *smartenv*) g="$GOLDEN/$name.txt" ;; esac

  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then
    cp "$out" "$g"
    dim "   골든 갱신: $(basename "$g")"
    return 0
  fi

  if [ ! -f "$g" ]; then
    _t_bad "$name" "골든이 없습니다: $g" "UPDATE_GOLDEN=1 로 만드세요"
    FAILED=1
    return 0
  fi

  if [ "$rc" != 0 ]; then
    _t_bad "$name" "종료 코드 $rc" "$(head -3 "$err")"
    FAILED=1
    return 0
  fi

  # ⚠️ 바이트로 비교한다. jq 로 정규화해 비교하면 들여쓰기·키 순서가 바뀌어도
  #    통과하는데, 그건 사용자 설정 파일에서는 **다른 파일**이다.
  if cmp -s "$out" "$g"; then
    _t_ok "$name"
  else
    _t_bad "$name" "골든과 다릅니다" "$(diff "$g" "$out" | head -6)"
    FAILED=1
  fi
}

t_start "smartenv — Smart Connections 제외 설정"
gen smartenv-ko-new ko -- "$ROOT/lib/gen/smartenv.py" "$TREE" "$CFG" "notes/템플릿" ""
gen smartenv-ko-merge ko -- "$ROOT/lib/gen/smartenv.py" "$TREE" "$CFG" "notes/템플릿" "$EXIST_SE"
gen smartenv-en-new en -- "$ROOT/lib/gen/smartenv.py" "$TREE" "$CFG" "notes/템플릿" ""

t_start "anm — Auto Note Mover 규칙"
for prof in new existing isolated; do
  gen "anm-ko-$prof" ko -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/$prof.json" ""
done
gen anm-ko-merge ko -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "$EXIST_ANM"
gen anm-en-new en -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" ""
# ⚠️ DEVTRAIL_LANG 이 **없는** 경우 — 실제로 `devtrail augment` 가 도는 방식이다.
gen anm-unset-new unset -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" ""

t_start "hotkeys — 단축키 · Templater · daily-notes"
for what in hotkeys templater daily; do
  gen "hotkeys-$what-ko-new" ko -- "$ROOT/lib/gen/hotkeys.py" "$what" "$TMPL" "$PATHS" "" "$IDS"
  gen "hotkeys-$what-en-new" en -- "$ROOT/lib/gen/hotkeys.py" "$what" "$TMPL" "$PATHS" "" "$IDS"
done
gen hotkeys-hotkeys-ko-merge ko -- "$ROOT/lib/gen/hotkeys.py" hotkeys "$TMPL" "$PATHS" "$EXIST_HK" "$IDS"
gen hotkeys-hotkeys-unset-new unset -- "$ROOT/lib/gen/hotkeys.py" hotkeys "$TMPL" "$PATHS" "" "$IDS"

t_start "골든이 결정론적이다"
# ⚠️ 두 번 돌려 같은 답이 나오는가. 타임스탬프·난수·해시 순서가 새면
#    골든은 매번 빨간불이 되고, 곧 아무도 믿지 않게 된다.
A="$T_TMP/det-a"; B="$T_TMP/det-b"
DEVTRAIL_LANG=ko LC_ALL=C.UTF-8 TZ=UTC python3 "$ROOT/lib/gen/anm.py" \
  "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "" > "$A" 2>/dev/null
DEVTRAIL_LANG=ko LC_ALL=C.UTF-8 TZ=UTC python3 "$ROOT/lib/gen/anm.py" \
  "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "" > "$B" 2>/dev/null
t_eq "같은 입력 → 같은 출력" "same" "$(cmp -s "$A" "$B" && echo same || echo different)"

t_start "골든이 기계에 매이지 않는다"
# ⚠️ 절대 경로·홈 디렉터리가 출력에 새면 다른 사람 기계에서 전부 빨간불이다.
LEAK=$(grep -rl "$HOME" "$GOLDEN" 2>/dev/null | tr '\n' ' ')
t_eq "홈 경로가 골든에 없다" "" "$(printf '%s' "$LEAK" | sed 's/ *$//')"
LEAK2=$(grep -rl "$ROOT" "$GOLDEN" 2>/dev/null | tr '\n' ' ')
t_eq "저장소 경로가 골든에 없다" "" "$(printf '%s' "$LEAK2" | sed 's/ *$//')"

t_start "골든이 실제로 무언가를 담고 있다"
# ⚠️ 빈 골든은 무엇과도 같다 — 단언이 공허하게 통과한다. 이 저장소가
#    빈 바늘로 이미 당한 적이 있다.
EMPTY=$(find "$GOLDEN" -type f -size -2c 2>/dev/null | tr '\n' ' ')
t_eq "빈 골든이 없다" "" "$(printf '%s' "$EMPTY" | sed 's/ *$//')"
# ⚠️ 개수를 손으로 적지 않는다. 케이스를 늘렸는데 숫자를 안 고치면 그때부터
#    거짓말이고, 반대로 골든이 사라져도 눈치채지 못한다.
#
#    소스를 파싱해 세려다 한 번 틀렸다(2026-08-23: awk 가 12, 실제 15).
#    그건 케이스 수의 **두 번째 정본**을 만드는 짓이다. gen() 이 돌면서
#    스스로 센 값을 쓴다 — 정본은 실행 하나다.
N=$(find "$GOLDEN" -type f | wc -l | tr -d ' ')
t_eq "골든 수 = 실행한 케이스 수" "$CASES" "$N"
t_eq "케이스가 0이 아니다" "no" "$([ "$CASES" = 0 ] && echo yes || echo no)"

t_end
