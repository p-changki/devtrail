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

DT_SKELETON="${DT_PRESET}/project-skeleton.json"

project_cmd() {
  require_config
  require_bins jq

  case "${1:-list}" in
    add)   shift; _pj_add "$@" ;;
    stage) shift; _pj_stage "$@" ;;
    list)  shift; _pj_list "$@" ;;
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
# 프로젝트 허브(README)를 만든다.
#
# ⚠️ 개발일지·개발메모·트러블슈팅 템플릿이 전부 `<프로젝트>/README` 로 링크한다.
#    이게 없으면 링크가 전부 깨지고 허브의 입구가 사라진다 —
#    2026-08-22 실물 QA 에서 CLI 로 만든 프로젝트가 그 상태였다.
#
# 본문은 preset/hub/project-readme.<lang>.md 한 곳에서만 온다.
# Obsidian 의 「프로젝트 생성 템플릿」도 같은 파일을 읽는다 — 두 벌을 두면
# 언젠가 어긋난다(이번 QA 에서 잡은 결함 6개 중 셋이 그 유형이었다).
#
# 이미 있으면 절대 건드리지 않는다. 사용자가 쓴 목표·상태가 거기 있다.
_pj_readme() {
  local key="$1"
  local dir; dir="$(dt_path projects)/$key"
  local out="$dir/README.md"
  [ -d "$dir" ] || return 0
  [ -f "$out" ] && return 0

  local src="$DT_PRESET/hub/project-readme.$(dt_lang).md"
  [ -f "$src" ] || src="$DT_PRESET/hub/project-readme.ko.md"
  [ -f "$src" ] || { warn "$(L "허브 원본 없음" "Hub source missing"): $src"; return 0; }

  local folder; folder="$(vault_rel "$(dt_dir projects)")/$key"
  local repodocs; repodocs="$(vault_rel "$(dt_dir repodocs)")"
  local today; today="$(date +%Y-%m-%d)"

  local tmp; tmp=$(mktemp)
  sed -e "s|{{STAGE}}|$stage|g" \
      -e "s|{{NAME}}|$key|g" \
      -e "s|{{FOLDER}}|$folder|g" \
      -e "s|{{REPODOCS}}|$repodocs|g" \
      -e "s|{{TODAY}}|$today|g" \
      "$src" > "$tmp" || { rm -f "$tmp"; return 1; }

  # ⚠️ 치환자가 남으면 Dataview 쿼리가 존재하지 않는 폴더를 가리킨다.
  if grep -q '{{' "$tmp"; then
    rm -f "$tmp"
    warn "$(L "허브 치환 실패 — README 를 만들지 않습니다" \
            "Hub substitution failed — not writing README"): $key"
    return 1
  fi
  mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
  jr_created "$out"
  ok "$(L "허브 생성" "Hub created"): $key/README.md"
}

# 프로젝트 단계. 대시보드가 이 값으로 칸을 나눈다.
#
# ⚠️ 목록을 여기 한 곳에만 둔다. 화면·템플릿·검증이 각자 갖고 있으면
#    언젠가 한쪽만 늘어나고, 사용자는 "적었는데 안 잡힌다" 를 만난다.
DT_PJ_STAGES="planning in-progress blocked done"

_pj_valid_stage() {
  case " $DT_PJ_STAGES " in *" $1 "*) return 0 ;; esac
  return 1
}

