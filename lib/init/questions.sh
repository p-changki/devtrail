#!/usr/bin/env bash
# DevTrail — init: 셋업 질문들.
#
# 탐지 결과가 비면 질문을 건너뛴다 — 빈 볼트 사용자에게
# 기존 볼트용 매핑 질문을 던지면 짜증난다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)


_init_backend() {
  {
    echo
    printf '%s\n' "${C_BOLD}1. 저장소 위치${C_RESET}"
    echo "   1) 로컬        — 클라우드 동기화 없음. 권한 문제 없음"
    echo "   2) iCloud      — 맥 간 동기화. 전체 디스크 접근 권한 필요"
    echo "   3) Google Drive— 미검증(MVP). 스트리밍 모드 주의"
  } >&2
  local n
  n=$(_init_ask "선택" "1" 2>/dev/null)
  case "$n" in
    2) printf 'icloud' ;;
    3) printf 'gdrive' ;;
    *) printf 'local' ;;
  esac
}


_init_vault() {
  local backend="$1" suggest=""
  case "$backend" in
    icloud) suggest="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Obsidian Vault" ;;
    gdrive) suggest=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name 'GoogleDrive-*' 2>/dev/null | head -1) ;;
    *)      suggest="$HOME/DevTrailVault" ;;
  esac
  {
    echo
    printf '%s\n' "${C_BOLD}2. 볼트 경로${C_RESET}"
    dim "   Obsidian 볼트 폴더의 절대경로입니다. 없으면 만들어 드립니다."
  } >&2
  local p
  p=$(_init_ask "경로" "$suggest" 2>/dev/null)
  p="${p%/}"
  if [ ! -d "$p" ]; then
    if confirm "   폴더가 없습니다. 새로 만들까요? ($p)" >&2; then
      mkdir -p "$p" || die "폴더 생성 실패: $p"
    fi
  fi
  printf '%s' "$p"
}


_init_github() {
  {
    echo
    printf '%s\n' "${C_BOLD}3. GitHub${C_RESET}"
  } >&2
  local detected=""
  if has gh && gh auth status >/dev/null 2>&1; then
    detected=$(gh api user --jq .login 2>/dev/null)
    [ -n "$detected" ] && ok "gh 인증 감지: $detected" >&2
  else
    warn "gh 미인증 — 나중에 'gh auth login' 후 doctor를 다시 실행하세요" >&2
  fi
  _init_ask "GitHub 사용자명" "$detected" 2>/dev/null
}


_init_src_root() {
  {
    echo
    printf '%s\n' "${C_BOLD}4. 프로젝트 폴더${C_RESET}"
    dim "   레포들이 모여 있는 상위 폴더입니다. 각 레포의 docs/ 를 볼트로 가져옵니다."
    dim "   다음 단계에서 이 폴더 안의 레포를 골라 동기화 대상으로 지정합니다."
  } >&2
  _init_ask "경로" "$HOME/Desktop" 2>/dev/null
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
  local tree="$DEVTRAIL_ROOT/preset/tree.json" list
  list=$(jq -r '.modules | to_entries[] | select(.value.required != true) | .key + " — " + .value.label' "$tree")
  {
    echo
    printf '%s\n' "${C_BOLD}설치할 모듈${C_RESET}"
    dim "   devlog(개발일지)는 항상 설치됩니다. 나머지는 나중에 추가할 수 있습니다:"
    dim "     devtrail augment <모듈> --apply"
  } >&2
  local picked
  picked=$(_init_pick "   추가 모듈:" "$list" "a")
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
    printf '%s\n' "${C_BOLD}5. docs 동기화 대상${C_RESET}"
    dim "   레포의 docs/ 폴더를 볼트로 가져옵니다. docs/ 가 있는 폴더만 보여줍니다."
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
    warn "docs/ 가 있는 레포를 찾지 못했습니다: $src" >&2
    dim "   나중에 설정의 sync.repos 에 직접 추가하세요." >&2
    return 0
  fi
  _init_pick "   찾은 레포:" "$found" "a"
}

# PR 요약이 들어갈 개발일지 섹션. 섹션이 없으면 summary 는 조용히 건너뛴다.

# PR 요약이 들어갈 개발일지 섹션. 섹션이 없으면 summary 는 조용히 건너뛴다.
_init_projects() {
  local gh_user="$1" found="" manual
  {
    echo
    printf '%s\n' "${C_BOLD}6. PR 요약 섹션${C_RESET}"
    dim "   머지된 PR 요약은 개발일지의 '#### <레포명>' 섹션 아래에 들어갑니다."
    dim "   여기서 고른 레포로 그 섹션을 미리 만들어 둡니다."
    dim "   (섹션이 없으면 요약은 에러 없이 건너뛰기만 합니다)"
  } >&2

  if [ -n "$gh_user" ] && has gh && gh auth status >/dev/null 2>&1; then
    found=$(gh repo list "$gh_user" --limit 50 --json name --jq '.[].name' 2>/dev/null | sort)
  fi

  if [ -z "$found" ]; then
    dim "   레포 목록을 가져오지 못했습니다. 쉼표로 직접 입력하세요 (예: my-app,my-api)" >&2
    manual=$(_init_ask "레포명" "" 2>/dev/null)
    [ -n "$manual" ] || return 0
    printf '%s' "$manual" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
    return 0
  fi
  # 기본값을 두지 않는다 — Enter 한 번에 레포 50개가 전부 섹션이 되면 안 된다.
  _init_pick "   내 레포:" "$found" ""
}


_init_ai() {
  {
    echo
    printf '%s\n' "${C_BOLD}7. AI (PR 쉬운말 요약)${C_RESET}"
    dim "   MVP는 claude만 검증됐습니다. codex/gemini는 어댑터 자리만 있습니다."
  } >&2
  local avail=()
  for c in claude codex gemini; do has "$c" && avail+=("$c"); done
  if [ ${#avail[@]} -gt 0 ]; then
    ok "감지된 CLI: ${avail[*]}" >&2
  else
    warn "AI CLI가 없습니다 — 요약 기능은 비활성으로 둡니다" >&2
    printf 'none'; return
  fi
  _init_ask "사용할 provider (none=비활성)" "${avail[0]}" 2>/dev/null
}

# ── write ────────────────────────────────────────────────────────────────────
# 개행 목록 → JSON 배열. 빈 입력은 [] 가 된다.
