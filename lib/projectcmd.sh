#!/usr/bin/env bash
# DevTrail — `devtrail project <add|list>`
#
# 프로젝트를 '등록'하는 유일한 쓰기 경로다.
#
# 지금까지 등록은 devtrail init 뿐이었다. Obsidian 에서 ⌘⇧P 로 만든
# 프로젝트는 github.project_groups 에 없어서, 개발일지·개발메모의 선택창에
# 나타나지 않았다. Templater 는 셸을 부를 수 없으므로 자동화할 수 없다.
#
# ⚠️ 새 식별자를 만들지 않는다. project_groups 의 키가 정식 키다.
#    두 벌이면 반드시 갈라진다.  ADR 0001 D1.
# ⚠️ wildcard("acme-*")는 프로젝트가 아니라 PR 섹션 매칭 규칙이다. 거부한다.
#    여러 레포를 한 섹션에 모으려면 각각 등록하고 같은 --section 을 준다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

DT_SKELETON="${DEVTRAIL_ROOT}/preset/project-skeleton.json"

project_cmd() {
  require_config
  require_bins jq

  case "${1:-list}" in
    add)  shift; _pj_add "$@" ;;
    list) shift; _pj_list "$@" ;;
    *)    die "$(L "사용법" "Usage"): devtrail project <add|list>" ;;
  esac
}

