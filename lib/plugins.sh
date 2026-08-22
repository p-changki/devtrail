#!/usr/bin/env bash
# DevTrail — Obsidian 커뮤니티 플러그인 설치.
#
# 예전에는 사용자가 Obsidian 을 열고, 제한 모드를 끄고, 4개를 검색해서
# 설치하고, 재시작해야 했다. 커뮤니티 플러그인은 결국 폴더 하나다:
#
#   .obsidian/plugins/<id>/{main.js, manifest.json, styles.css}
#   .obsidian/community-plugins.json   ← 켜진 id 목록
#
# 그래서 우리가 받아 넣을 수 있다. 볼트를 처음 열기 '전에' 넣으면
# 재시작도 필요 없다 — 첫 실행부터 로드된다.
#
# ⚠️ 남의 코드를 받아 남의 볼트에 넣는 일이다. 규칙:
#     1. 버전을 고정한다 (preset/plugins.json). latest 를 쫓지 않는다.
#     2. 설치 전에 무엇을 어디서 받는지 화면에 띄우고 동의를 받는다.
#     3. 이미 있는 플러그인은 건드리지 않는다. 다운그레이드는 최악이다.
#     4. 받은 뒤 manifest 의 id 가 기대한 값인지 확인하고 옮긴다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

DT_PLUGINS_JSON="$DEVTRAIL_ROOT/preset/plugins.json"

# ── 조회 ─────────────────────────────────────────────────────────────────────
# id<TAB>name<TAB>repo<TAB>tag<TAB>files(공백구분)<TAB>required<TAB>why
_pl_rows() {
  local why; why=$([ "$(dt_lang)" = en ] && echo why_en || echo why_ko)
  jq -r --arg why "$why" '
    .plugins[] | [.id, .name, .repo, .tag, (.files | join(" ")),
                  (if .required then "1" else "0" end), .[$why]] | @tsv
  ' "$DT_PLUGINS_JSON"
}

pl_installed() { [ -f "$1/plugins/$2/main.js" ]; }

pl_enabled() {
  local f="$1/community-plugins.json"
  [ -f "$f" ] || return 1
  jq -e --arg p "$2" 'index($p)' "$f" >/dev/null 2>&1
}

# ── 화면 ─────────────────────────────────────────────────────────────────────
# 받아야 할 개수. 화면과 섞지 않는다 —
# ⚠️ 예전에는 _pl_consent_screen 이 화면도 그리고 개수도 stdout 으로 냈다.
#    $(...) 로 받으면 화면 전체가 숫자 자리에 들어와 "integer expression
#    expected" 로 죽었다. 한 함수는 하나만 낸다.
pl_todo_count() {
  local dot="$1" id rest n=0
  while IFS=$'\t' read -r id rest; do
    [ -n "$id" ] || continue
    pl_installed "$dot" "$id" || n=$((n + 1))
  done <<EOF
$(_pl_rows)
EOF
  printf '%s' "$n"
}

# 무엇을 어디서 받는지 반드시 보여준다. 사용자가 모르는 코드가 볼트에
# 들어가면 안 된다.
_pl_consent_screen() {
  local dot="$1"
  local id name repo tag files req why
  echo
  dim "   $(L "GitHub 릴리스에서 내려받아 볼트에 넣습니다. 버전은 고정돼 있습니다." \
            "Downloaded from GitHub releases into your vault. Versions are pinned.")"
  echo
  while IFS=$'\t' read -r id name repo tag files req why; do
    [ -n "$id" ] || continue
    if pl_installed "$dot" "$id"; then
      dim "   ✓ ${name} — $(L "이미 있음, 건드리지 않습니다" "already there, left alone")"
      continue
    fi
    printf '   ↓ %-16s %s\n' "$name" "${C_MUTED}github.com/${repo}@${tag}${C_RESET}"
    dim "     $why"
  done <<EOF
$(_pl_rows)
EOF
}

# ── 설치 ─────────────────────────────────────────────────────────────────────
# 하나를 받는다. 성공하면 0, 실패하면 1. 실패해도 다른 것은 계속 받는다.
_pl_fetch_one() {
  local dot="$1" id="$2" repo="$3" tag="$4" files="$5"
  local base="https://github.com/$repo/releases/download/$tag"
  local stage; stage=$(mktemp -d) || return 1
  local f
  for f in $files; do
    curl -fsSL --retry 2 --max-time 60 -o "$stage/$f" "$base/$f" || { rm -rf "$stage"; return 1; }
    [ -s "$stage/$f" ] || { rm -rf "$stage"; return 1; }
  done

  # 받은 것이 기대한 플러그인인지 확인한 뒤에 옮긴다.
  local got; got=$(jq -r '.id // ""' "$stage/manifest.json" 2>/dev/null)
  if [ "$got" != "$id" ]; then
    rm -rf "$stage"; return 1
  fi

  local dest="$dot/plugins/$id"
  jr_mkdir "$dest" || { rm -rf "$stage"; return 1; }
  for f in $files; do
    cp "$stage/$f" "$dest/$f" || { rm -rf "$stage"; return 1; }
    jr_created "$dest/$f"
  done
  rm -rf "$stage"
  return 0
}

