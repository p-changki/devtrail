# DevTrail Command Center 배포물 계약 — plugin/files.json 하나가 정본이다.
#
# ⚠️ 왜 글롭이 아닌가: 글롭은 새 파일을 우연히 포함할 수는 있어도 **제거된
#    파일**을 다루지 못한다. 모듈을 지운 릴리스에서 그 파일은 배포에서 빠질
#    뿐, 사용자 폴더엔 영원히 남는다. 무엇을 지울지 알려면 "이전에 무엇을
#    깔았나" 의 기록이 필요하고, 그 기록이 설치본의 files.json 이다.
#
# 근거: docs/decisions/0004-plugin-file-split.md

# 배포물 목록 — plugin/files.json 하나에서만 온다 (ADR 0004).
#
# ⚠️ 목록을 셸에 박지 않는다. 두 곳에 있으면 반드시 갈라진다 — 이 저장소가
#    dirs.devlog 로 네 번 겪은 병이다.
# ⚠️ files.json 자체도 배포한다. 그것이 "이전 릴리스가 무엇을 깔았나" 의
#    기록이고, 그 기록이 있어야 사라진 파일을 안전하게 지울 수 있다.
_cc_manifest_list() {
  local dir="$1" f="$1/files.json"
  [ -f "$f" ] || return 1
  jq -r '
    if (.schema // 0) != 1 then error("unknown schema") else . end
    | .files[]
    # ⚠️ 볼트 밖을 가리키는 경로를 거부한다. 배포가 남의 파일을 덮어쓰면
    #    되돌릴 방법이 없다.
    | select(startswith("/") | not)
    | select(test("\\.\\.") | not)
    | select(test("(^|/)\\.") | not)
  ' "$f" 2>/dev/null | awk '!seen[$0]++'
}

_cc_files() {
  # ⚠️ 환경변수로 목록을 갈아끼우던 봉합 지점(DT_CC_FILES_OVERRIDE)을 없앴다.
  #    files.json 이 정본이 된 이상 그것은 두 번째 출처다 — 테스트도 진짜
  #    목록을 쓴다.
  local f
  _cc_manifest_list "$DT_CC_SRC" | while IFS= read -r f; do
    [ -f "$DT_CC_SRC/$f" ] && printf '%s\n' "$f"
  done
}

# 이 경로가 정말 설치 폴더 **안**인가.
#
# ⚠️ 목록 필터만으로는 부족하다. 지우는 자리에서 한 번 더 본다 — 필터가
#    언젠가 느슨해져도 여기서 막힌다. 방어는 위험한 동작 옆에 둔다.
# ⚠️ 심볼릭 링크로 밖을 가리킬 수도 있으므로 실제 경로로 풀어 비교한다.
_cc_inside() {
  local dest="$1" path="$2" rd rp
  rd=$(cd "$dest" 2>/dev/null && pwd -P) || return 1
  # 파일이 있어야 지울 수 있다. 없으면 애초에 대상이 아니다.
  [ -e "$path" ] || return 1
  rp=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
  rp="$rp/$(basename "$path")"
  case "$rp" in
    "$rd"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 이전 릴리스가 깔았지만 이번 목록에 없는 것.
#
# ⚠️ 설치본의 files.json 에 적힌 것만 지운다. 그 기록이 없으면(옛 설치본)
#    아무것도 지우지 않는다 — 모르는 것을 지우느니 남기는 게 낫다.
_cc_orphans() {
  local dest="$1" now old
  [ -f "$dest/files.json" ] || return 0
  now=$(_cc_files | sort)
  old=$(_cc_manifest_list "$dest" | sort)
  comm -13 <(printf '%s\n' "$now") <(printf '%s\n' "$old")
}
