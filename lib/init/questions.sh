#!/usr/bin/env bash
# DevTrail — init: 셋업 질문들.
#
# 탐지 결과가 비면 질문을 건너뛴다 — 빈 볼트 사용자에게
# 기존 볼트용 매핑 질문을 던지면 짜증난다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)


# ⚠️ 언어는 가장 먼저 묻는다. 이 답이 폴더 이름과 나머지 질문의 문구를
#    결정하기 때문이다. 뒤에서 물으면 이미 만들어진 것과 어긋난다.
#
# 로케일은 '제안'일 뿐이다. 한국에서 영어 로케일을 쓰는 사람도 많고,
# 그 반대도 있다. 판단은 사용자가 한다.
_init_lang() {
  local guess; guess=$(dt_lang_from_locale)
  local reply

  {
    echo
    printf '%s\n' "${C_BOLD}Language / 언어${C_RESET}"
    dim "   Folder names, note templates, and everything DevTrail prints."
    dim "   폴더 이름 · 노트 템플릿 · DevTrail 이 출력하는 모든 문구에 쓰입니다."
    printf '    1) 한국어  (개발/개발일지 · 자료실/20_카드노트)\n'
    printf '    2) English (Dev/Devlog · Library/20_Zettel)\n'
    echo
    dim "   Tags never change: #type/devlog is the same either way."
    dim "   태그는 언어와 무관합니다 — #type/devlog 는 양쪽에서 같습니다."
  } >&2

  local hint="1"; [ "$guess" = "en" ] && hint="2"
  read -r -p "선택 / Choose [$hint]: " reply
  reply="${reply:-$hint}"

  case "$reply" in
    2|en|EN|english|English) printf 'en' ;;
    *)                       printf 'ko' ;;
  esac
}

_init_backend() {
  {
    echo
    printf '%s\n' "${C_BOLD}1. $(L "저장소 위치" "Where the vault lives")${C_RESET}"
    echo "   1) $(L "로컬        — 클라우드 동기화 없음. 권한 문제 없음" \
                    "Local        — no cloud sync, no permission issues")"
    echo "   2) $(L "iCloud      — 맥 간 동기화. 전체 디스크 접근 권한 필요" \
                    "iCloud       — syncs across Macs. Needs Full Disk Access")"
    echo "   3) $(L "Google Drive— 미검증(MVP). 스트리밍 모드 주의" \
                    "Google Drive — untested. Beware streaming mode")"
  } >&2
  local n
  n=$(_init_ask "$(L "선택" "Choose")" "1" 2>/dev/null)
  case "$n" in
    2) printf 'icloud' ;;
    3) printf 'gdrive' ;;
    *) printf 'local' ;;
  esac
}


# 경로를 손으로 치게 하는 마지막 수단.
_init_vault_typed() {
  local suggest="$1" p
  p=$(_init_ask "$(L "경로" "Path")" "$suggest" 2>/dev/null)
  p="${p%/}"
  [ -n "$p" ] || return 1
  if [ ! -d "$p" ]; then
    if confirm "   $(L "폴더가 없습니다. 새로 만들까요?" "That folder does not exist. Create it?") ($p)" >&2; then
      mkdir -p "$p" || die "$(L "폴더 생성 실패" "Could not create folder"): $p"
    else
      return 1
    fi
  fi
  printf '%s' "$p"
}

# 볼트 고르기.
#
# 예전에는 절대경로를 손으로 치게 했다. 사용자는 자기 볼트가 어디 있는지
# 모른다 — iCloud 볼트의 실제 경로를 외우는 사람은 없다.
# Obsidian 은 자기가 아는 볼트를 레지스트리에 갖고 있으므로, 그걸 읽어
# 목록으로 보여준다. 목록이 비어 있을 때만 예전처럼 묻는다.
_init_vault() {
  local backend="$1" suggest=""
  case "$backend" in
    icloud) suggest="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Obsidian Vault" ;;
    gdrive) suggest=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name 'GoogleDrive-*' 2>/dev/null | head -1) ;;
    *)      suggest="$HOME/DevTrailVault" ;;
  esac

  . "$DEVTRAIL_ROOT/lib/obsidian_app.sh"

  local known=() v
  while IFS= read -r v; do [ -n "$v" ] && known+=("$v"); done <<EOF
