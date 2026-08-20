#!/usr/bin/env bash
# DevTrail — `devtrail augment [모듈...]`
#
# 없는 것만 만든다. 있는 것은 건드리지 않는다(멱등).
# 빈 볼트에서 돌리면 전부 없으므로 전체 스캐폴딩이 된다 —
# 신규/기존을 분기하지 않고 같은 코드로 처리하는 이유다.
#
#   devtrail augment                 프로파일이 정한 모듈 전부
#   devtrail augment devlog pkm      모듈 지정
#   devtrail augment --apply         실제 생성 (기본은 dry-run)
#   devtrail augment --list          모듈 목록
#
# ⚠️ 기본이 dry-run 이다. 남의 볼트를 건드리는 도구의 기본은 "안 하는 것"이다.
# ⚠️ 한글이 뒤따르는 변수는 중괄호로 감싼다: "${n}개"  (bash 3.2)

DT_TREE="${DEVTRAIL_TREE:-$DEVTRAIL_ROOT/preset/tree.json}"

augment_cmd() {
  require_config
  require_bins jq python3
  [ -f "$DT_TREE" ] || die "트리 정의 없음: $DT_TREE"

  local apply=0 want=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      --list) _aug_list; return 0 ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) want="$want $1" ;;
    esac
    shift
  done

  local vroot; vroot="$(vault_root)"
  [ -d "$(vault_path)" ] || die "볼트 경로 없음: $(vault_path)"

  # 대상 모듈 결정: 인자 > 설정 > 기본(default=false 인 것 제외)
  local modules
  modules=$(_aug_modules "$want")
  [ -n "$modules" ] || die "설치할 모듈이 없습니다.  목록: devtrail augment --list"

  step "대상 모듈: $(printf '%s' "$modules" | tr '\n' ' ')"
  [ "$apply" = 1 ] || dim "   (dry-run — 실제로 만들려면 --apply)"
  echo

  local made=0 kept=0 hubs=0
  local rel abs key hub

  while IFS=$'\t' read -r key rel hub; do
    [ -n "$key" ] || continue
    abs="$vroot/$rel"
    if [ -d "$abs" ]; then
      kept=$((kept + 1))
      dim "   유지  $rel"
    else
      made=$((made + 1))
      ok "생성  $rel"
      [ "$apply" = 1 ] && mkdir -p "$abs"
    fi
    if [ "$hub" = "true" ]; then
      _aug_hub "$key" "$rel" "$abs" "$apply" && hubs=$((hubs + 1))
    fi
  done <<EOF
$(_aug_folders "$modules")
EOF

  [ "$apply" = 1 ] && _aug_paths_note

  echo
  if [ "$apply" = 1 ]; then
    ok "폴더 ${made}개 생성 · ${kept}개 유지 · 허브 ${hubs}개"
  else
    info "생성 예정 ${made}개 · 유지 ${kept}개 · 허브 ${hubs}개"
    dim "   적용: devtrail augment --apply"
  fi
}

_aug_list() {
  step "모듈"
  jq -r '.modules | to_entries[]
    | "  \(.key)\t\(.value.label)\t\(if .value.required then "필수" elif .value.default == false then "기본 꺼짐" else "기본 켬" end)"' \
    "$DT_TREE" | while IFS=$'\t' read -r k l d; do
    printf '  %-10s %-28s %s\n' "$k" "$l" "$d"
  done
}

# 설치할 모듈 목록. 인자가 없으면 required + 기본 켬.
_aug_modules() {
  local want="$1"
  if [ -n "$(printf '%s' "$want" | tr -d ' ')" ]; then
    local m
    for m in $want; do
      jq -e --arg m "$m" '.modules[$m]' "$DT_TREE" >/dev/null 2>&1 \
        || die "알 수 없는 모듈: $m  (목록: devtrail augment --list)"
      printf '%s\n' "$m"
    done
    return 0
  fi
  jq -r '.modules | to_entries[] | select(.value.default != false) | .key' "$DT_TREE"
}

