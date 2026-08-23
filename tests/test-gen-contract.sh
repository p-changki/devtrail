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

# ⚠️ 프로젝트가 있는 설정. 기본 CFG 에는 project_groups 가 비어 있어
#    project/* 규칙이 **한 줄도 안 생겼다** — 그래서 "project 는 맨 뒤" 도
#    "wildcard 키를 거른다" 도 한 번도 시험되지 않았다(변이 생존으로 확인).
CFG_PROJ="$T_TMP/config-proj.json"
jq '.github.project_groups = {"my-app":"myapp","acme-*":"acme","b-repo":"b","깊은레포":"deep"}' \
  "$CFG" > "$CFG_PROJ"

# ⚠️ **우리 태그**를 이미 라우팅 중인 기존 설정. 예전 픽스처는 남의 태그
#    (#keep)만 있어서 "이미 라우팅 중이면 그들 것을 남긴다" 가 안 돌았다.
EXIST_ANM_OURS="$T_TMP/existing-anm-ours.json"
cat > "$EXIST_ANM_OURS" <<'JSON'
{
  "folder_tag_pattern": [
    { "folder": "사용자가/고친/폴더", "tag": "#type/devlog", "pattern": "" },
    { "folder": "남의폴더", "tag": "#keep", "pattern": "" }
  ],
  "excluded_folder": [{ "folder": "기존제외" }],
  "use_regex_to_check_for_tags": true,
  "남의키": "건드리면 안 된다"
}
JSON

# ⚠️ 프리셋으로 도달할 수 없는 가지를 태우는 합성 트리.
TREE_EDGE="$ROOT/tests/fixtures/tree-edge.json"

IDS="$T_TMP/ids.json"
printf '%s' '{}' > "$IDS"

# 기존 설정이 있는 경우 — 병합 가지를 태운다.
EXIST_HK="$T_TMP/existing-hotkeys.json"
printf '%s' '{"editor:toggle-bold":[{"modifiers":["Mod"],"key":"B"}]}' > "$EXIST_HK"
EXIST_ANM="$T_TMP/existing-anm.json"
printf '%s' '{"folder_tag_pattern":[{"folder":"기존","tag":"#keep"}]}' > "$EXIST_ANM"
# ⚠️ smartenv 의 기존 설정은 **JSON** 이다 (json.load 로 읽는다).
#    처음엔 텍스트 파일을 줬는데 파싱이 실패해 {} 로 떨어졌고, 병합 가지를
#    한 번도 안 탔다 — merge 골든이 new 골든과 **글자 하나까지 같았다.**
#    통과하는데 아무것도 안 지키는 케이스였다(2026-08-23).
EXIST_SE="$T_TMP/existing-smartenv.json"
cat > "$EXIST_SE" <<'JSON'
{
  "smart_sources": {
    "folder_exclusions": "existing/excluded, 앞뒤공백폴더 ",
    "excluded_headings": "기존 헤딩",
    "min_chars": 999
  },
  "other_key": "건드리면 안 된다"
}
JSON

# ── 실행 ─────────────────────────────────────────────────────────────────────
FAILED=0

# gen <이름> <언어> -- <python 인자…>
#
# ⚠️ 환경을 통째로 고정한다. 여기서 새는 값이 하나라도 있으면 골든이
#    "이 기계에서만 맞는" 파일이 된다.
CASES=0
# ⚠️ 골든 파일 이름을 정하는 곳은 **여기 하나**다. gen · genv · cmpx 가
#    각자 정하면 어긋난다 — 실제로 cmpx 가 .txt 만 보다가 anm 골든(.json)을
#    통째로 못 찾았고, 그 케이스들이 조용히 세어지지도 않았다(2026-08-23).
golden_path() {
  case "$1" in
    smartenv-*) printf '%s/%s.txt' "$GOLDEN" "$1" ;;
    anm-*|hotkeys-*) printf '%s/%s.json' "$GOLDEN" "$1" ;;
    *) printf '%s/%s.txt' "$GOLDEN" "$1" ;;
  esac
}

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

  local g; g=$(golden_path "$name")

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
# 프로젝트가 있는 경우 — project/* 순서와 wildcard 거르기가 여기서 시험된다.
gen anm-ko-proj ko -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG_PROJ" "$ROOT/preset/profiles/new.json" ""
# 우리 태그를 이미 라우팅 중인 경우 — 그들의 folder 를 지켜야 한다.
gen anm-ko-ours ko -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "$EXIST_ANM_OURS"
# 프리셋이 못 지나는 가지 — 부모 제외 전파 · 중복 태그(안정 정렬).
gen anm-ko-edge ko -- "$ROOT/lib/gen/anm.py" "$TREE_EDGE" "$CFG" "$ROOT/preset/profiles/new.json" ""
# ⚠️ 슬래시 없는 태그(구체성 0)와 프로젝트(-1)가 **함께** 있어야 둘의 순서를
#    구별할 수 있다. 프리셋에는 슬래시 없는 태그가 없어서, project 의 -1 을
#    0 으로 바꿔도 결과가 같았다(변이 생존).
gen anm-ko-edge-proj ko -- "$ROOT/lib/gen/anm.py" "$TREE_EDGE" "$CFG_PROJ" "$ROOT/preset/profiles/new.json" ""
# ⚠️ DEVTRAIL_LANG 이 **없는** 경우 — 실제로 `devtrail augment` 가 도는 방식이다.
gen anm-unset-new unset -- "$ROOT/lib/gen/anm.py" "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" ""