# devtrail project stage <키> <단계>  — 이미 있는 프로젝트의 단계를 정한다.
#
# ⚠️ 왜 필요한가 (2026-08-24 실물 QA)
#
#    대시보드는 frontmatter 의 `stage` 로 칸을 나눈다. 그런데 사용자가 자기
#    Templater 템플릿으로 만든 프로젝트에는 그 키가 없다 — 화면에는
#    **"단계 미지정"** 으로만 쌓이고, 고치려면 노트를 직접 열어 손으로
#    적어야 했다.
#
# ⚠️ 새 스키마를 만드는 게 아니다. `stage` 는 이미 계약에 있고, 없는 노트에
#    **그 키를 채워 넣을 수단**이 없었을 뿐이다.
#
# ⚠️ 기본은 dry-run 이다. 그리고 저널에 남겨 되돌릴 수 있게 한다 —
#    사용자 노트를 고치는 일이다.
_pj_stage() {
  require_config
  local key="" stage="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -*)        die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)         if [ -z "$key" ]; then key="$1"; else stage="$1"; fi ;;
    esac
    shift
  done

  [ -n "$key" ] && [ -n "$stage" ] \
    || die "$(L "사용법" "Usage"): devtrail project stage <키> <$(printf '%s' "$DT_PJ_STAGES" | tr ' ' '|')> [--apply]"
  _pj_valid_stage "$stage" || die "$(L "모르는 단계" "Unknown stage"): $stage
   $(L "쓸 수 있는 값" "Allowed"): $DT_PJ_STAGES"

  local root; root="$(vault_root)/$(dt_dir projects)"
  local note="$root/$key/README.md"
  # ⚠️ 사용자가 자기 템플릿으로 만든 프로젝트는 이름이 다를 수 있다.
  [ -f "$note" ] || note=$(find "$root/$key" -maxdepth 1 -name '*.md' 2>/dev/null | head -1)
  [ -n "$note" ] && [ -f "$note" ] \
    || die "$(L "프로젝트 노트를 찾지 못했습니다" "No project note found"): $root/$key"

  local cur; cur=$(awk '/^stage:/{sub(/^stage:[[:space:]]*/,""); print; exit}' "$note")
  if [ "$cur" = "$stage" ]; then
    ok "$(L "이미 그 단계입니다" "Already at that stage"): $key → $stage"
    return 0
  fi

  step "$(L "프로젝트 단계" "Project stage")"
  printf '   %s  %s → %s\n' "$key" "${cur:-$(L "없음" "none")}" "$stage"
  dim "   $note"

  if [ "$apply" != 1 ]; then
    echo
    dim "   $(L "적용" "Apply"): devtrail project stage $key $stage --apply"
    return 0
  fi

  jr_begin project-stage
  jr_backup "$note" >/dev/null || { jr_end; die "$(L "백업 실패 — 원본을 건드리지 않습니다" \
                                                    "Backup failed — leaving the original alone"): $note"; }
  local tmp; tmp=$(mktemp)
  if [ -n "$cur" ]; then
    # ⚠️ frontmatter 안의 stage 만 바꾼다. 본문에 같은 글자가 있어도 건드리지 않는다.
    awk -v s="$stage" '
      NR==1 && $0=="---" { fm=1; print; next }
      fm==1 && $0=="---" { fm=0; print; next }
      fm==1 && /^stage:/ { print "stage: " s; next }
      { print }
    ' "$note" > "$tmp"
  else
    # ⚠️ 키가 없으면 frontmatter 끝에 넣는다. frontmatter 가 없으면 만들지
    #    않는다 — 노트의 모양을 바꾸는 일은 여기서 할 일이 아니다.
    awk -v s="$stage" '
      NR==1 && $0=="---" { fm=1; print; next }
      fm==1 && $0=="---" { print "stage: " s; fm=0; print; next }
      { print }
    ' "$note" > "$tmp"
  fi

  if ! grep -q '^stage: ' "$tmp"; then
    rm -f "$tmp"; jr_end
    die "$(L "frontmatter 가 없어 단계를 넣지 못했습니다" \
            "No frontmatter — could not set the stage"): $note"
  fi
  mv "$tmp" "$note" || { rm -f "$tmp"; jr_end; die "$(L "쓰지 못했습니다" "Could not write"): $note"; }
  jr_end
  ok "$(L "단계를 정했습니다" "Stage set"): $key → $stage"
}

_pj_add() {
  local key="" section="" apply=0 stage="planning"
  while [ $# -gt 0 ]; do
    case "$1" in
      --section) shift; section="${1:-}" ;;
      --stage)   shift; stage="${1:-}" ;;
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -*)        die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)         key="$1" ;;
    esac
    shift
  done

  [ -n "$key" ] || die "$(L "사용법" "Usage"): devtrail project add <key> [--section <name>] [--stage <단계>]"

  # ⚠️ 모르는 단계를 쓰면 대시보드에서 '단계 미지정' 으로 빠진다. 여기서 막는다.
  _pj_valid_stage "$stage" || die "$(L "모르는 단계" "Unknown stage"): $stage
   $(L "쓸 수 있는 값" "Allowed"): $DT_PJ_STAGES"

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

  # ⚠️ README 도 '할 일' 로 센다. 이걸 빼면 이미 등록된 프로젝트는
  #    "할 일이 없습니다" 로 빠져나가 허브를 영영 못 받는다 —
  #    템플릿이 거는 <프로젝트>/README 링크가 계속 깨진 채로 남는다.
  local will_readme=0
  if [ ! -f "$folder/README.md" ]; then
    will_readme=1
    ok "$(L "허브 생성" "create hub")  $key/README.md"
  fi

  # 기존 파일이 있으면 밝힌다 — 건드리지 않는다는 약속이다.
  if [ -d "$folder" ]; then
    local files; files=$(find "$folder" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "${files:-0}" -gt 0 ] && dim "   $(L "기존 노트 ${files}개는 건드리지 않습니다" \
                                          "${files} existing notes are left alone")"
  fi

  if [ "$will_register" = 0 ] && [ "${n:-0}" = 0 ] && [ "$will_readme" = 0 ]; then
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

  _pj_readme "$key"

  # 경로 맵을 갱신해야 선택창에 즉시 반영된다.
  _aug_paths_note

  echo
  ok "$(L "완료" "Done"): $key"
  dim "   $(L "개발일지·개발메모의 선택창에 바로 나타납니다" \
             "It appears in the devlog and dev-note pickers right away")"
  jr_end
}