# community-plugins.json 에 id 를 넣는다.
#
# ⚠️ 사용자가 이미 쓰던 목록을 덮어쓰면 그 사람의 플러그인이 전부 꺼진다.
#    반드시 '더하기'다.
_pl_enable() {
  local dot="$1" id="$2"
  local f="$dot/community-plugins.json"
  if [ ! -f "$f" ]; then
    printf '%s\n' '[]' > "$f" || return 1
    jr_created "$f"
  else
    pl_enabled "$dot" "$id" && return 0
    jr_backup "$f" >/dev/null || return 1
  fi
  local tmp; tmp=$(mktemp)
  jq --arg p "$id" '. + [$p] | unique' "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  return 0
}

# pl_install <.obsidian 경로> [--yes]
#
# 반환값: 필수 플러그인을 하나라도 못 넣었으면 1. 셋업을 멈추지는 않는다 —
# 나머지는 정상이고, 끝에 무엇이 빠졌는지 말해주는 편이 낫다.
pl_install() {
  local dot="$1" yes=0
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in --yes|-y) yes=1 ;; esac
    shift
  done

  require_bins jq curl
  [ -f "$DT_PLUGINS_JSON" ] || { warn "$(L "플러그인 목록 없음" "No plugin list"): $DT_PLUGINS_JSON"; return 1; }
  [ -d "$dot" ] || { warn "$(L "Obsidian 설정 폴더 없음" "No Obsidian config folder"): $dot"; return 1; }

  step "$(L "Obsidian 플러그인" "Obsidian plugins")"

  local todo; todo=$(pl_todo_count "$dot")
  _pl_consent_screen "$dot"
  if [ "${todo:-0}" -eq 0 ]; then
    echo
    ok "$(L "받을 것이 없습니다" "Nothing to download")"
  else
    echo
    if [ "$yes" != 1 ]; then
      confirm "   $(L "설치할까요?" "Install these?")" || {
        info "$(L "건너뜁니다. 나중에" "Skipped. Later"): devtrail plugins install"
        return 1
      }
    fi
  fi

  local id name repo tag files req why
  local failed_required=0 done_n=0
  while IFS=$'\t' read -r id name repo tag files req why; do
    [ -n "$id" ] || continue
    if ! pl_installed "$dot" "$id"; then
      if _pl_fetch_one "$dot" "$id" "$repo" "$tag" "$files"; then
        done_n=$((done_n + 1))
        ok "$name $tag"
      else
        if [ "$req" = 1 ]; then
          fail "$name — $(L "받지 못했습니다" "could not download")"
          failed_required=1
        else
          warn "$name — $(L "받지 못했습니다 (선택 항목)" "could not download (optional)")"
        fi
        continue
      fi
    fi
    _pl_enable "$dot" "$id" \
      || warn "$name — $(L "활성화 실패" "could not enable")"
  done <<EOF
$(_pl_rows)
EOF

  # ⚠️ Obsidian 은 시작할 때만 플러그인 폴더를 훑는다. 실행 중에 넣으면
  #    그 자리에서는 아무 일도 일어나지 않는다 — 말해주지 않으면 고장으로 본다.
  [ "$done_n" -gt 0 ] && { . "$DEVTRAIL_ROOT/lib/obsidian_app.sh"; oa_warn_if_running || true; }

  if [ "$failed_required" = 1 ]; then
    echo
    warn "$(L "필수 플러그인이 빠졌습니다. 네트워크를 확인하고 다시" \
            "A required plugin is missing. Check the network and retry"): devtrail plugins install"
    return 1
  fi
  return 0
}

# ── 목록 ─────────────────────────────────────────────────────────────────────
pl_status() {
  require_config
  local dot; dot="$(vault_path)/.obsidian"
  step "$(L "Obsidian 플러그인" "Obsidian plugins")"
  [ -d "$dot" ] || { warn "$(L "Obsidian 설정 폴더 없음" "No Obsidian config folder"): $dot"; return 1; }
  local id name repo tag files req why mark
  while IFS=$'\t' read -r id name repo tag files req why; do
    [ -n "$id" ] || continue
    if ! pl_installed "$dot" "$id"; then mark="❌ $(L "없음" "missing")"
    elif ! pl_enabled "$dot" "$id"; then mark="⚠️  $(L "설치됐지만 꺼짐" "installed but off")"
    else mark="✅ $(L "켜짐" "on")"
    fi
    printf '   %-18s %s\n' "$name" "$mark"
  done <<EOF
$(_pl_rows)
EOF
  return 0
}

plugins_cmd() {
  local sub="${1:-status}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    install) require_config; oa_ensure_dot "$(vault_path)" >/dev/null 2>&1 || true
             jr_begin plugins-install
             pl_install "$(vault_path)/.obsidian" "$@"; local rc=$?
             jr_end; return $rc ;;
    status|list) pl_status ;;
    *) die "$(L "알 수 없는 하위 명령" "Unknown subcommand"): $sub  (install|status)" ;;
  esac
}