t_start "hotkeys — 단축키 · Templater · daily-notes"
for what in hotkeys templater daily; do
  gen "hotkeys-$what-ko-new" ko -- "$ROOT/lib/gen/hotkeys.py" "$what" "$TMPL" "$PATHS" "" "$IDS"
  gen "hotkeys-$what-en-new" en -- "$ROOT/lib/gen/hotkeys.py" "$what" "$TMPL" "$PATHS" "" "$IDS"
done
gen hotkeys-hotkeys-ko-merge ko -- "$ROOT/lib/gen/hotkeys.py" hotkeys "$TMPL" "$PATHS" "$EXIST_HK" "$IDS"
gen hotkeys-hotkeys-unset-new unset -- "$ROOT/lib/gen/hotkeys.py" hotkeys "$TMPL" "$PATHS" "" "$IDS"

# ── 픽스처 볼트 ──────────────────────────────────────────────────────────────
#
# ⚠️ scan · hubs · snapshot 은 **볼트를 읽는다.** 파일 mtime 이 입력이므로
#    touch 로 못 박는다. 안 그러면 골든이 만들 때마다 달라진다.
#
# ⚠️ 그리고 시계를 고정한다(DT_NOW · now_ms). scan 의 role_candidates 는
#    "최근에 손댔는가" 로 점수를 곱하는데, 그 판정이 **현재 시각**에 걸린다.
#    실측(2026-08-23): 같은 볼트가 DT_NOW 에 따라
#      {"devlog":0.45}  ↔  {}
#    로 갈린다. 고정하지 않으면 이 골든은 한 달 뒤 저절로 깨진다.
VAULT="$T_TMP/vault"
mkdir -p "$VAULT/notes/개발/개발일지" "$VAULT/notes/개발/주간리뷰" \
         "$VAULT/notes/개발/프로젝트/proj-a" "$VAULT/notes/템플릿" "$VAULT/notes/자료"

for d in 01 02 03 04 05; do
  printf -- '---\ntype: devlog\ncreated: 2026-08-%s\n---\n# 일지\n- [ ] 할 일 하나\n' "$d" \
    > "$VAULT/notes/개발/개발일지/2026-08-$d.md"
done
for w in 31 32 33; do
  printf -- '---\ntype: weekly\n---\n# 주간\n' > "$VAULT/notes/개발/주간리뷰/2026-W$w.md"
done
printf -- '---\ntype: project-home\nstatus: active\nstage: planning\nnext: 다음 행동\n---\n# proj-a\n' \
  > "$VAULT/notes/개발/프로젝트/proj-a/README.md"
printf -- '---\ntype: note\n---\n# 자료\n' > "$VAULT/notes/자료/카드.md"
printf -- '# 분류 없는 노트\n' > "$VAULT/notes/자료/무타입.md"
printf -- '---\ntype: template\n---\n<%% tp.file.title %%>\n' > "$VAULT/notes/템플릿/개발일지양식.md"

# ⚠️ mtime 을 전부 같은 값으로 못 박는다.
find "$VAULT" -type f -exec touch -t 202608010900 {} +

FIXED_NOW=1786000000        # 2026-08-06 근처 — 픽스처 mtime 직후
FIXED_NOW_MS=1786000000000
FIXED_DATE=2026-08-06

