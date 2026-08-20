#!/usr/bin/env bash
# DevTrail — init: 볼트를 읽어 기본값을 정한다.
#
# 탐지하되 묻는다 — 탐지는 기본값을 제안하는 데 쓰고 결정은 사용자가 한다.
# 기존 볼트가 있어도 '새로 시작'을 원하는 사람이 있다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── 진단 ─────────────────────────────────────────────────────────────────────
# scan 을 한 번 돌려 캐시한다. 모드 제안 · 루트명 기본값 · 충돌 안내가 이걸 쓴다.
_init_scan() {
  local vault="$1"
  DT_SCAN=$(mktemp); export DT_SCAN
  echo
  printf '%s\n' "${C_BOLD}볼트 진단${C_RESET}"
  if ! python3 "$DEVTRAIL_ROOT/lib/gen/scan.py" "$vault" \
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
