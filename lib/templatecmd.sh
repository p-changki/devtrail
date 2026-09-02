#!/usr/bin/env bash
# DevTrail — `devtrail template <list|diff|update>`
#
# 설치된 템플릿이 구버전일 때 무엇을 할지 사용자가 정한다.
#
# ⚠️ 자동으로 덮어쓰지 않는다. 사용자가 고친 템플릿을 잃는 것보다
#    새 기능이 늦게 오는 편이 낫다. DevTrail 의 안전 계약이다.
# ⚠️ 판별은 헬퍼 헤더의 버전 표시로 한다. 사용자가 헤더를 지웠다면
#    구버전으로 보고 '알리기만' 한다 — 틀린 알림이 조용한 오작동보다 낫다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# 현재 헬퍼 버전. 올릴 때 preset/templates/*/_lib.js.txt 의 표시도 함께 바꾼다.
DT_TPL_VERSION=2

template_cmd() {
  require_config
  require_bins jq

  case "${1:-list}" in
    list)   shift; _tpl_list "$@" ;;
    diff)   shift; _tpl_diff "$@" ;;
    update) shift; _tpl_update "$@" ;;
    *)      die "$(L "사용법" "Usage"): devtrail template <list|diff|update>" ;;
  esac
}

_tpl_src_dir() {
  local base="$DT_PRESET/templates"
  local d="$base/$(dt_lang)"
  [ -d "$d" ] || d="$base/ko"
  printf '%s' "$d"
}

_tpl_dest_dir() { printf '%s/%s' "$(vault_root)" "$(dt_dir templates)"; }

# 파일의 헬퍼 버전. 없으면 1 로 본다(표시가 없던 시절).
_tpl_version_of() {
  [ -f "$1" ] || { printf '0'; return; }
  grep -qE '(공통 헬퍼|shared helpers) v[0-9]+' "$1" || { printf '1'; return; }
  sed -nE 's/.*(공통 헬퍼|shared helpers) v([0-9]+).*/\2/p' "$1" | head -1
}

# 구버전 템플릿 목록을 낸다: <파일명><TAB><설치버전>
_tpl_outdated() {
  local src dest f name v
  src="$(_tpl_src_dir)"; dest="$(_tpl_dest_dir)"
  [ -d "$dest" ] || return 0
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    [ -f "$dest/$name" ] || continue
    # 원본이 헬퍼를 쓰지 않으면 버전 개념이 없다
    grep -q 'DevTrail' "$f" || continue
    v=$(_tpl_version_of "$dest/$name")
    [ "${v:-1}" -lt "$DT_TPL_VERSION" ] && printf '%s\t%s\n' "$name" "$v"
  done
  return 0
}

_tpl_list() {
  step "$(L "노트 템플릿" "Note templates")"
  local out; out=$(_tpl_outdated)
  if [ -z "$out" ]; then
    ok "$(L "전부 최신입니다" "All up to date") (v${DT_TPL_VERSION})"
    return 0
  fi
  local n; n=$(printf '%s' "$out" | grep -c . | tr -d ' ')
  warn "$(L "구버전 ${n}개" "${n} outdated")"
  printf '%s\n' "$out" | while IFS=$'\t' read -r name v; do
    [ -n "$name" ] || continue
    printf '     v%-3s %s\n' "${v}" "$name"
  done
  echo
  dim "   $(L "무엇이 다른지" "See the difference"): devtrail template diff <$(L "이름" "name")>"
  dim "   $(L "바꾸기 (백업 후)" "Replace (backed up)"): devtrail template update <$(L "이름" "name")>"
}

_tpl_diff() {
  local name="${1:-}"
  [ -n "$name" ] || die "$(L "사용법" "Usage"): devtrail template diff <$(L "이름" "name")>"
  local src dest
  src="$(_tpl_src_dir)/$name"; dest="$(_tpl_dest_dir)/$name"
  [ -f "$src" ]  || die "$(L "배포본에 없는 템플릿" "Not a shipped template"): $name"
  [ -f "$dest" ] || die "$(L "설치되지 않았습니다" "Not installed"): $name"

  step "$name  ($(L "설치본" "installed") v$(_tpl_version_of "$dest") → $(L "배포본" "shipped") v${DT_TPL_VERSION})"
  dim "   $(L "왼쪽이 설치본, 오른쪽이 새 배포본입니다" "Left is installed, right is the new one")"
  echo
  diff -u "$dest" "$src" || true
}