SCANOUT="$T_TMP/scan.json"

# 볼트 경로가 출력에 새면 기계마다 골든이 달라진다. 지우고 비교한다.
#
# ⚠️ 정규화는 최소로만 한다. 많이 지울수록 "다른데 같다고 하는" 골든이 된다.
norm() { sed "s|$VAULT|<VAULT>|g; s|$ROOT|<ROOT>|g"; }

# genv <이름> <언어> -- <명령…>   — 볼트를 읽는 생성기용 (경로 정규화 포함)
genv() {
  local name="$1" lang="$2"; shift 3
  CASES=$((CASES + 1))
  local out="$T_TMP/$name.out" rc=0
  if [ "$lang" = unset ]; then
    env -u DEVTRAIL_LANG LC_ALL=C.UTF-8 TZ=UTC DT_NOW="$FIXED_NOW" DT_DATE="$FIXED_DATE" \
      "$@" 2>/dev/null | norm > "$out" || rc=$?
  else
    env DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC DT_NOW="$FIXED_NOW" DT_DATE="$FIXED_DATE" \
      "$@" 2>/dev/null | norm > "$out" || rc=$?
  fi

  local g="$GOLDEN/$name.txt"
  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then cp "$out" "$g"; return 0; fi
  if [ ! -f "$g" ]; then _t_bad "$name" "골든 없음: $g" "UPDATE_GOLDEN=1"; FAILED=1; return 0; fi
  if cmp -s "$out" "$g"; then _t_ok "$name"; else
    _t_bad "$name" "골든과 다릅니다" "$(diff "$g" "$out" | head -6)"; FAILED=1
  fi
}

t_start "scan — 볼트 진단"
genv scan-ko ko -- python3 "$ROOT/lib/gen/scan.py" "$VAULT"
genv scan-en en -- python3 "$ROOT/lib/gen/scan.py" "$VAULT"
# 다음 단계들이 이 결과를 입력으로 쓴다.
DT_NOW="$FIXED_NOW" DEVTRAIL_LANG=ko LC_ALL=C.UTF-8 \
  python3 "$ROOT/lib/gen/scan.py" "$VAULT" > "$SCANOUT" 2>/dev/null

t_start "hub — L3 폴더 허브"
# ⚠️ DT_HUB_TITLE 의 **기본값**은 시험하지 않는다 — 동등 변이로 확인했다.
#    기본값을 바꿔도 이 테스트는 통과하는데, 그건 테스트가 약해서가 아니라
#    그 경로가 **도달 불가**이기 때문이다:
#
#      hub.py 를 부르는 곳    lib/augmentcmd.sh 하나뿐
#      그 호출이 넘기는 것    DT_HUB_TITLE="$(basename "$rel")"  — 항상 설정
#
#    도달하지 않는 코드에 테스트를 붙이면 유지 비용만 는다. 다만 호출자가
#    늘거나 이 변수를 안 넘기게 되면 이야기가 달라진다 — 그때 여기를 본다.
#
#    (DT_HUB_REL · DT_HUB_COV_* 의 기본값은 반대로 **시험된다** —
#     여기서 넘기지 않으므로 골든이 그 경로를 지난다.)
for lang in ko en; do
  CASES=$((CASES + 1))
  NAME="hub-$lang"
  env DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC \
    DT_HUB_FROM="notes/개발/개발일지" DT_HUB_TITLE="개발일지" \
    DT_HUB_KEY=devlog DT_HUB_DATE="$FIXED_DATE" \
    python3 "$ROOT/lib/gen/hub.py" 2>/dev/null | norm > "$T_TMP/$NAME.out"
  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then
    cp "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt"
  elif cmp -s "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt" 2>/dev/null; then
    _t_ok "$NAME"
  else
    _t_bad "$NAME" "골든과 다릅니다" "$(diff "$GOLDEN/$NAME.txt" "$T_TMP/$NAME.out" 2>/dev/null | head -6)"
    FAILED=1
  fi
done

