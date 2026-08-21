#!/usr/bin/env bash
# DevTrail — 전체 검사.
#
#   ./tests/run.sh          전부
#   ./tests/run.sh fast     느린 것(swift 빌드) 빼고
#   ./tests/run.sh lint     문법·JSON·파이썬만        (CI: ubuntu)
#   ./tests/run.sh guard    이 저장소 고유의 함정만    (CI: ubuntu)
#
# CI 도 이 스크립트를 부른다. 로컬과 CI 가 같은 것을 돌려야
# "내 머신에서는 됐는데" 가 안 생긴다.
#
# ⚠️ 동작 테스트(path·augment·scan·undo)는 CI 에서 macOS 잡이 돌린다.
#    이 프로젝트가 실제로 설치되는 곳이 macOS 이고, bash 3.2 함정은
#    ubuntu 의 bash 5 에서 재현되지 않는다.
# ⚠️ macOS 기본 bash 3.2 에서 돌아야 한다.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

GROUP="${1:-all}"
case "$GROUP" in
  all|fast|lint|guard) ;;
  *) echo "사용법: run.sh [all|fast|lint|guard]"; exit 2 ;;
esac

# 이 그룹에서 돌릴 것인가
_want() {
  case "$GROUP" in
    lint)  [ "$1" = lint ] ;;
    guard) [ "$1" = guard ] ;;
    *)     [ "$1" != swift ] || command -v swift >/dev/null 2>&1 ;;
  esac
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  G=$'\033[32m'; R=$'\033[31m'; B=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'
else
  G=''; R=''; B=''; D=''; Z=''
fi

FAILED=""
SKIPPED=0
# run <그룹> <이름> <명령…>
run() {
  local group="$1" name="$2"; shift 2
  if ! _want "$group"; then SKIPPED=$((SKIPPED + 1)); return 0; fi
  printf '\n%s━━ %s %s\n' "$B" "$name" "$Z"
  if "$@"; then
    printf '%s✓ %s%s\n' "$G" "$name" "$Z"
  else
    printf '%s✗ %s%s\n' "$R" "$name" "$Z"
    FAILED="${FAILED}${name}
"
  fi
}

