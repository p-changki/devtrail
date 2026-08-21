#!/usr/bin/env bash
# 한국어 · 영어 양쪽.
#
# 핵심 계약: 언어는 '표시'만 바꾼다. key 와 tag 는 바뀌지 않는다.
# 이게 깨지면 언어를 바꾼 사용자의 자동 분류가 통째로 죽는다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$PWD"
. tests/lib/harness.sh

T_TMP=$(mktemp -d)
trap 'rm -rf "$T_TMP"' EXIT
DT="$ROOT/bin/devtrail"

# ⚠️ 이 파일은 grep '[가-힣]' 로 한글을 센다. 그 문자 범위는 로케일의 대조
#    순서에 의존해서, C 로케일의 GNU grep 은 "Invalid collation character"
#    로 거부한다(BSD grep 은 통과시킨다).
#
#    CI 의 동작 잡은 macOS 라 문제가 없지만, Linux 에서 전체를 돌리는
#    기여자는 원인을 알 수 없는 실패를 만난다. 먼저 확인하고 알려준다.
if ! printf '%s\n' '한글' | grep -q '[가-힣]' 2>/dev/null; then
  echo "❌ 이 환경의 grep 이 [가-힣] 범위를 쓰지 못합니다 (LC_ALL=${LC_ALL:-unset})"
  echo "   UTF-8 로케일에서 실행하세요:  LC_ALL=ko_KR.UTF-8 ./tests/test-i18n.sh"
  echo "   (macOS 는 영향 없음 — CI 의 동작 잡도 macOS 입니다)"
  exit 1
fi
unset DEVTRAIL_LANG DEVTRAIL_JOURNAL

# ── 로케일에서 제안값 ────────────────────────────────────────────────────────
t_start "로케일 감지"
_l() { LANG="$1" LC_ALL="" DEVTRAIL_LANG="" bash -c \
       'DEVTRAIL_ROOT="'"$ROOT"'"; . lib/i18n.sh; dt_lang_from_locale'; }
t_eq "한국어 로케일" "ko" "$(_l ko_KR.UTF-8)"
t_eq "영어 로케일"   "en" "$(_l en_US.UTF-8)"
t_eq "그 밖의 로케일" "en" "$(_l de_DE.UTF-8)"
t_eq "로케일 없음은 기본값" "ko" "$(_l '')"

# ── 경로 ─────────────────────────────────────────────────────────────────────
t_start "경로 — 언어별"
t_vault i18n
t_config MyVault

t_eq "ko devlog" "MyVault/개발/개발일지" "$("$DT" path devlog --rel)"
t_eq "en devlog" "MyVault/Dev/Devlog"   "$(DEVTRAIL_LANG=en "$DT" path devlog --rel)"
t_eq "en 하위 폴더" "MyVault/Dev/Notes/Frontend" \
  "$(DEVTRAIL_LANG=en "$DT" path devnote.frontend --rel)"
# 이미 영어인 폴더는 번역을 두지 않았다 — path 로 떨어져야 한다
t_eq "번역 없으면 원본" "MyVault/Dev/Notes/Frontend" \
  "$(DEVTRAIL_LANG=en "$DT" path devnote.frontend --rel)"

# ── key 는 언어와 무관하다 (핵심 계약) ───────────────────────────────────────
t_start "key 는 안 바뀐다"
ko_keys=$("$DT" path --json | jq -r 'keys|sort|join(",")')
en_keys=$(DEVTRAIL_LANG=en "$DT" path --json | jq -r 'keys|sort|join(",")')
t_eq "키 집합이 동일" "$ko_keys" "$en_keys"
t_ne "경로는 다르다" \
  "$("$DT" path --json | jq -r '.devlog.rel')" \
  "$(DEVTRAIL_LANG=en "$DT" path --json | jq -r '.devlog.rel')"

# ── tag 는 언어와 무관하다 ───────────────────────────────────────────────────
t_start "tag 는 안 바뀐다"
t_eq "태그에 한글이 없다" "0" \
  "$(jq -r '[.folders[].tag//empty, ((.folders[].children//[])[].tag//empty)]|.[]' \
     preset/tree.json | grep -c '[가-힣]')"

# ── augment: 영어 볼트에 한국어 폴더가 섞이면 안 된다 ────────────────────────
# _aug_folders 가 tree.json 의 .path 만 읽어 양쪽이 다 생긴 적이 있다.
t_start "영어 볼트에 한국어 폴더 없음"
t_vault en1
t_config MyVault
DEVTRAIL_LANG=en "$DT" augment --apply >/dev/null 2>&1

