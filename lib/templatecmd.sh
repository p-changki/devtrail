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

  if [ "$apply" = 0 ]; then
    echo
    dim "   $(L "내용 보기" "See it"): devtrail template diff $name"
    dim "   $(L "적용" "Apply"): devtrail template update $name --apply"
    return 0
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