# ── 정적 검사 ────────────────────────────────────────────────────────────────
check_shell() {
  bash -n bin/devtrail install.sh || return 1
  for f in lib/*.sh lib/merge/*.sh lib/init/*.sh \
           tests/*.sh tests/lib/*.sh templates/scripts/*.tmpl; do
    [ -e "$f" ] || continue
    bash -n "$f" || return 1
  done
  echo "  셸 문법 OK"
}

check_python() {
  python3 -m py_compile lib/gen/*.py templates/dashboard/server.py || return 1
  echo "  파이썬 OK"
}

check_json() {
  local f
  for f in preset/tree.json preset/profiles/*.json preset/obsidian/*.json \
           templates/devtrail.config.json templates/obsidian/shellcommands.json; do
    [ -e "$f" ] || continue
    jq -e . "$f" >/dev/null || { echo "  ❌ $f"; return 1; }
  done
  echo "  JSON OK"
}

# ── 이 프로젝트 고유의 함정 ──────────────────────────────────────────────────
#
# 둘 다 실제로 사고가 났던 것이다. 문법 검사로는 안 잡힌다.

check_local_selfref() {
  # bash 3.2 는 local 한 줄의 이름을 '전부 먼저' 지역화한 뒤 대입한다.
  # 그래서 아래는 set -u 에서 죽는다:
  #
  #     local dot="$1" app="$dot/app.json"     # ✗ dot: unbound variable
  #     local dot="$1"; local app="$dot/..."   # ✓
  #
  # 실제로 5곳이 이랬고, 그중 4곳은 아직 실행이 도달하지 않아 조용했다.
  # 문법 검사로는 안 잡히고, 그 코드 경로를 밟아야만 터진다.
  local hits
  hits=$(git grep --untracked -nE 'local [A-Za-z_]+=' \
           -- '*.sh' 'bin/devtrail' 'install.sh' 2>/dev/null \
         | grep -vE ':[0-9]+:[[:space:]]*#' \
         | grep -v '^tests/run\.sh:' \
         | python3 -c '
import sys, re
for line in sys.stdin:
    parts = line.split(":", 2)
    if len(parts) < 3: continue
    f, n, code = parts
    m = re.search(r"\blocal\s+(.*)", code)
    if not m: continue
    names = []
    for nm, val in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)=(\S*(?:\"[^\"]*\")?\S*)", m.group(1)):
        for prev in names:
            if re.search(r"\$\{?" + prev + r"\}?\b", val):
                print(f"{f}:{n}: {nm} 가 같은 줄의 {prev} 를 참조")
        names.append(nm)
')
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  ❌ /'
    echo "  → local 을 줄로 나누세요 (bash 3.2 에서 unbound variable 로 죽습니다)"
    return 1
  fi
  echo "  local 자기참조 없음"
}

check_no_hardcoded_paths() {
  # 프리셋의 템플릿·허브·스킬에 볼트 경로가 박히면 사용자가 폴더명을 바꿀 때 깨진다.
  local hits
  hits=$(grep -rlE '창기/|"notes/개발' preset/templates preset/guides preset/learn 2>/dev/null)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  ❌ /'
    return 1
  fi
  echo "  경로 하드코딩 없음"
}

check_file_size() {
  # 400줄을 넘으면 분리를 검토한다. 600줄은 실패다.
  local over="" f n
  for f in lib/*.sh lib/merge/*.sh lib/init/*.sh lib/gen/*.py bin/devtrail; do
    [ -e "$f" ] || continue
    n=$(wc -l < "$f" | tr -d ' ')
    if [ "$n" -gt 600 ]; then
      printf '  ❌ %-28s %s줄 (600 초과)\n' "$f" "$n"
      over="y"
    elif [ "$n" -gt 400 ]; then
      printf '  %s⚠️  %-28s %s줄 (분리 검토)%s\n' "$D" "$f" "$n" "$Z"
    fi
  done
  [ -z "$over" ] && echo "  파일 길이 OK"
  [ -z "$over" ]
}

check_version() {
  # 버전은 VERSION 파일 하나에만 있어야 한다.
  # 두 곳에 박아두면 릴리스할 때 한쪽을 빠뜨린다 — 실제로 그랬다.
  [ -f VERSION ] || { echo "  ❌ VERSION 파일이 없다"; return 1; }

  local v; v=$(tr -d ' \n' < VERSION)
  case "$v" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "  ❌ 유의적 버전이 아니다: $v"; return 1 ;;
  esac

  local hard
  hard=$(git grep --untracked -nE 'VERSION="[0-9]+\.[0-9]+' -- 'bin' 'lib' 'app' 2>/dev/null)
  if [ -n "$hard" ]; then
    printf '%s\n' "$hard" | sed 's/^/  ❌ 하드코딩: /'
    return 1
  fi

  # CLI 가 내는 값과 파일이 같아야 한다
  local cli; cli=$(./bin/devtrail version 2>/dev/null | awk '{print $2}')
  [ "$cli" = "$v" ] || { echo "  ❌ devtrail version=$cli · VERSION=$v"; return 1; }

  # CHANGELOG 에 이 버전이 있어야 한다
  grep -q "^## \[$v\]" CHANGELOG.md 2>/dev/null \
    || { echo "  ❌ CHANGELOG 에 [$v] 항목이 없다"; return 1; }

  echo "  버전 $v · 단일 출처 · CHANGELOG 있음"
}

check_migrations() {
  # DT_SCHEMA 를 올려놓고 마이그레이션 파일을 안 만들면,
  # 사용자에게 "올려야 한다"고 말해놓고 아무것도 하지 않는다.
  local want n f
  want=$(grep -E '^DT_SCHEMA=' lib/migrate.sh | head -1 | cut -d= -f2)
  case "$want" in ''|*[!0-9]*) echo "  ❌ DT_SCHEMA 를 읽을 수 없다"; return 1 ;; esac

  n=2   # v1 은 최초 스키마라 마이그레이션이 없다
  while [ "$n" -le "$want" ]; do
    f=$(ls lib/migrations/$(printf '%03d' "$n")-*.sh 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "  ❌ v${n} 마이그레이션 파일이 없다"; return 1; }
    grep -q "^_mg_$(printf '%03d' "$n")()" "$f" \
      || { echo "  ❌ $f 에 _mg_$(printf '%03d' "$n")() 가 없다"; return 1; }
    grep -q "^_mg_$(printf '%03d' "$n")_why=" "$f" \
      || { echo "  ❌ $f 에 설명(_why)이 없다"; return 1; }
    n=$((n + 1))
  done
  echo "  스키마 v${want} · 마이그레이션 짝 맞음"
}

check_docs() {
  # 아키텍처 문서가 코드와 어긋나면 없느니만 못하다.
  # 기여자는 문서를 믿고 파일을 찾는다 — 없는 경로를 적어두면 거기서 막힌다.
  local doc=docs/ARCHITECTURE.md
  [ -f "$doc" ] || { echo "  ❌ $doc 이 없다"; return 1; }

  # 저장소 안을 가리키는 경로만 검사한다(런타임 파일은 여기 없는 게 맞다).
  local bad="" f
  for f in $(grep -oE '`(bin|lib|preset|tests|templates|skills|app)/[a-zA-Z0-9_./*-]+`' "$doc" \
             | tr -d '`' | sort -u); do
    ls $f >/dev/null 2>&1 || bad="$bad$f
"
  done
  if [ -n "$bad" ]; then
    printf '%s' "$bad" | sed 's/^/  ❌ 문서가 없는 경로를 가리킨다: /'
    return 1
  fi

  # 숫자로 적힌 것 중 코드에서 셀 수 있는 것을 대조한다.
  local claim actual
  claim=$(grep -oE '병합기 [0-9]+종' "$doc" | head -1 | grep -oE '[0-9]+')
  actual=$(ls lib/merge/*.sh 2>/dev/null | wc -l | tr -d ' ')
  [ "$claim" = "$actual" ] || { echo "  ❌ 병합기: 문서 ${claim} · 실제 ${actual}"; return 1; }

  # ⚠️ 스킬은 언어별로 한 벌씩 있다. 합쳐 세면 문서와 안 맞는다.
  # 템플릿 개수도 본다. 하나 추가하고 문서를 안 고치면 거짓말이 된다.
  #
  # ⚠️ ARCHITECTURE 뿐 아니라 README 양쪽도 본다. 개수는 여러 문서에 흩어져
  #    있어서, 한 곳만 검사하면 나머지가 조용히 낡는다.
  local actual d claim
  actual=$(ls preset/templates/ko/*.md 2>/dev/null | wc -l | tr -d ' ')
  for d in "$doc" README.md README.en.md; do
    [ -f "$d" ] || continue
    # ⚠️ 줄바꿈을 넘어야 한다. "노트 템플릿\n21종" 처럼 나뉘어 있으면
    #    한 줄만 보는 grep 이 못 잡는다 — 실제로 그랬다.
    claim=$(tr '\n' ' ' < "$d" \
            | grep -oE '(노트 템플릿|note templates) +[0-9]+종|[0-9]+ note templates' \
            | head -1 | grep -oE '[0-9]+')
    [ -n "$claim" ] || continue
    [ "$claim" = "$actual" ] \
      || { echo "  ❌ 템플릿: $d 는 ${claim} · 실제 ${actual}"; return 1; }
  done

  claim=$(grep -oE '스킬 [0-9]+종' "$doc" | head -1 | grep -oE '[0-9]+')
  actual=$(find skills/ko -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$claim" = "$actual" ] || { echo "  ❌ 스킬: 문서 ${claim} · 실제 ${actual}"; return 1; }

  # 두 언어의 스킬 목록이 같아야 한다. 한쪽에만 있으면 그 언어 사용자가 못 쓴다.
  local only
  only=$(comm -3 <(ls skills/ko 2>/dev/null | sort) <(ls skills/en 2>/dev/null | sort))
  if [ -n "$only" ]; then
    printf '%s\n' "$only" | sed 's/^/  ❌ 한쪽 언어에만 있는 스킬: /'
    return 1
  fi

  # 문서·템플릿이 없는 명령을 안내하면, 그대로 따라한 사람이 거기서 막힌다.
  #
  # ⚠️ ADR(docs/decisions/)은 예외다. 아직 만들지 않은 것을 '만들기로 한다'
  #    라고 적는 문서라, 여기서 없는 명령을 안내하는 것이 정상이다.
  #    사용자가 따라 하는 문서가 아니다.
  local known cmd unknown=""
  known=$(sed -n '/^case "$cmd" in/,/^esac/p' bin/devtrail \
          | grep -oE '^  [a-z|_-]+\)' | tr -d ' )' | tr '|' '\n' | sort -u)
  for cmd in $(git grep --untracked -hoE '(\./bin/)?devtrail [a-z][a-z-]*' -- \
                 '*.md' '.github' ':!docs/decisions' 2>/dev/null \
               | awk '{print $2}' | sort -u); do
    printf '%s\n' "$known" | grep -qx "$cmd" || unknown="$unknown$cmd
"
  done
  if [ -n "$unknown" ]; then
    printf '%s' "$unknown" | sed 's/^/  ❌ 문서가 없는 명령을 안내한다: devtrail /'
    return 1
  fi

  echo "  문서 경로 실재 · 개수 일치 · 명령 실재"
}

# ── 실행 ─────────────────────────────────────────────────────────────────────
# 정적 — 어느 OS 에서나 같은 답이 나온다
run lint  "셸 문법"        check_shell
run lint  "파이썬"         check_python
run lint  "JSON"          check_json

# 이 저장소 고유의 함정 — 문법 검사로는 안 잡힌다
run guard "bash 3.2"      python3 ./tests/check-bash32.py
run guard "local 자기참조"  check_local_selfref
run guard "L 인자"        python3 ./tests/check-l-arity.py
run guard "주석 중복"     python3 ./tests/check-dup-comments.py
run guard "경로 하드코딩"   check_no_hardcoded_paths
run guard "파일 길이"      check_file_size
run guard "버전"          check_version
run guard "마이그레이션"   check_migrations
run guard "시크릿"         ./tests/scan-secrets.sh
run guard "스킬 규약"      ./tests/check-skills.sh
run guard "문서 정합성"   check_docs

# 동작 — 실제로 실행해 봐야 아는 것
run behav "path"          ./tests/test-path.sh
run behav "augment"       ./tests/test-augment.sh
run behav "scan"          ./tests/test-scan.sh
run behav "undo·마이그레이션" ./tests/test-undo.sh
run behav "한국어·영어"    ./tests/test-i18n.sh
run behav "프로젝트 키"   ./tests/test-project-keys.sh
run behav "부트스트랩"     ./tests/test-bootstrap.sh

[ "$GROUP" = all ] && run swift "swift 빌드" \
  sh -c 'cd app && swift build -c release 2>&1 | tail -1'

# ── 결과 ─────────────────────────────────────────────────────────────────────
echo
if [ -n "$FAILED" ]; then
  printf '%s실패:%s\n' "$R" "$Z"
  printf '%s' "$FAILED" | sed 's/^/  /'
  exit 1
fi
if [ "$SKIPPED" -gt 0 ]; then
  printf '%s전부 통과%s %s(%s 그룹 · %s개 건너뜀)%s\n' "$G" "$Z" "$D" "$GROUP" "$SKIPPED" "$Z"
else
  printf '%s전부 통과%s\n' "$G" "$Z"
fi