t_start "hubs — L1 대시보드 · L2 영역 허브"
# ⚠️ hubs 는 stdout 이 아니라 **디렉터리에 파일을 쓴다.** 만들어진 파일 전체를
#    하나로 묶어 비교한다 — 파일 목록만 보면 내용이 바뀌어도 통과한다.
bundle() {   # bundle <디렉터리>
  (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf -- '--- %s\n' "${f#./}"
    cat "$f"
  done)
}
for lang in ko en; do
  CASES=$((CASES + 1))
  NAME="hubs-$lang"
  OUTDIR="$T_TMP/hubs-$lang"
  mkdir -p "$OUTDIR"
  env DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC DT_DATE="$FIXED_DATE" \
    python3 "$ROOT/lib/gen/hubs.py" "$PATHS" "$CFG" "$SCANOUT" "$OUTDIR" >/dev/null 2>&1
  bundle "$OUTDIR" | norm > "$T_TMP/$NAME.out"
  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then
    cp "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt"
  elif cmp -s "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt" 2>/dev/null; then
    _t_ok "$NAME"
  else
    _t_bad "$NAME" "골든과 다릅니다" "$(diff "$GOLDEN/$NAME.txt" "$T_TMP/$NAME.out" 2>/dev/null | head -6)"
    FAILED=1
  fi
done

t_start "snapshot — 메뉴바용 볼트 상태"
# ⚠️ cfg 를 **JSON 문자열 인자**로 받는다. today 와 now_ms 를 못 박는다.
SNAPCFG=$(jq -nc --arg r "$VAULT/notes" --arg t "$FIXED_DATE" --argjson n "$FIXED_NOW_MS" \
  '{root:$r, templates_rel:"템플릿", today:$t, now_ms:$n, limit:5}')
for lang in ko en; do
  CASES=$((CASES + 1))
  NAME="snapshot-$lang"
  env DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC \
    python3 "$ROOT/lib/snapshot.py" "$SNAPCFG" 2>/dev/null | norm > "$T_TMP/$NAME.out"
  if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then
    cp "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt"
  elif cmp -s "$T_TMP/$NAME.out" "$GOLDEN/$NAME.txt" 2>/dev/null; then
    _t_ok "$NAME"
  else
    _t_bad "$NAME" "골든과 다릅니다" "$(diff "$GOLDEN/$NAME.txt" "$T_TMP/$NAME.out" 2>/dev/null | head -6)"
    FAILED=1
  fi
done

t_start "시계를 고정하지 않으면 답이 달라진다"
# ⚠️ 위 골든들이 DT_NOW 를 박는 이유를 여기서 증명한다. 이 단언이 통과하지
#    않으면 이음새가 필요 없다는 뜻이고, 그러면 이음새를 지워야 한다.
R1=$(DT_NOW="$FIXED_NOW" python3 "$ROOT/lib/gen/scan.py" "$VAULT" 2>/dev/null \
     | jq -c '[.folders[]|select(.notes>=3)|.role_candidates]')
R2=$(DT_NOW=2000000000 python3 "$ROOT/lib/gen/scan.py" "$VAULT" 2>/dev/null \
     | jq -c '[.folders[]|select(.notes>=3)|.role_candidates]')
t_eq "DT_NOW 가 role_candidates 를 바꾼다" "different" \
  "$([ "$R1" = "$R2" ] && echo same || echo different)"

t_start "이음새는 미설정 시 예전 그대로다"
# ⚠️ 테스트 이음새가 기본 동작을 바꿨다면 그건 이음새가 아니라 변경이다.
t_eq "DT_NOW 없이도 돈다" "0" \
  "$(python3 "$ROOT/lib/gen/scan.py" "$VAULT" >/dev/null 2>&1; echo $?)"
t_eq "now_ms 없이도 돈다" "0" \
  "$(python3 "$ROOT/lib/snapshot.py" \
       "$(jq -nc --arg r "$VAULT/notes" '{root:$r, limit:5}')" >/dev/null 2>&1; echo $?)"

# ── Swift 헬퍼 대조 (M2) ─────────────────────────────────────────────────────
#
# ⚠️ 이관의 합격 기준은 하나다: **같은 골든을 바이트로 통과한다.**
#    통과하지 못하면 이관이 아니라 변경이다.
#
#    헬퍼가 아직 없는 명령은 건너뛴다 — 이관은 한 번에 끝나지 않는다.
#    다만 **건너뛴 것을 조용히 넘기지 않는다.** 몇 개를 안 봤는지 말한다.
HELPER="$ROOT/app/.build/debug/DevTrailHelper"