$(oa_vaults 2>/dev/null)
EOF

  {
    echo
    printf '%s\n' "${C_BOLD}2. $(L "볼트" "Vault")${C_RESET}"
  } >&2

  # 아는 볼트가 없으면 예전 방식 그대로.
  if [ ${#known[@]} -eq 0 ]; then
    dim "   $(L "Obsidian 볼트 폴더의 절대경로입니다. 없으면 만들어 드립니다." \
                "Absolute path to your Obsidian vault. We create it if missing.")" >&2
    local typed; typed=$(_init_vault_typed "$suggest") \
      || die "$(L "볼트를 정하지 않았습니다." "No vault chosen.")"
    printf '%s' "$typed"
    return 0
  fi

  local i=0 n
  {
    dim "   $(L "Obsidian 이 알고 있는 볼트입니다." "Vaults Obsidian already knows about.")"
    while [ $i -lt ${#known[@]} ]; do
      n=$(oa_note_count "${known[$i]}")
      printf '   %2d) %-28s %s\n' $((i + 1)) "$(basename "${known[$i]}")" \
        "${C_MUTED}$(L "노트 ${n}개" "${n} notes") · ${known[$i]}${C_RESET}"
      i=$((i + 1))
    done
    printf '   %2d) %s\n' $((${#known[@]} + 1)) "$(L "새 볼트 만들기" "Create a new vault")"
    printf '   %2d) %s\n' $((${#known[@]} + 2)) "$(L "경로 직접 입력" "Type a path")"
  } >&2

  local pick; pick=$(_init_ask "$(L "선택" "Choose")" "1" 2>/dev/null)
  case "$pick" in
    ''|*[!0-9]*) pick=1 ;;
  esac

  if [ "$pick" -ge 1 ] && [ "$pick" -le ${#known[@]} ]; then
    printf '%s' "${known[$((pick - 1))]}"
    return 0
  fi

  local target=""
  if [ "$pick" -eq $((${#known[@]} + 1)) ]; then
    dim "   $(L "만들 위치입니다. 없으면 만들어 드립니다." "Where to create it. We make it if missing.")" >&2
    target=$(_init_vault_typed "$HOME/DevTrailVault")
  else
    target=$(_init_vault_typed "$suggest")
  fi
  [ -n "$target" ] || die "$(L "볼트를 정하지 않았습니다." "No vault chosen.")"
  printf '%s' "$target"
}


_init_github() {
  {
    echo
    printf '%s\n' "${C_BOLD}3. GitHub${C_RESET}"
  } >&2
  local detected=""
  if has gh && gh auth status >/dev/null 2>&1; then
    detected=$(gh api user --jq .login 2>/dev/null)
    [ -n "$detected" ] && ok "$(L "gh 인증 감지" "gh account detected"): $detected" >&2
  else
    warn "$(L "gh 미인증 — 나중에 'gh auth login' 후 doctor 를 다시 실행하세요" \
              "gh not authenticated — run 'gh auth login', then doctor again")" >&2
  fi
  _init_ask "$(L "GitHub 사용자명" "GitHub username")" "$detected" 2>/dev/null
}


_init_src_root() {
  {
    echo
    printf '%s\n' "${C_BOLD}4. $(L "프로젝트 폴더" "Projects folder")${C_RESET}"
    dim "   $(L "레포들이 모여 있는 상위 폴더입니다. 각 레포의 docs/ 를 볼트로 가져옵니다." \
                "The folder your repos live in. Each repo's docs/ is pulled into the vault.")"
    dim "   $(L "다음 단계에서 이 폴더 안의 레포를 골라 동기화 대상으로 지정합니다." \
                "In the next step you pick which of those repos to sync.")"
  } >&2
  _init_ask "$(L "경로" "Path")" "$HOME/Desktop" 2>/dev/null
}

# _init_pick <제목> <개행으로 구분된 항목> [기본값]  →  선택된 항목을 개행으로 출력
#
# 기본값 "a" 는 Enter 만 눌렀을 때 전체 선택, 빈 문자열이면 아무것도 고르지 않는다.
# 안내 문구는 반드시 실제 기본값과 일치해야 한다 — 어긋나면 사용자가 의도하지
# 않은 항목을 켜게 된다(요약 섹션이 레포 수만큼 생기는 식으로).
#
# ⚠️ bash 3.2다. 인덱스 배열은 되지만 `declare -A`·mapfile 은 안 된다.
#    또 set -u 에서 빈 배열의 "${arr[@]}" 는 unbound 로 죽으므로,
#    확장하기 전에 반드시 개수를 먼저 검사한다.

# ── 모듈 ─────────────────────────────────────────────────────────────────────
_init_modules() {
  local tree="$DT_PRESET/tree.json" list
  # ⚠️ label_en 이 있으면 그걸 쓴다. 없으면 label 로 떨어진다.
  local en; en=$([ "$(dt_lang)" = en ] && echo true || echo false)
  list=$(jq -r --argjson en "$en" '
    .modules | to_entries[] | select(.value.required != true)
    | .key + " — " + (if $en then (.value.label_en // .value.label) else .value.label end)
  ' "$tree")
  {
    echo
    printf '%s\n' "${C_BOLD}$(L "설치할 모듈" "Modules to install")${C_RESET}"
    dim "   $(L "devlog(개발일지)는 항상 설치됩니다. 나머지는 나중에 추가할 수 있습니다:" \
                "devlog is always installed. You can add the rest later:")"
    dim "     devtrail augment <module> --apply"
  } >&2
  local picked
  picked=$(_init_pick "   $(L "추가 모듈:" "Optional modules:")" "$list" "a")
  # "key — label" 에서 key 만 남긴다
  { printf 'devlog\n'; printf '%s' "$picked" | sed 's/ —.*//' | grep -v '^$'; } | sort -u
}

# ── AI 스킬 ──────────────────────────────────────────────────────────────────
# Claude Code 가 있을 때만. 없어도 DevTrail 은 그대로 동작한다.

# 어떤 레포의 docs/ 를 볼트로 가져올지. 비워두면 sync 는 매번 할 일 없이 끝난다.
_init_sync_repos() {
  local src="$1" found="" d
  {
    echo
    printf '%s\n' "${C_BOLD}5. $(L "docs 동기화 대상" "Repos to sync docs from")${C_RESET}"
    dim "   $(L "레포의 docs/ 폴더를 볼트로 가져옵니다. docs/ 가 있는 폴더만 보여줍니다." \
                "Pulls each repo's docs/ into the vault. Only repos that have one are listed.")"
  } >&2

  if [ -d "$src" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      d="${d#$src/}"; d="${d%/docs}"
      [ -n "$d" ] && found="$found$d
"
    done <<EOF
$(find "$src" -maxdepth 2 -type d -name docs 2>/dev/null | sort)
EOF
  fi

  if [ -z "$found" ]; then
    warn "$(L "docs/ 가 있는 레포를 찾지 못했습니다" "No repos with a docs/ folder"): $src" >&2
    dim "   $(L "나중에 설정의 sync.repos 에 직접 추가하세요." \
                "Add them to sync.repos in the config later.")" >&2
    return 0
  fi
  _init_pick "   $(L "찾은 레포:" "Found:")" "$found" "a"
}

# PR 요약이 들어갈 개발일지 섹션. 섹션이 없으면 summary 는 조용히 건너뛴다.

# PR 요약이 들어갈 개발일지 섹션. 섹션이 없으면 summary 는 조용히 건너뛴다.
_init_projects() {
  local gh_user="$1" found="" manual
  {
    echo
    printf '%s\n' "${C_BOLD}6. $(L "PR 요약 섹션" "PR summary sections")${C_RESET}"
    dim "   $(L "머지된 PR 요약은 개발일지의 '#### <레포명>' 섹션 아래에 들어갑니다." \
                "Merged-PR summaries go under the '#### <repo>' sections in your devlog.")"
    dim "   $(L "여기서 고른 레포로 그 섹션을 미리 만들어 둡니다." \
                "The repos you pick here become those sections.")"
    dim "   $(L "(섹션이 없으면 요약은 에러 없이 건너뛰기만 합니다)" \
                "(With no section the summary is skipped without an error)")"
  } >&2

  if [ -n "$gh_user" ] && has gh && gh auth status >/dev/null 2>&1; then
    found=$(gh repo list "$gh_user" --limit 50 --json name --jq '.[].name' 2>/dev/null | sort)
  fi

  if [ -z "$found" ]; then
    dim "   $(L "레포 목록을 가져오지 못했습니다. 쉼표로 직접 입력하세요" \
                "Could not list your repos. Type them comma-separated") (e.g. my-app,my-api)" >&2
    manual=$(_init_ask "$(L "레포명" "Repos")" "" 2>/dev/null)
    [ -n "$manual" ] || return 0
    printf '%s' "$manual" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
    return 0
  fi
  # 기본값을 두지 않는다 — Enter 한 번에 레포 50개가 전부 섹션이 되면 안 된다.
  _init_pick "   $(L "내 레포:" "Your repos:")" "$found" ""
}


_init_ai() {
  {
    echo
    printf '%s\n' "${C_BOLD}7. $(L "AI (PR 쉬운말 요약)" "AI (plain-language PR summaries)")${C_RESET}"
    dim "   $(L "claude 만 검증됐습니다. codex/gemini 는 어댑터 자리만 있습니다." \
                "Only claude is verified. codex/gemini are adapter stubs.")"
  } >&2
  local avail=()
  for c in claude codex gemini; do has "$c" && avail+=("$c"); done
  if [ ${#avail[@]} -gt 0 ]; then
    ok "$(L "감지된 CLI" "Detected"): ${avail[*]}" >&2
  else
    warn "$(L "AI CLI 가 없습니다 — 요약 기능은 비활성으로 둡니다" \
              "No AI CLI found — summaries stay off")" >&2
    printf 'none'; return
  fi
  _init_ask "$(L "사용할 provider (none=비활성)" "Provider (none = off)")" "${avail[0]}" 2>/dev/null
}

# ── write ────────────────────────────────────────────────────────────────────
# 개행 목록 → JSON 배열. 빈 입력은 [] 가 된다.