t_eq "한글 폴더 0개" "0" \
  "$(find "$T_VAULT" -type d -name '*[가-힣]*' | wc -l | tr -d ' ')"
t_dir "영어 폴더가 생겼다" "$T_VAULT/MyVault/Dev/Devlog"
t_no_file "한국어 폴더가 없다" "$T_VAULT/MyVault/개발"

t_start "한국어 볼트에 영어 폴더 없음"
t_vault ko1
t_config MyVault
"$DT" augment --apply >/dev/null 2>&1
t_dir "한국어 폴더가 생겼다" "$T_VAULT/MyVault/개발/개발일지"
t_no_file "영어 폴더가 없다" "$T_VAULT/MyVault/Dev"

# ── 허브 본문 ────────────────────────────────────────────────────────────────
t_start "허브 본문 언어"
_hub() {
  DEVTRAIL_LANG="$1" DT_HUB_KEY=devlog DT_HUB_REL=x DT_HUB_FROM="V/x" \
  DT_HUB_TITLE=Devlog DT_HUB_COV_STATUS=0 DT_HUB_COV_REVIEW=0 \
  DT_HUB_DATE=2026-01-01 python3 lib/gen/hub.py
}
t_contains "ko 제목"   "## 최근"   "$(_hub ko)"
t_contains "en 제목"   "## Recent" "$(_hub en)"
t_contains "en 컬럼"   'AS "Note"' "$(_hub en)"
t_not_contains "en 에 한글 없음" "최근" "$(_hub en)"
# frontmatter 의 키는 언어와 무관해야 한다 — Dataview 가 이걸로 동작한다
t_contains "ko frontmatter 키" "devtrail_key: devlog" "$(_hub ko)"
t_contains "en frontmatter 키" "devtrail_key: devlog" "$(_hub en)"
t_contains "en 태그도 그대로" "type/moc" "$(_hub en)"

# ── L1 대시보드 ──────────────────────────────────────────────────────────────
t_start "L1 대시보드 언어"
t_vault l1en
t_config MyVault
DEVTRAIL_LANG=en "$DT" augment --apply >/dev/null 2>&1
t_file "영어 파일명" "$T_VAULT/MyVault/Dashboard.md"
t_file "체크인도"     "$T_VAULT/MyVault/Daily check-in.md"
t_eq "한글 0줄" "0" "$(grep -c '[가-힣]' "$T_VAULT/MyVault/Dashboard.md" | tr -d ' ')"

t_vault l1ko
t_config MyVault
"$DT" augment --apply >/dev/null 2>&1
t_file "한국어 파일명" "$T_VAULT/MyVault/대시보드.md"
t_no_file "영어판은 없다" "$T_VAULT/MyVault/Dashboard.md"

# ── 쿼리에 이름을 박지 않는다 ────────────────────────────────────────────────
#
# '오늘' 쿼리가 " 개발일지" 를 찾고 있었다. 실제 파일명은 설정의
# naming.devlog_file("{{DATE}} devlog.md") 을 따르므로 한 번도 매칭되지
# 않았다 — 한국어 볼트에서도 오늘 할 일이 빈 채였다.
t_start "쿼리가 설정을 따른다"
t_vault naming
t_config MyVault '.naming.devlog_file = "{{DATE}} 일지.md"'
"$DT" augment --apply >/dev/null 2>&1
dash="$T_VAULT/MyVault/대시보드.md"
t_contains "파일명 규칙을 따른다" '+ " 일지"' "$(grep 'dateformat(date(today)' "$dash")"
t_not_contains "박아둔 이름이 없다" '개발일지"' "$(grep 'dateformat(date(today)' "$dash")"

# 템플릿 폴더 제외도 실제 폴더 이름을 써야 한다
t_start "템플릿 제외가 실제 폴더를 쓴다"
t_vault tplex
t_config MyVault
DEVTRAIL_LANG=en "$DT" augment --apply >/dev/null 2>&1
t_contains "영어 볼트는 Templates" 'file.folder, "Templates"' \
  "$(grep -m1 'contains(file.folder' "$T_VAULT/MyVault/Dashboard.md")"