# key<TAB>상대경로<TAB>hub여부 — 부모 경로를 이어붙인다.
#
# ⚠️ 경로는 반드시 config 의 dirs.<key> 를 먼저 본다.
#    tree.json 을 그대로 쓰면 「얹기」가 깨진다 — 사용자가 Daily/ 를 쓰는데도
#    개발/개발일지 를 새로 만들어 평행 구조를 만든다(실제로 그렇게 동작했다).
_aug_folders() {
  local modules="$1" key rel hub
  printf '%s\n' "$modules" | jq -R -s 'split("\n") | map(select(length>0))' \
    | jq -r --slurpfile t "$DT_TREE" '
      . as $mods
      | $t[0].folders[]
      | select(.module as $m | $mods | index($m))
      | . as $p
      | ([$p.key, $p.path, (($p.hub // false) | tostring)] | @tsv),
        (($p.children // [])[]
         | [.key, ($p.path + "/" + .path), ((.hub // false) | tostring)] | @tsv)
    ' | while IFS=$'\t' read -r key rel hub; do
        local mapped; mapped=$(cfg ".dirs[\"$key\"]" '')
        printf '%s\t%s\t%s\n' "$key" "${mapped:-$rel}" "$hub"
      done
}

# ── 경로 맵 노트 ─────────────────────────────────────────────────────────────
#
# Templater JS 는 셸을 부를 수 없다. 그래서 devtrail path 를 직접 못 쓴다.
# 대신 경로 맵을 볼트 안에 노트로 두고, 템플릿이 파일명으로 찾아 읽는다.
#
#   app.vault.getFiles().find(f => f.name === "_devtrail-paths.md")
#
# 이러면 템플릿에 경로 하드코딩이 0 이 된다. 사용자가 루트를 뭘로 정하든,
# 폴더를 어디로 옮기든 템플릿이 따라간다.
# (원본 볼트는 "창기/개발/개발메모/Frontend" 를 JS 안에 박아뒀고,
#  루트명을 바꾸면 템플릿 전체가 죽는 구조였다.)
_aug_paths_note() {
  local tdir; tdir="$(vault_root)/$(dt_dir templates)"
  mkdir -p "$tdir"
  local out="$tdir/_devtrail-paths.md"

  {
    printf -- '---\ntags:\n  - type/devtrail\ntype: devtrail-paths\nupdated: %s\n---\n\n' "$(date +%Y-%m-%d)"
    printf '# DevTrail 경로 맵\n\n'
    printf '> 자동 생성됩니다. 직접 고치지 마세요 — `devtrail augment --apply` 가 덮어씁니다.\n'
    printf '> 템플릿이 이 파일을 파일명으로 찾아 읽습니다.\n\n'
    printf '```json\n'
    _aug_paths_json
    printf '\n```\n'
  } > "$out"
  ok "경로 맵  $(dt_dir templates)/_devtrail-paths.md"
}

_aug_paths_json() {
  local keys k
  keys=$(jq -r '[ .folders[] | . as $p | $p.key, (($p.children // [])[] | .key) ] | .[]' "$DT_TREE")
  {
    printf '{\n  "root": %s,\n  "paths": {\n' "$(cfg '.vault.root' | jq -R .)"
    local first=1
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      [ "$first" = 1 ] || printf ',\n'
      first=0
      printf '    %s: %s' "$(printf '%s' "$k" | jq -R .)" \
                          "$(vault_rel "$(dt_dir "$k")" | jq -R .)"
    done <<EOF
$keys
EOF
    printf '\n  },\n'
    # 프로젝트 목록도 함께 내려보낸다. 템플릿이 선택창을 띄울 때 쓴다 —
    # 원본은 이 배열을 JS 안에 박아둬서 프로젝트가 늘 때마다 템플릿을 고쳐야 했다.
    printf '  "projects": %s,\n' \
      "$(jq -c '[(.github.project_groups // {}) | keys[]]' "$CONFIG_FILE" 2>/dev/null || echo '[]')"
    printf '  "categories": %s\n}' \
      "$(jq -c '[.folders[] | select(.key=="devnote") | (.children // [])[] | {key: (.key|split(".")[1]), path: .path, tag: .tag}]' "$DT_TREE")"
  }
}

# ── L3 폴더 허브 ─────────────────────────────────────────────────────────────
# 4블록을 만든다. 쿼리 종류는 볼트의 메타데이터 커버리지가 정한다:
#   값 커버리지 >= 50%  정식 (frontmatter 기반)
#             10~50%  병용
#              < 10%  폴백 (파일시스템 메타만) + "근사치" 표시
# 커버리지를 무시하고 정식 쿼리를 박으면 조용히 빈 결과가 나오고,
# 사용자는 그걸 "밀린 게 없다"로 읽는다.
_aug_hub() {
  local key="$1" rel="$2" abs="$3" apply="$4"
  local hub="$abs/_index.md"
  [ -f "$hub" ] && { dim "         허브 유지"; return 1; }

  ok "         허브 생성  $rel/_index.md"
  [ "$apply" = 1 ] || return 0

  mkdir -p "$abs"
  DT_HUB_KEY="$key" \
  DT_HUB_REL="$rel" \
  DT_HUB_FROM="$(vault_rel "$rel")" \
  DT_HUB_TITLE="$(basename "$rel")" \
  DT_HUB_COV_STATUS="$(_aug_cov status)" \
  DT_HUB_COV_REVIEW="$(_aug_cov review_at)" \
  DT_HUB_DATE="$(date +%Y-%m-%d)" \
    python3 "$DEVTRAIL_ROOT/lib/hub.py" > "$hub" || {
      rm -f "$hub"; warn "허브 생성 실패: $rel"; return 1; }
  return 0
}

# 필드의 '값' 커버리지(%)를 낸다. scan 결과를 캐시해 재사용한다.
_aug_cov() {
  local field="$1"
  if [ -z "${DT_SCAN_CACHE:-}" ]; then
    DT_SCAN_CACHE=$(mktemp)
    python3 "$DEVTRAIL_ROOT/lib/scan.py" "$(vault_path)" >"$DT_SCAN_CACHE" 2>/dev/null || echo '{}' >"$DT_SCAN_CACHE"
    export DT_SCAN_CACHE
  fi
  jq -r --arg f "$field" '(.fields[$f].value_pct // 0)' "$DT_SCAN_CACHE" 2>/dev/null || echo 0
}
