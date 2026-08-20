#!/usr/bin/env bash
# DevTrail — `devtrail init`
# 대화형 셋업. 기존 파일을 덮어쓰지 않는다(항상 .bak 후 진행).

init_run() {
  printf '%s\n' "${C_BOLD}DevTrail 셋업${C_RESET}"
  dim "언제든 Ctrl+C로 중단할 수 있습니다. 기존 파일은 덮어쓰지 않습니다."
  echo

  require_bins jq

  if config_exists; then
    warn "설정이 이미 있습니다: $CONFIG_FILE"
    confirm "다시 설정할까요? (기존 설정은 .bak으로 백업)" || { info "취소했습니다."; return 0; }
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)" \
      || die "설정 백업 실패 — 중단합니다: $CONFIG_FILE"
  fi

  mkdir -p "$DEVTRAIL_HOME"/{scripts,logs}

  local backend vault root gh_user ai_provider
  backend=$(_init_backend)
  vault=$(_init_vault "$backend")

  # 볼트를 알아낸 직후 진단한다. 이후의 기본값이 전부 여기서 나온다.
  _init_scan "$vault"
  DT_MODE=$(_init_mode); export DT_MODE

  root=$(_init_root "$vault")
  DT_DIRS=$(_init_adopt "$root"); export DT_DIRS
  DT_MODULES=$(_init_modules); export DT_MODULES
  gh_user=$(_init_github)
  DT_SRC_ROOT=$(_init_src_root); export DT_SRC_ROOT
  DT_SYNC_REPOS=$(_init_sync_repos "$DT_SRC_ROOT"); export DT_SYNC_REPOS
  DT_PROJECTS=$(_init_projects "$gh_user"); export DT_PROJECTS
  ai_provider=$(_init_ai)

  _init_write_config "$backend" "$vault" "$root" "$gh_user" "$ai_provider"
  _init_render_scripts
  _init_scaffold
  _init_next_steps "$vault"
}

# ── 진단 ─────────────────────────────────────────────────────────────────────
# scan 을 한 번 돌려 캐시한다. 모드 제안 · 루트명 기본값 · 충돌 안내가 이걸 쓴다.
_init_scan() {
  local vault="$1"
  DT_SCAN=$(mktemp); export DT_SCAN
  echo
  printf '%s\n' "${C_BOLD}볼트 진단${C_RESET}"
  if ! python3 "$DEVTRAIL_ROOT/lib/scan.py" "$vault" \
        "$DEVTRAIL_ROOT/preset/tree.json" \
        "$DEVTRAIL_ROOT/preset/obsidian/hotkeys.tmpl.json" > "$DT_SCAN" 2>/dev/null; then
    warn "진단에 실패했습니다 — 빈 볼트로 간주합니다"
    echo '{}' > "$DT_SCAN"
    return 0
  fi
  local n fm
  n=$(jq -r '.scale.notes // 0' "$DT_SCAN")
  fm=$(jq -r '.scale.frontmatter_pct // 0' "$DT_SCAN")
  ok "노트 ${n}개 · frontmatter ${fm}%"
  local roles
  roles=$(jq -r '[.folders[]? | select(.role_candidates|length>0)] | length' "$DT_SCAN")
  [ "${roles:-0}" != "0" ] && dim "   역할로 보이는 폴더 ${roles}개를 찾았습니다 (자세히: devtrail scan)"
}

_dt_scan_notes() { jq -r '.scale.notes // 0' "${DT_SCAN:-/dev/null}" 2>/dev/null || echo 0; }

# ── 모드 ─────────────────────────────────────────────────────────────────────
# 탐지 결과로 제안하되 결정은 사용자가 한다.
# 위험은 한 방향으로만 흐른다 — 노트가 많은데 '새로 시작'을 고르는 경우만 막는다.
_init_mode() {
  local n; n=$(_dt_scan_notes)
  local suggest=new
  [ "${n:-0}" -ge 10 ] && suggest=existing
  {
    echo
    printf '%s\n' "${C_BOLD}설치 방식${C_RESET}"
    if [ "$suggest" = existing ]; then
      dim "   노트 ${n}개가 있습니다. 기존 볼트로 보입니다."
    else
      dim "   빈 볼트로 보입니다."
    fi
    echo "   1) 기존 볼트에 얹기 — 기존 폴더를 그대로 쓰고 설정만 매핑 (노트를 움직이지 않음)"
    echo "   2) 새로 시작하기   — 전체 구조를 만들고 설정을 전부 적용"
    echo "   3) 분리 설치       — 기존은 그대로 두고 새 하위 트리에만 설치"
  } >&2
  local pick def=1
  [ "$suggest" = new ] && def=2
  pick=$(_init_ask "선택" "$def" 2>/dev/null)
  case "$pick" in
    2)
      if [ "${n:-0}" -ge 10 ]; then
        {
          echo
          warn "노트 ${n}개가 있는 볼트입니다."
          dim "   '새로 시작'은 자동 이동을 켜고 Linter 설정을 덮어씁니다."
        } >&2
        confirm "   그래도 계속할까요?" >&2 || { printf 'existing'; return 0; }
      fi
      printf 'new' ;;
    3) printf 'isolated' ;;
    *) printf 'existing' ;;
  esac
}