# ⚠️ 여기서 **직접 빌드한다.** run.sh 의 swift 단계는 all 에서만 돌고
#    release 를 만든다 — 일상 게이트(fast)에서는 이 대조가 통째로 건너뛰어진다.
#    "게이트가 있는데 안 돈다" 는 게이트가 없는 것보다 나쁘다: 있다고 믿게 된다.
#    증분 빌드는 1초 안팎이다.
if command -v swift >/dev/null 2>&1; then
  NEWER=$(find "$ROOT/app/Sources/DevTrailHelper" -name '*.swift' -newer "$HELPER" 2>/dev/null | head -1)
  if [ ! -x "$HELPER" ] || [ -n "$NEWER" ]; then
    (cd "$ROOT/app" && swift build --product DevTrailHelper) > "$T_TMP/build.log" 2>&1 \
      || { t_start "헬퍼 빌드"; _t_bad "swift build" "빌드 실패" "$(tail -5 "$T_TMP/build.log")"; FAILED=1; }
  fi
fi

t_start "Swift 헬퍼가 python 골든을 바이트로 통과한다"
if ! command -v swift >/dev/null 2>&1; then
  dim "   swift 없음 — 건너뜀 (⚠️ 이관이 깨져도 모른다)"
elif [ ! -x "$HELPER" ]; then
  _t_bad "헬퍼" "빌드 산출물이 없습니다" "$HELPER"
  FAILED=1
else
  PORTED=0
  SKIPPED=0

  # cmpx <골든이름> <언어> -- <헬퍼 인자…>
  cmpx() {
    local name="$1" lang="$2"; shift 3
    local g; g=$(golden_path "$name")
    [ -f "$g" ] || { _t_bad "헬퍼 = $name" "골든 없음" "$g"; FAILED=1; return 0; }
    local out="$T_TMP/helper-$name.out"
    if [ "$lang" = unset ]; then
      env -u DEVTRAIL_LANG LC_ALL=C.UTF-8 TZ=UTC "$HELPER" "$@" > "$out" 2>/dev/null
    else
      env DEVTRAIL_LANG="$lang" LC_ALL=C.UTF-8 TZ=UTC "$HELPER" "$@" > "$out" 2>/dev/null
    fi
    PORTED=$((PORTED + 1))
    if cmp -s "$out" "$g"; then
      _t_ok "헬퍼 = $name"
    else
      _t_bad "헬퍼 ≠ $name" "python 골든과 다릅니다" "$(diff "$g" "$out" | head -6)"
      FAILED=1
    fi
  }

  # smartenv — 이관 완료
  cmpx smartenv-ko-new   ko -- gen-smartenv "$TREE" "$CFG" "notes/템플릿" ""
  cmpx smartenv-en-new   en -- gen-smartenv "$TREE" "$CFG" "notes/템플릿" ""
  cmpx smartenv-ko-merge ko -- gen-smartenv "$TREE" "$CFG" "notes/템플릿" "$EXIST_SE"

  # anm — 이관 완료
  for prof in new existing isolated; do
    cmpx "anm-ko-$prof" ko -- gen-anm "$TREE" "$CFG" "$ROOT/preset/profiles/$prof.json" ""
  done
  cmpx anm-ko-merge  ko    -- gen-anm "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "$EXIST_ANM"
  cmpx anm-en-new    en    -- gen-anm "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" ""
  cmpx anm-unset-new unset -- gen-anm "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" ""
  cmpx anm-ko-proj  ko -- gen-anm "$TREE" "$CFG_PROJ" "$ROOT/preset/profiles/new.json" ""
  cmpx anm-ko-ours  ko -- gen-anm "$TREE" "$CFG" "$ROOT/preset/profiles/new.json" "$EXIST_ANM_OURS"
  cmpx anm-ko-edge      ko -- gen-anm "$TREE_EDGE" "$CFG" "$ROOT/preset/profiles/new.json" ""
  cmpx anm-ko-edge-proj ko -- gen-anm "$TREE_EDGE" "$CFG_PROJ" "$ROOT/preset/profiles/new.json" ""

  # ⚠️ 아직 이관하지 않은 것을 **세어서 말한다.** 침묵하면 "다 됐다" 로 읽힌다.
  TOTAL=$(find "$GOLDEN" -type f | wc -l | tr -d ' ')
  SKIPPED=$((TOTAL - PORTED))
  t_start "이관 진행 상황을 숨기지 않는다"
  t_eq "이관된 케이스가 0이 아니다" "no" "$([ "$PORTED" = 0 ] && echo yes || echo no)"
  dim "   이관 ${PORTED}건 · 남음 ${SKIPPED}건 (골든 ${TOTAL}건)"
fi

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