# 정식 프로젝트 키인가.  ADR 0001 D3.
_pj_valid_key() {
  case "$1" in
    '') return 1 ;;
    *[*?/\\:\<\>\|\"[\]]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

_pj_list() {
  step "$(L "프로젝트" "Projects")"
  local groups; groups=$(cfg '.github.project_groups' '{}')
  local n; n=$(printf '%s' "$groups" | jq 'length')
  if [ "${n:-0}" = 0 ]; then
    dim "   $(L "등록된 프로젝트가 없습니다" "No projects registered")"
    dim "   devtrail project add <key>"
    return 0
  fi

  local root; root="$(vault_root)/$(dt_dir projects)"
  printf '%s' "$groups" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' \
  | while IFS=$'\t' read -r key section; do
      local mark folder
      if ! _pj_valid_key "$key"; then
        # wildcard 는 프로젝트가 아니다. PR 요약 전용이라고 밝힌다.
        printf '  %s  %-24s %s\n' "—" "$key" \
          "$(L "PR 요약 규칙 (프로젝트 아님)" "PR summary rule (not a project)")"
        continue
      fi
      folder="$root/$key"
      [ -d "$folder" ] && mark="✅" || mark="⚠️ "
      if [ "$key" = "$section" ]; then
        printf '  %s %-24s %s\n' "$mark" "$key" \
          "$([ -d "$folder" ] || printf '%s' "$(L "폴더 없음" "no folder")")"
      else
        printf '  %s %-24s → %s %s\n' "$mark" "$key" "$section" \
          "$([ -d "$folder" ] || printf '%s' "$(L "폴더 없음" "no folder")")"
      fi
    done
  echo
  dim "   $(L "→ 는 PR 요약이 들어갈 섹션명입니다" "→ is the PR summary section")"
}

# devtrail project add <key> [--section <name>] [--apply]
#
# 기존 폴더를 만났을 때의 계약 (ADR 0001 D4):
#   폴더 없음        등록 + 골격 생성
#   비었음           등록 + 없는 골격만 보강
#   README·노트 있음 등록만. 기존 파일을 절대 고치지 않는다
#   docs/ 일부만     없는 하위 폴더만 만든다
#   이미 등록됨      아무것도 하지 않고 그렇다고 말한다
_pj_add() {
  local key="" section="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --section) shift; section="${1:-}" ;;
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -*)        die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)         key="$1" ;;
    esac
    shift
  done

  [ -n "$key" ] || die "$(L "사용법" "Usage"): devtrail project add <key> [--section <name>]"

  # wildcard 는 프로젝트가 아니다. 여기서 막지 않으면 * 가 든 폴더를 만든다.
  if ! _pj_valid_key "$key"; then
    die "$(L "프로젝트 키로 쓸 수 없습니다" "Not usable as a project key"): $key
   $(L "태그와 폴더 이름이 되므로 * ? / \\ : < > | \" [ ] 를 쓸 수 없습니다." \
       "It becomes a tag and a folder name, so * ? / \\ : < > | \" [ ] are not allowed.")
   $(L "여러 레포를 한 섹션에 모으려면 각각 등록하고 같은 --section 을 주세요:" \
       "To group repos into one section, register each with the same --section:")
     devtrail project add acme-fe --section acme
     devtrail project add acme-be --section acme"
  fi

  [ -n "$section" ] || section="$key"

  local root; root="$(vault_root)/$(dt_dir projects)"
  local folder="$root/$key"
  local registered=0
  [ "$(cfg ".github.project_groups[\"$key\"]" '')" != "" ] && registered=1

  step "$(L "프로젝트" "Project"): $key"
  [ "$apply" = 1 ] || dim "   $(L "(dry-run — 실제로 만들려면 --apply)" "(dry run — pass --apply to create)")"

  # ── 무엇을 할 것인가 ───────────────────────────────────────────────────────
  local will_register=0 will_make=""
  if [ "$registered" = 1 ]; then
    dim "   $(L "이미 등록됨" "Already registered") → $(cfg ".github.project_groups[\"$key\"]")"
  else
    will_register=1
    ok "$(L "등록" "register")  $key → $section"
  fi

  local d
  for d in "$folder" "$folder/worklogs" \
           $(jq -r --arg f "$folder" '.docs[] | $f + "/docs/" + .' "$DT_SKELETON"); do
    [ -d "$d" ] && continue
    will_make="$will_make$d
"
  done

  local n; n=$(printf '%s' "$will_make" | grep -c . | tr -d ' ')
  if [ "${n:-0}" -gt 0 ]; then
    ok "$(L "폴더 ${n}개 생성" "create ${n} folders")"
    printf '%s' "$will_make" | sed "s|^$root/|     |" | head -12
  else
    dim "   $(L "골격이 이미 다 있습니다" "The skeleton is already complete")"
  fi

  # 기존 파일이 있으면 밝힌다 — 건드리지 않는다는 약속이다.
  if [ -d "$folder" ]; then
    local files; files=$(find "$folder" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "${files:-0}" -gt 0 ] && dim "   $(L "기존 노트 ${files}개는 건드리지 않습니다" \
                                          "${files} existing notes are left alone")"
  fi

  if [ "$will_register" = 0 ] && [ "${n:-0}" = 0 ]; then
    echo; dim "   $(L "할 일이 없습니다" "Nothing to do")"; return 0
  fi

  if [ "$apply" = 0 ]; then
    echo; dim "   $(L "적용" "Apply"): devtrail project add $key --apply"
    return 0
  fi

  # ── 적용 ───────────────────────────────────────────────────────────────────
  #
  # ⚠️ 설정 쓰기와 폴더 생성을 하나의 저널 작업으로 묶는다. 어느 쪽이 실패해도
  #    devtrail undo 로 되돌아간다 — 설정만 바뀌고 폴더가 없는 상태를 남기지
  #    않는다.  ADR 0001 D4.
  jr_begin project-add

  if [ "$will_register" = 1 ]; then
    jr_backup "$CONFIG_FILE" >/dev/null \
      || { die "$(L "설정 백업 실패 — 아무것도 바꾸지 않았습니다" \
                   "Config backup failed — nothing was changed")"; }
    local tmp; tmp=$(mktemp "$(dirname "$CONFIG_FILE")/.dt-pj.XXXXXX")
    if ! jq --arg k "$key" --arg s "$section" \
          '.github.project_groups[$k] = $s' "$CONFIG_FILE" > "$tmp"; then
      rm -f "$tmp"; die "$(L "설정 변경 실패 — 원본 유지" "Config update failed — original kept")"
    fi
    jq -e . "$tmp" >/dev/null 2>&1 \
      || { rm -f "$tmp"; die "$(L "결과가 유효한 JSON 이 아님 — 원본 유지" \
                                 "The result is not valid JSON — original kept")"; }
    mv "$tmp" "$CONFIG_FILE"
  fi

  while IFS= read -r d; do
    [ -n "$d" ] || continue
    jr_mkdir "$d" || warn "$(L "폴더 생성 실패" "Could not create folder"): $d"
  done <<EOF
$will_make
EOF

  # 경로 맵을 갱신해야 선택창에 즉시 반영된다.
  _aug_paths_note

  echo
  ok "$(L "완료" "Done"): $key"
  dim "   $(L "개발일지·개발메모의 선택창에 바로 나타납니다" \
             "It appears in the devlog and dev-note pickers right away")"
  jr_end
}