_dt_profile() { printf '%s' "$DEVTRAIL_ROOT/preset/profiles/${DT_MODE:-existing}.json"; }

# ── 루트 폴더 ────────────────────────────────────────────────────────────────
# 기존 볼트면 가장 노트가 많은 최상위 폴더를 기본값으로 제안한다.
# 루트는 '감싸는 폴더'다 — 하위 폴더를 여럿 거느리고 직속 노트는 적은 것.
#
# ⚠️ 단순히 '노트가 가장 많은 최상위 폴더'로 제안하면 안 된다.
#    Daily/ 하나만 쓰는 볼트에서 Daily 를 루트로 제안했고,
#    그 결과 Daily/개발/개발일지 가 만들어졌다(역할 폴더를 루트로 오인).
_init_root() {
  local vault="$1" suggest=""
  if [ "${DT_MODE:-existing}" != new ]; then
    suggest=$(jq -r '
      [ .folders[]? | select(.path != "." and (.path | contains("/") | not))
        | {top: .path, direct: .notes} ] as $tops
      | [ .folders[]? | select(.path != ".")
          | {top: (.path | split("/")[0]), n: .notes} ]
        | group_by(.top) | map({top: .[0].top, total: (map(.n) | add)}) as $sums
      | [ $tops[] | . as $t | ($sums[] | select(.top == $t.top) | .total) as $tot
          | select($tot > $t.direct * 2)          # 하위가 직속보다 훨씬 많아야 감싸는 폴더다
          | {top: $t.top, total: $tot} ]
      | sort_by(-.total) | (.[0].top // empty)
    ' "${DT_SCAN:-/dev/null}" 2>/dev/null)
  fi
  [ -n "$suggest" ] || { [ "${DT_MODE:-existing}" = new ] && suggest="notes"; }

  {
    echo
    printf '%s\n' "${C_BOLD}루트 폴더${C_RESET}"
    dim "   볼트 안에서 DevTrail 이 관리할 최상위 폴더입니다."
    if [ -z "$suggest" ]; then
      dim "   감싸는 폴더를 찾지 못했습니다 — 비워두면 볼트 최상위에 바로 만듭니다."
    fi
    [ "${DT_MODE:-}" = isolated ] && dim "   분리 설치이므로 기존과 겹치지 않는 새 이름을 권합니다."
  } >&2
  if [ -n "$suggest" ]; then
    _init_ask "폴더명 (비우면 볼트 최상위)" "$suggest" 2>/dev/null
  else
    _init_ask "폴더명 (비우면 볼트 최상위)" "" 2>/dev/null
  fi
}

# ── 역할 매핑 (adopt) ────────────────────────────────────────────────────────
# 탐지된 폴더를 우리 key 에 붙인다. 이것이 「얹기」의 실체다 —
# 노트를 옮기지 않고 config.dirs 만 바꿔 자동화가 사용자 구조 위에서 돌게 한다.
# 매핑이 없으면 augment 가 우리 트리를 새로 만들어 평행 구조가 생긴다.
_init_adopt() {
  local root="$1" pairs=""
  [ "${DT_MODE:-existing}" = new ] && { printf '{}'; return 0; }
  [ -s "${DT_SCAN:-/dev/null}" ] || { printf '{}'; return 0; }

  # 역할별 최상위 후보 하나씩. 루트 폴더 밑이면 상대경로로 줄인다.
  local cands
  cands=$(jq -r --arg root "$root" '
    [ .folders[]? | . as $f | (.role_candidates // {} | to_entries[])
      | {role: .key, score: .value, path: $f.path, notes: $f.notes} ]
    | group_by(.role) | map(max_by(.score))
    | .[] | [.role, .path, (.notes|tostring), (.score|tostring)] | @tsv
  ' "$DT_SCAN" 2>/dev/null)
  [ -n "$cands" ] || { printf '{}'; return 0; }

  {
    echo
    printf '%s\n' "${C_BOLD}기존 폴더 매핑${C_RESET}"
    dim "   찾은 폴더를 그대로 씁니다. 노트를 옮기지 않습니다."
    dim "   아니라고 하면 우리 기본 폴더를 새로 만듭니다."
  } >&2

  local role path notes score rel ans
  while IFS=$'\t' read -r role path notes score; do
    [ -n "$role" ] || continue
    # 루트 폴더 하위면 그 아래 상대경로로 바꾼다 (dirs 는 루트 기준이다)
    rel="$path"
    case "$path" in
      "$root"/*) rel="${path#"$root"/}" ;;
      "$root")   continue ;;
    esac
    printf '   %s → %s  (%s개, 확신 %s)\n' "$role" "$rel" "$notes" "$score" >&2
    ans=$(_init_ask "   이 폴더를 '$role' 로 쓸까요? [y/N]" "y" 2>/dev/null)
    case "$ans" in
      [Yy]*) pairs="$pairs$role\t$rel\n" ;;
    esac
  done <<EOF
$cands
EOF

  [ -n "$pairs" ] || { printf '{}'; return 0; }
  printf '%b' "$pairs" | jq -R -s '
    split("\n") | map(select(length>0) | split("\t"))
    | map({key: .[0], value: .[1]}) | from_entries'
}

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

# ── 스캐폴딩 ─────────────────────────────────────────────────────────────────
_init_scaffold() {
  echo
  printf '%s\n' "${C_BOLD}볼트 구조${C_RESET}"
  local mods; mods=$(printf '%s' "${DT_MODULES:-devlog}" | tr '\n' ' ')
  dim "   모듈: $mods"
  # augment 는 없는 것만 만든다. 기존 폴더는 그대로 둔다.
  . "$DEVTRAIL_ROOT/lib/augmentcmd.sh"
  # shellcheck disable=SC2086
  augment_cmd $mods --apply
}

# ── prompts ──────────────────────────────────────────────────────────────────
_init_ask() {
  local prompt="$1" default="${2-}" reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    printf '%s' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    printf '%s' "$reply"
  fi
}

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
_init_pick() {
  local title="$1" items="$2" default="${3-}" reply sel i
  [ -n "$items" ] || return 0

  local list=() out=() oldifs="$IFS"
  IFS=$'\n'
  for i in $items; do [ -n "$i" ] && list+=("$i"); done
  IFS="$oldifs"
  [ ${#list[@]} -gt 0 ] || return 0

  {
    printf '%s\n' "$title"
    i=0
    while [ $i -lt ${#list[@]} ]; do
      printf '   %2d) %s\n' $((i + 1)) "${list[$i]}"
      i=$((i + 1))
    done
    local hint="그냥 Enter=선택 안 함"
    [ "$default" = "a" ] && hint="그냥 Enter=전체"
    dim "   a=전체 · 개별 선택 예) 1,3 · $hint"
  } >&2

  reply=$(_init_ask "선택" "$default" 2>/dev/null)
  [ -n "$reply" ] || return 0

  case "$reply" in
    a|A) out=("${list[@]}") ;;
    *)
      IFS=','
      for sel in $reply; do
        IFS="$oldifs"
        sel="${sel// /}"
        case "$sel" in ''|*[!0-9]*) continue ;; esac
        [ "$sel" -ge 1 ] && [ "$sel" -le ${#list[@]} ] || continue
        out+=("${list[$((sel - 1))]}")
        IFS=','
      done
      IFS="$oldifs" ;;
  esac

  [ ${#out[@]} -gt 0 ] || return 0
  printf '%s\n' "${out[@]}"
}

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
_dt_json_array() {
  printf '%s' "${1-}" | jq -R -s 'split("\n") | map(select(length > 0))'
}

# 개행 목록 → { "이름": "이름", ... } 항등 매핑.
# project_groups 는 '레포명 → 개발일지 섹션명' 이다. 기본은 레포명 그대로 쓰고,
# fe/be 로 나뉜 레포를 한 섹션에 모으고 싶으면 나중에 값만 바꾸면 된다.
_dt_json_identity() {
  printf '%s' "${1-}" \
    | jq -R -s 'split("\n") | map(select(length > 0)) | map({key: ., value: .}) | from_entries'
}

_init_write_config() {
  local backend="$1" vault="$2" root="$3" gh_user="$4" ai="$5"
  local enabled=true; [ "$ai" = none ] && { enabled=false; ai=claude; }

  jq -n \
    --arg backend "$backend" --arg vault "$vault" --arg root "$root" \
    --arg gh "$gh_user" --arg ai "$ai" --argjson enabled "$enabled" \
    --argjson syncrepos "$(_dt_json_array "${DT_SYNC_REPOS:-}")" \
    --argjson projects "$(_dt_json_array "${DT_PROJECTS:-}")" \
    --argjson groups "$(_dt_json_identity "${DT_PROJECTS:-}")" \
    --arg mode "${DT_MODE:-existing}" \
    --argjson adopted "${DT_DIRS:-\{\}}" \
    --argjson modules "$(_dt_json_array "${DT_MODULES:-devlog}")" \
    --arg python "$(command -v python3 || echo /usr/bin/python3)" \
    --arg brew "$(brew --prefix 2>/dev/null || echo /opt/homebrew)" \
    --arg src "${DT_SRC_ROOT:-$HOME/Desktop}" \
    --arg backup "$DEVTRAIL_HOME/vault-backup" \
    -f /dev/stdin > "$CONFIG_FILE" <<'JQ'
{
  version: 1,
  install: { mode: $mode, modules: $modules },
  vault:   { backend: $backend, path: $vault, root: $root },
  dirs:    $adopted,
  naming:  { devlog_file: "{{DATE}} devlog.md", weekly_file: "{{ISOWEEK}} weekly.md",
             date_format: "%Y-%m-%d" },
  headings:{ issues_pr: "## Issues / PRs", worklog: "## Work log",
             morning: "### Morning", youtube: "## YouTube" },
  github:  { user: $gh, repos: $projects, project_groups: $groups },
  sync:    { source_root: $src, repos: $syncrepos, exclude: [
             "node_modules","dist","build",".next",".git",".DS_Store",
             "*.log","*.ts","*.tsx","*.js","*.jsx","*.mjs","*.py","*.pyc",
             "__pycache__","*.sh" ] },
  linear:  { enabled: false, keychain_service: "devtrail-linear-api-key" },
  ai:      { provider: $ai, summary_enabled: $enabled },
  backup:  { enabled: true, repo_path: $backup },
  schedule:{ daily_hour: 10, repodocs_interval_sec: 600 },
  bin:     { python: $python, brew_prefix: $brew }
}
JQ
  ok "설정 저장: $CONFIG_FILE"
}

# 템플릿의 {{VAR}}를 설정값으로 치환해 ~/.devtrail/scripts/ 에 생성한다.
_init_render_scripts() {
  local src="$DEVTRAIL_ROOT/templates/scripts" dst="$DEVTRAIL_HOME/scripts"
  [ -d "$src" ] || { warn "스크립트 템플릿 없음: $src"; return; }
  mkdir -p "$dst"

  local n=0
  for t in "$src"/*.sh.tmpl; do
    [ -e "$t" ] || continue
    local name; name=$(basename "$t" .tmpl)
    sed \
      -e "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" \
      -e "s|{{CONFIG_FILE}}|$CONFIG_FILE|g" \
      "$t" > "$dst/$name"
    chmod +x "$dst/$name"
    n=$((n+1))
  done
  ok "스크립트 생성: ${n}개 → $dst"
  dim "   설정값은 실행 시점에 $CONFIG_FILE 에서 읽습니다(하드코딩 없음)"
}

# Obsidian 설정은 여기서 건드리지 않는다.
#
# 예전에는 templates/obsidian/ 을 볼트의 .obsidian/ 으로 통째로 복사했다.
# 셋 다 틀렸다: 셸커맨드는 .obsidian/plugins/obsidian-shellcommands/data.json
# 에 있어야 하고, 노트 템플릿은 .obsidian/ 이 아니라 볼트 안 templates 폴더에
# 들어가야 하며, {{DEVTRAIL_HOME}} 치환도 하지 않아 플레이스홀더가 그대로
# 남았다. 게다가 '.obsidian 이 없을 때만' 돌았는데, .obsidian 이 없다는 건
# 볼트를 한 번도 안 열었다는 뜻이라 플러그인도 없는 상태였다.
#
# 그 일은 `devtrail obsidian` 이 제대로 한다(병합·치환·백업). 여기서는
# 그 명령을 부르기 위한 선행 조건만 안내한다.
_init_next_steps() {
  local vault="$1"
  echo
  ok "셋업 완료"
  echo
  printf '%s\n' "${C_BOLD}다음 단계${C_RESET}"
  info "  1) Obsidian에서 볼트를 엽니다: $vault"
  dim "     처음 열어야 .obsidian/ 폴더가 생깁니다."
  info "  2) 플러그인 4개를 설치·활성화하고 Obsidian을 재시작합니다"
  dim "     Shell commands · Templater · Dataview · Auto Note Mover"
  info "  3) devtrail obsidian             # 셸커맨드 병합 · 노트 템플릿 설치"
  dim "     2번을 마치기 전에 실행하면 셸커맨드 병합을 건너뜁니다."
  info "  4) devtrail doctor               # 진단 — 여기서 ❌가 없어야 합니다"
  info "  5) devtrail install-schedule     # 자동 실행 등록"
  if [ "${DT_MODE:-existing}" != new ]; then
    echo
    dim "   기존 볼트이므로 자동 이동은 수동(Manual)으로 시작합니다."
    dim "   무엇이 달라지는지 먼저 보려면: devtrail scan"
  fi
  echo
  dim "설정: $CONFIG_FILE"
  dim "스크립트: $DEVTRAIL_HOME/scripts/"
}