# ── 템플릿 · 가이드 ──────────────────────────────────────────────────────────
t_start "템플릿 · 가이드 언어"
t_vault tpl
t_config MyVault
mkdir -p "$T_VAULT/.obsidian"
DEVTRAIL_LANG=en "$DT" augment --apply >/dev/null 2>&1
DEVTRAIL_LANG=en "$DT" obsidian >/dev/null 2>&1

tdir="$T_VAULT/MyVault/Templates"
t_file "영어 템플릿" "$tdir/Devlog.md"
t_no_file "한국어 이름은 없다" "$tdir/개발일지양식.md"
# ⚠️ 개수를 박지 않는다. 템플릿을 추가할 때마다 테스트가 깨지면
#    고치는 김에 단언을 느슨하게 만들게 된다.
t_eq "템플릿 개수" "$(ls preset/templates/en/*.md | wc -l | tr -d ' ')" \
  "$(ls "$tdir"/*.md 2>/dev/null | grep -vc '_devtrail-paths' | tr -d ' ')"
t_eq "한글 든 템플릿 0개" "0" \
  "$(grep -l '[가-힣]' "$tdir"/*.md 2>/dev/null | grep -vc '_devtrail-paths' | tr -d ' ')"
t_file "영어 가이드" "$T_VAULT/MyVault/Guides/1. Getting started.md"

# ── 단축키가 존재하는 템플릿을 가리켜야 한다 ────────────────────────────────
# 이름이 언어를 타므로, 매핑이 빠지면 눌렀을 때 "템플릿 없음" 이 뜬다.
t_start "단축키가 실재하는 템플릿을 가리킨다"
hk="$T_VAULT/.obsidian/hotkeys.json"
if [ -f "$hk" ]; then
  bad=0
  # ⚠️ templater-obsidian:create-new-note-from-template 은 Templater 내장
  #    명령이지 파일 경로가 아니다. 경로로 취급하면 거짓 실패가 난다.
  # ⚠️ for k in $(...) 는 공백에서 쪼갠다. 템플릿 이름에 공백이 있다
  #    ("Reference card.md"). while read 로 줄 단위로 읽는다.
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    f="${k#templater-obsidian:create-}"
    [ -f "$T_VAULT/$f" ] || { bad=$((bad + 1)); echo "    가리키는 곳 없음: $f"; }
  done <<EOF
$(jq -r 'keys[]
   | select(startswith("templater-obsidian:create-"))
   | select(. != "templater-obsidian:create-new-note-from-template")' "$hk")
EOF
  t_eq "가리키는 곳이 전부 실재" "0" "$bad"
  # ⚠️ 개수를 단언해야 한다. 없는 템플릿은 조용히 '건너뛰어질' 뿐 매달린
  #    포인터가 생기지 않아서, 실재 검사만으로는 언어를 무시해도 통과한다.
  #    (변이 주입으로 확인했다)
  t_eq "템플릿 단축키가 전부 배정됨" \
    "$(jq '.templater|length' preset/obsidian/hotkeys.tmpl.json)" \
    "$(jq -r '[keys[]
        | select(startswith("templater-obsidian:create-"))
        | select(. != "templater-obsidian:create-new-note-from-template")]
       | length' "$hk")"
fi

# ── 파일명·태그를 박지 않는다 ────────────────────────────────────────────────
t_start "템플릿이 이름을 박지 않는다"
t_eq "개발일지 이름 하드코딩" "0" \
  "$(grep -lE '\} 개발일지`|\} 주간리뷰`' preset/templates/ko/*.md 2>/dev/null | wc -l | tr -d ' ')"
t_eq "태그 네임스페이스 하드코딩" "0" \
  "$(grep -lE '^\s+- (주제|상태)/|#(주제|상태)/' preset/templates/ko/*.md 2>/dev/null | wc -l | tr -d ' ')"
t_eq "번역 매핑이 전부 존재" "0" \
  "$(python3 -c '
import io, os
m = dict(l.rstrip("\n").split("\t") for l in io.open("preset/templates/en/_map.tsv", encoding="utf-8") if l.strip())
print(sum(1 for v in m.values() if not os.path.exists("preset/templates/en/" + v)))')"

