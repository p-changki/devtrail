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

  # ⚠️ 검증은 서브셸 밖에서 한다.
  #    $(...) 안에서 die 를 부르면 서브셸만 죽고 부모는 계속 간다.
  #    에러 메시지가 모듈 이름으로 흘러들어가 "대상 모듈: ❌ 알 수 없는..." 이
  #    출력되고 종료코드는 0 이었다.
  _aug_check_modules "$want" || return 1

  # 대상 모듈 결정: 인자 > 설정 > 기본(default=false 인 것 제외)
  local modules
  modules=$(_aug_modules "$want")
  [ -n "$modules" ] || die "설치할 모듈이 없습니다.  목록: devtrail augment --list"

  # 실제로 쓸 때만 저널을 연다. dry-run 은 아무것도 안 바꾼다.
  [ "$apply" = 1 ] && jr_begin augment

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
      [ "$apply" = 1 ] && jr_mkdir "$abs"
    fi
    if [ "$hub" = "true" ]; then
      _aug_hub "$key" "$rel" "$abs" "$apply" && hubs=$((hubs + 1))
    fi
  done <<EOF
$(_aug_folders "$modules")
EOF

  [ "$apply" = 1 ] && _aug_paths_note
  [ "$apply" = 1 ] && _aug_l1_hubs
  [ "$apply" = 1 ] && _aug_guides
  [ "$apply" = 1 ] && printf '%s\n' "$modules" | grep -qx learn && _aug_learn

  echo
  if [ "$apply" = 1 ]; then
    ok "폴더 ${made}개 생성 · ${kept}개 유지 · 허브 ${hubs}개"
    jr_end
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

# 모듈 이름이 실재하는지 확인한다. 여기서만 die 를 부른다.
_aug_check_modules() {
  local want="$1" m
  [ -n "$(printf '%s' "$want" | tr -d ' ')" ] || return 0
  for m in $want; do
    jq -e --arg m "$m" '.modules[$m]' "$DT_TREE" >/dev/null 2>&1 \
      || die "알 수 없는 모듈: $m  (목록: devtrail augment --list)"
  done
  return 0
}

# 설치할 모듈 목록. 우선순위:
#   1) 인자        devtrail augment pkm
#   2) 설정        install.modules  — init 에서 사용자가 고른 것
#   3) tree.json   기본 켬
#
# ⚠️ 2) 를 빼먹으면 사용자가 init 에서 거절한 모듈이 되살아난다.
#    init 은 install.modules 를 저장하는데 여기서 읽지 않아 실제로 그랬다.
#
# 이 함수는 조회만 한다 — 서브셸에서 불리므로 여기서 죽어도 소용이 없다.
_aug_modules() {
  local want="$1" m chosen
  if [ -n "$(printf '%s' "$want" | tr -d ' ')" ]; then
    for m in $want; do printf '%s\n' "$m"; done
    return 0
  fi

  if config_exists; then
    chosen=$(jq -r '(.install.modules // []) | .[]' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$chosen" ]; then printf '%s\n' "$chosen"; return 0; fi
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
  jr_mkdir "$tdir"
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
  jr_created "$out"
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

# ── 학습 시스템 골격 ─────────────────────────────────────────────────────────
#
# 내용이 아니라 운영 체계를 배포한다 — PROGRESS(진도) · SUBJECTS(순서) ·
# WEEKLY-REVIEW(회고) · milestone(스스로 시험).
# 커리큘럼은 사람마다 달라서 빈 골격만 준다. 76일을 실제로 굴려본 구조다.
_aug_learn() {
  local src="$DEVTRAIL_ROOT/preset/learn"
  local dest; dest="$(vault_root)/$(dt_dir study)"
  [ -d "$src" ] || return 0
  mkdir -p "$dest"

  local rel; rel=$(vault_rel "$(dt_dir study)")
  local n=0 f name
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    [ -f "$dest/$name" ] && continue
    # {{PATH}} 는 Dataview FROM 에 들어간다 — 경로를 박지 않기 위한 치환이다.
    sed "s|{{PATH}}|$rel|g" "$f" > "$dest/$name" && n=$((n + 1))
  done
  [ "$n" -gt 0 ] && ok "학습 골격 ${n}개  $(dt_dir study)/"
  return 0
}

# ── 입문 가이드 ──────────────────────────────────────────────────────────────
# 없을 때만 복사한다. 사용자가 고친 가이드를 덮어쓰지 않는다.
_aug_guides() {
  local src="$DEVTRAIL_ROOT/preset/guides"
  local dest; dest="$(vault_root)/$(dt_dir guides)"
  [ -d "$src" ] || return 0
  jr_mkdir "$dest"
  local n=0 f
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    [ -f "$dest/$(basename "$f")" ] && continue
    cp "$f" "$dest/" && { jr_created "$dest/$(basename "$f")"; n=$((n + 1)); }
  done
  [ "$n" -gt 0 ] && ok "가이드 ${n}개  $(dt_dir guides)/"
  return 0
}

# ── L1 대시보드 · 일일 체크인 ────────────────────────────────────────────────
# 볼트 루트에 둔다. 없을 때만 만든다.
_aug_l1_hubs() {
  local out; out=$(mktemp)
  local paths; paths=$(mktemp)
  . "$DEVTRAIL_ROOT/lib/pathcmd.sh"
  path_cmd --json 2>/dev/null | jq '{paths: (. | with_entries(.value = .value.rel))}' > "$paths" 2>/dev/null \
    || { rm -f "$paths" "$out"; return 0; }

  DT_DATE="$(date +%Y-%m-%d)" \
  python3 "$DEVTRAIL_ROOT/lib/gen/hubs.py" "$paths" "$CONFIG_FILE" \
    "${DT_SCAN_CACHE:-/dev/null}" "$(vault_root)" > "$out" 2>/dev/null || {
      rm -f "$paths" "$out"; warn "L1 허브 생성 실패"; return 0; }

  # grep -c 는 매치가 없으면 exit 1 이라 || echo 0 이 두 값을 이어붙인다.
  # wc 로 세고 공백을 떼는 편이 안전하다.
  local n; n=$(grep -c . "$out" 2>/dev/null | head -1 | tr -d ' ')
  [ -n "$n" ] || n=0
  if [ "$n" -gt 0 ] 2>/dev/null; then
    ok "L1 허브 ${n}개  $(tr '\n' ' ' < "$out")"
    # 되돌릴 수 있게 기록한다. hubs.py 는 파일명만 낼 수도 있어 루트를 붙인다.
    local line
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in /*) jr_created "$line" ;; *) jr_created "$(vault_root)/$line" ;; esac
    done < "$out"
  fi
  rm -f "$paths" "$out"
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
    python3 "$DEVTRAIL_ROOT/lib/gen/hub.py" > "$hub" || {
      rm -f "$hub"; warn "허브 생성 실패: $rel"; return 1; }
  jr_created "$hub"
  return 0
}

# 필드의 '값' 커버리지(%)를 낸다. scan 결과를 캐시해 재사용한다.
_aug_cov() {
  local field="$1"
  if [ -z "${DT_SCAN_CACHE:-}" ]; then
    DT_SCAN_CACHE=$(mktemp)
    python3 "$DEVTRAIL_ROOT/lib/gen/scan.py" "$(vault_path)" >"$DT_SCAN_CACHE" 2>/dev/null || echo '{}' >"$DT_SCAN_CACHE"
    export DT_SCAN_CACHE
  fi
  jq -r --arg f "$field" '(.fields[$f].value_pct // 0)' "$DT_SCAN_CACHE" 2>/dev/null || echo 0
}