# 교체가 설정의 헤딩 짝을 깨는가.
#
# ⚠️ 헤딩은 **두 곳**에 있다 — 노트를 만드는 볼트 템플릿과, 그 노트에서
#    넣을 자리를 찾는 설정의 headings.*(activity.sh · summary.sh 가 읽는다).
#    둘은 짝이다. 교체가 그 짝을 조용히 깨면 그날 만든 개발일지부터
#    활동 삽입도 PR 요약도 넣을 자리를 못 찾는다.
#
# ⚠️ 2026-08-29 에 실제로 그렇게 깨졌다. 사용자는 헤딩을 한국어로 바꿔
#    두었는데(config set headings.*), 배포본 템플릿은 "## Issues / PRs" 를
#    쓴다. `template update --apply` 가 아무 말 없이 바꿔놓았고, 이틀 뒤
#    개발일지부터 활동이 안 들어갔다. 그동안 메뉴바 앱은 초록불이었다.
#
# ⚠️ 지금 템플릿에 **있는** 헤딩만 본다. 처음부터 없던 헤딩은 이 교체가
#    깨는 것이 아니다 — 없던 것을 교체 탓으로 돌리면 경고가 늑대소년이 된다.
_tpl_heading_guard() {   # _tpl_heading_guard <src> <dest>  깨지면 1
  local src="$1" dest="$2" k h miss=""
  for k in issues_pr worklog morning youtube; do
    h=$(cfg ".headings.$k" '')
    [ -n "$h" ] || continue
    grep -qF "$h" "$dest" 2>/dev/null || continue
    grep -qF "$h" "$src"  2>/dev/null || miss="$miss $k"
  done
  [ -n "$miss" ] || return 0

  echo
  warn "$(L "새 템플릿에는 설정된 헤딩이 없습니다" \
           "The new template does not have your configured headings")"
  for k in $miss; do
    dim "     headings.$k = $(cfg ".headings.$k" '')"
  done
  echo
  dim "   $(L "이대로 바꾸면 이후에 만든 개발일지에는" \
              "Replace it as is and, in devlogs created from now on,")"
  dim "   $(L "활동 삽입(devtrail activity)과 PR 요약(devtrail summary)이" \
              "activity insertion (devtrail activity) and PR summaries (devtrail summary)")"
  dim "   $(L "넣을 자리를 찾지 못합니다." "will not find their place.")"
  echo
  dim "   $(L "새 템플릿의 헤딩:" "Headings in the new template:")"
  grep -E '^#{1,6} ' "$src" 2>/dev/null | sed 's/^/     /' | head -6
  echo
  dim "   $(L "바꾸려면 설정도 함께 맞추세요:" "To go ahead, move the config with it:")"
  for k in $miss; do
    dim "     devtrail config set headings.$k '<$(L "새 헤딩" "new heading")>' --apply"
  done
  echo
  return 1
}

_tpl_update() {
  local name="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -*)        die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)         name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die "$(L "사용법" "Usage"): devtrail template update <$(L "이름" "name")> [--apply]"

  local src dest
  src="$(_tpl_src_dir)/$name"; dest="$(_tpl_dest_dir)/$name"
  [ -f "$src" ]  || die "$(L "배포본에 없는 템플릿" "Not a shipped template"): $name"
  [ -f "$dest" ] || die "$(L "설치되지 않았습니다" "Not installed"): $name"

  if cmp -s "$src" "$dest"; then
    ok "$(L "이미 같습니다" "Already identical"): $name"; return 0
  fi

  step "$(L "템플릿 교체" "Replace template"): $name"
  local changed; changed=$(diff "$dest" "$src" | grep -c '^[<>]' | tr -d ' ')
  info "  $(L "바뀌는 줄 ${changed}개" "${changed} lines change")"
  dim "   $(L "설치본" "installed") v$(_tpl_version_of "$dest") → $(L "배포본" "shipped") v${DT_TPL_VERSION}"

  # ⚠️ dry-run 에서도 말한다. '적용해 봐야 아는 위험'은 경고가 아니다.
  local breaks=0
  _tpl_heading_guard "$src" "$dest" || breaks=1

  if [ "$apply" = 0 ]; then
    echo
    dim "   $(L "내용 보기" "See it"): devtrail template diff $name"
    dim "   $(L "적용" "Apply"): devtrail template update $name --apply"
    return 0
  fi

  # ⚠️ 막지는 않는다 — 무슨 일이 일어나는지 먼저 말하고 사용자가 정한다.
  #    (lang 을 바꿀 때와 같은 계약이다.) 대답을 못 받으면 '아니오'다:
  #    비대화형에서 read 는 실패하고, 그때 조용히 덮어쓰는 것이 최악이다.
  if [ "$breaks" = 1 ]; then
    confirm "$(L "그래도 바꿀까요?" "Replace anyway?")" \
      || { info "$(L "취소했습니다 — 템플릿을 건드리지 않았습니다." \
                     "Cancelled — the template was not touched.")"; return 1; }
  fi

  # ⚠️ 백업이 실패하면 원본을 건드리지 않는다. 저널에 남아 undo 로 되돌아간다.
  jr_begin template-update
  jr_backup "$dest" >/dev/null \
    || die "$(L "백업 실패 — 원본을 건드리지 않습니다" "Backup failed — leaving the original alone"): $dest"
  cp "$src" "$dest" || die "$(L "복사 실패" "Copy failed"): $name"
  echo
  ok "$(L "교체 완료" "Replaced"): $name"
  jr_end
}