# ── init 흐름 — 영어 사용자가 끝까지 갈 수 있는가 ───────────────────────────
#
# 화면 전체가 영어여야 한다. 한 화면이라도 한국어면 거기서 막힌다.
t_start "init 흐름 (영어)"
t_vault flow
_flow() {
  # 2=English · 1=Local · 볼트 · 모드(Enter) · 루트(Enter) · 모듈(Enter)
  # · GitHub(Enter) · 프로젝트폴더 · 나머지 Enter
  { printf '2\n1\n%s\n\n\n\n\n' "$T_VAULT"
    printf '%s\n\n\n\n\n\n' "$T_TMP/nonexistent"; } \
  | LANG=en_US.UTF-8 DEVTRAIL_LANG= DEVTRAIL_SKILL_DIR="$T_TMP/sk-$$" \
    "$DT" init 2>&1
}
out=$(_flow)

t_contains "언어 선택이 첫 화면"   "Language / 언어"        "$out"
t_contains "볼트 위치 질문"        "Where the vault lives"  "$out"
t_contains "설치 방식 질문"        "How to install"         "$out"
t_contains "기존 볼트에 얹기"      "Add to this vault"      "$out"
t_contains "새로 시작"             "Start fresh"            "$out"
t_contains "분리 설치"             "Isolated install"       "$out"
t_contains "모듈 선택"             "Modules to install"     "$out"
t_contains "모듈 라벨도 영어"      "Weekly · monthly"       "$out"
t_contains "마무리 안내"           "Next steps"             "$out"
t_contains "완료"                  "Setup complete"         "$out"

# ⚠️ 화면에 한글이 섞이면 안 된다.
#    단, 언어 선택 화면은 양쪽 병기가 맞다 — 아직 언어를 모르는 사람이 본다.
# 언어를 묻기 전에 나오는 줄은 양쪽 병기가 맞다 — 그때는 사용자의 언어를
# 알 수 없다. 그 밖에 한글이 섞이면 영어 사용자가 거기서 막힌다.
ko_lines=$(printf '%s\n' "$out" | grep '[가-힣]' \
           | grep -vE 'setup / 셋업|언제든 Ctrl\+C|Language / 언어|한국어|폴더 이름|태그는 언어와' || true)
t_eq "그 밖에 한글 없음" "" "$ko_lines"

# ── 영어 볼트에 한글 파일이 남지 않는다 ──────────────────────────────────────
t_start "영어 볼트 내용"
left=$(grep -rl '[가-힣]' "$T_VAULT" 2>/dev/null \
       | grep -v 'Folders and tags' || true)
t_eq "한글 든 파일 없음" "" "$left"

# ── 문서 종류 → 골격 폴더 매핑 ───────────────────────────────────────────────
#
# 종류를 묻고도 전부 docs/ 바로 아래에 저장하면, 설계안·ADR·요구사항이
# 한 폴더에 쌓여 골격이 아무 일도 하지 않는다.
t_start "문서 배치가 결정적이다"
for f in "preset/templates/en/Project doc.md" "preset/templates/ko/docs 문서 템플릿.md"; do
  name=$(basename "$f")
  t_contains "$name — 매핑이 있다"   "DOC_DIR"                    "$(cat "$f")"
  t_contains "$name — 하위로 저장"   'docs/${sub}'                "$(cat "$f")"
  t_not_contains "$name — 바로 아래 저장 안 함" \
    'const docs = `${root}/${project}/docs`;' "$(cat "$f")"
  # 골격 8단계 중 실재하는 폴더만 가리켜야 한다
  for d in $(grep -oE '"0[0-7]-[a-z]+"' "$f" | tr -d '"' | sort -u); do
    grep -q "\"$d\"" "preset/templates/en/New project.md" \
      || t_eq "$name — $d 가 골격에 있다" "있음" "없음"
  done
done

# 스킬 문서가 말하는 배치와 템플릿이 같아야 한다
t_start "스킬 문서와 템플릿이 일치"
t_contains "prd → 01-product"       "01-product"      "$(cat 'preset/templates/en/Project doc.md')"
t_contains "design → 03-architecture" "03-architecture" "$(cat 'preset/templates/en/Project doc.md')"
t_contains "스킬도 같은 규칙"        "01-product"      "$(cat skills/en/docs/SKILL.md)"

# ── 없는 언어는 기본값으로 ───────────────────────────────────────────────────
t_start "알 수 없는 언어"
t_vault fallback
t_config MyVault
t_eq "ja 는 ko 로 떨어진다" "MyVault/개발/개발일지" \
  "$(DEVTRAIL_LANG=ja "$DT" path devlog --rel)"

t_end
