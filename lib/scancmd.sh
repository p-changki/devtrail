#!/usr/bin/env bash
# DevTrail — `devtrail scan [VAULT]`
#
# 볼트를 진단한다. 쓰기는 하지 않는다.
#
# 이 명령이 나머지 전부의 전제다. 모드 제안 · 충돌 회피 · 자동이동 제외 목록 ·
# 허브 쿼리 선택이 모두 여기서 나온 값으로 결정된다.
#
#   devtrail scan               설정의 볼트를 진단
#   devtrail scan /path/vault   경로를 직접 지정 (init 전에도 쓸 수 있다)
#   devtrail scan --json        기계 판독용 원본
#
# ⚠️ 한글이 뒤따르는 변수는 반드시 중괄호로 감싼다: "${n}개"  (bash 3.2)

DT_SCAN_PY="${DEVTRAIL_ROOT}/lib/gen/scan.py"

scan_cmd() {
  require_bins python3 jq

  local as_json=0 vault=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) as_json=1 ;;
      -*)     die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *)      vault="$1" ;;
    esac
    shift
  done

  if [ -z "$vault" ]; then
    config_exists || die "$(L "볼트 경로를 알 수 없습니다." "No vault path.")
   $(L "devtrail scan /경로/볼트 처럼 직접 지정하거나 'devtrail init' 을 먼저 실행하세요." \
       "Pass one (devtrail scan /path/to/vault) or run 'devtrail init' first.")"
    vault="$(vault_path)"
  fi
  [ -d "$vault" ] || die "$(L "볼트 경로 없음" "Vault not found"): $vault"
  [ -f "$DT_SCAN_PY" ] || die "$(L "진단기 없음" "Scanner missing"): $DT_SCAN_PY"

  local out; out=$(mktemp); trap 'rm -f "$out"' RETURN
  python3 "$DT_SCAN_PY" "$vault" \
    "$DEVTRAIL_ROOT/preset/tree.json" \
    "$DEVTRAIL_ROOT/preset/obsidian/hotkeys.tmpl.json" > "$out" \
    || die "$(L "진단 실패" "Scan failed")"

  if jq -e '.error' "$out" >/dev/null 2>&1; then
    die "$(jq -r '.error' "$out")"
  fi

  if [ "$as_json" = 1 ]; then cat "$out"; return 0; fi
  _scan_render "$out"
}

_scan_render() {
  local j="$1"
  local notes fm_pct
  notes=$(jq -r '.scale.notes' "$j")
  fm_pct=$(jq -r '.scale.frontmatter_pct' "$j")

  _d_section "$(L "볼트" "Vault")"
  info "  $(L "경로 " "path ")   $(jq -r '.vault' "$j")"
  info "  $(L "노트 " "notes")   ${notes} · $(L "폴더" "folders") $(jq -r '.scale.folders' "$j")"
  info "  $(L "메타 " "meta ")   frontmatter ${fm_pct}%"

  _scan_fields "$j"
  _scan_tags "$j"
  _scan_roles "$j"
  _scan_obsidian "$j"
  _scan_mode "$j" "$notes"
}

# 필드 커버리지 — 허브 쿼리의 종류를 결정하는 값이다.
_scan_fields() {
  local j="$1"
  _d_section "$(L "메타데이터 커버리지" "Metadata coverage")"
  dim "   $(L "'키만 있는 것'과 '값까지 있는 것'을 구분합니다 — 쿼리는 값이 있어야 동작합니다." \
            "Keys and values are counted separately — a query only works when there is a value.")"
  jq -r '
    .fields | to_entries[] | select(.value.with_key > 0)
    | "  \(.key)\t\(.value.with_key)\t\(.value.key_pct)\t\(.value.with_value)\t\(.value.value_pct)"
  ' "$j" | while IFS=$'\t' read -r k wk kp wv vp; do
    local mark="  "
    # 값 커버리지로 쿼리 등급이 갈린다 (명세: 50% 정식 / 10~50% 병용 / 미만 폴백)
    if   awk "BEGIN{exit !($vp >= 50)}"; then mark="✅"
    elif awk "BEGIN{exit !($vp >= 10)}"; then mark="⚠️ "
    else mark="❌"; fi
    printf '  %s %-12s %s %4s (%4s%%)   %s %4s (%4s%%)\n' \
      "$mark" "$k" "$(L "키" "key  ")" "$wk" "$kp" "$(L "값" "value")" "$wv" "$vp"
  done

  local custom; custom=$(jq -r '[.custom_fields[] | .[0]] | join(" · ")' "$j")
  [ -n "$custom" ] && [ "$custom" != "" ] && dim "   $(L "그 밖의 필드" "Other fields"): $custom"
}

_scan_tags() {
  local j="$1" total tpct
  total=$(jq -r '.tags.total_uses' "$j")
  tpct=$(jq -r '.tags.type_pct' "$j")
  _d_section "$(L "태그" "Tags")"
  if [ "$total" = "0" ]; then
    warn "$(L "태그를 쓰지 않는 볼트입니다 — 자동 라우팅이 동작하지 않습니다" \
            "This vault has no tags — auto-filing will not work")"
    dim "   $(L "'devtrail adopt' 로 폴더 매핑만 쓰거나, 'devtrail align' 으로 태그를 채웁니다." \
            "Use folder mapping only ('devtrail adopt'), or backfill tags ('devtrail align').")"
    return
  fi
  info "  $(L "총 ${total}회 사용" "${total} uses") · #type/* ${tpct}%"
  jq -r '.tags.top[0:8][] | "     \(.[1])회  #\(.[0])"' "$j"
  if awk "BEGIN{exit !($tpct < 30)}"; then
    warn "  $(L "#type/* 사용률이 낮아 태그 기반 집계가 대부분 빈 결과가 됩니다" \
              "#type/* is rare here, so tag queries will mostly come back empty")"
    dim "   $(L "scan 이 뽑은 상위 태그를 우리 type 에 매핑하면 노트를 고치지 않고 쓸 수 있습니다." \
            "Map your top tags onto our types and it works without editing notes.")"
  fi
}

_scan_roles() {
  local j="$1" n
  n=$(jq -r '[.folders[] | select(.role_candidates | length > 0)] | length' "$j")
  _d_section "$(L "폴더 역할 추론" "Inferred folder roles")"
  if [ "$n" = "0" ]; then
    dim "   $(L "역할로 보이는 폴더를 찾지 못했습니다 (빈 볼트이거나 구조가 다릅니다)" \
            "No folder looks like a role (empty vault, or a different structure)")"
    return
  fi
  dim "   $(L "폴더 '이름'이 아니라 내용의 형태로 추론합니다. 확정은 사용자가 합니다." \
            "Inferred from what folders contain, not their names. You decide.")"
  jq -r '
    .folders[] | select(.role_candidates | length > 0)
    | . as $f | (.role_candidates | to_entries[])
    | "  \(.key)\t\(.value)\t\($f.notes)\t\($f.path)"
  ' "$j" | sort -t$'\t' -k2 -rn | head -8 | while IFS=$'\t' read -r role conf cnt path; do
    printf '  %-9s %s %-5s %4s  %s\n' \
      "$role" "$(L "확신" "conf")" "$conf" "$cnt" "$path"
  done
}

_scan_obsidian() {
  local j="$1"
  _d_section "Obsidian"
  if [ "$(jq -r '.obsidian.present' "$j")" != "true" ]; then
    warn "$(L "Obsidian 설정 폴더(.obsidian)가 없습니다" "No .obsidian folder")"
    dim "   $(L "볼트를 Obsidian 에서 한 번 열어야 플러그인 설정을 병합할 수 있습니다." \
            "Open the vault in Obsidian once before we can merge plugin settings.")"
    return
  fi

  local miss rec coremiss
  miss=$(jq -r '.obsidian.plugins.required_missing | join(" ")' "$j")
  rec=$(jq -r '.obsidian.plugins.recommended_missing | join(" ")' "$j")
  coremiss=$(jq -r '.obsidian.plugins.core_missing | join(" ")' "$j")

  [ -n "$miss" ] && fail "$(L "필수 플러그인 누락" "Required plugins missing"): $miss" || ok "$(L "필수 플러그인" "Required plugins") 4/4"
  [ -n "$coremiss" ] && warn "$(L "코어 플러그인 꺼짐" "Core plugins off"): $coremiss"
  [ -n "$rec" ] && dim "   $(L "권장 미설치" "Recommended, not installed"): $rec"
  [ "$(jq -r '.obsidian.plugins.zk_prefixer_on' "$j")" = "true" ] \
    && warn "$(L "zk-prefixer 가 켜져 있습니다 — Zettel ID 가 이중으로 붙습니다" \
            "zk-prefixer is on — Zettel IDs will be doubled")"

  local hk fold anm trig
  hk=$(jq -r '.obsidian.conflicts.hotkeys | length' "$j")
  fold=$(jq -r '.obsidian.conflicts.folders | length' "$j")
  anm=$(jq -r '.obsidian.conflicts.auto_note_mover_rules' "$j")
  trig=$(jq -r '.obsidian.conflicts.auto_note_mover_trigger // "없음"' "$j")

  [ "$hk" != "0" ] && {
    warn "$(L "단축키 ${hk}개가 이미 쓰이는 중 — 빈 키로 재배정합니다" \
            "${hk} hotkeys are taken — we will reassign to free keys")"
    jq -r '.obsidian.conflicts.hotkeys[0:4][] | "       \(.combo) ← \(.taken_by)"' "$j"
  }
  [ "$fold" != "0" ] && warn "$(L "만들려는 폴더 ${fold}개가 이미 존재합니다 (기존 것을 그대로 씁니다)" \
            "${fold} folders already exist — we will use them as-is")"
  [ "$anm" != "0" ] && {
    warn "$(L "Auto Note Mover 규칙이 이미 ${anm}개 있습니다" \
            "Auto Note Mover already has ${anm} rules") ($(L "트리거" "trigger"): ${trig})"
    [ "$trig" = "Automatic" ] && \
      dim "   $(L "⚠️ 자동 이동이 켜져 있습니다. 기존 모드는 Manual 로 시작해 기존 노트를 지킵니다." \
            "⚠️ Auto-move is on. Existing mode starts on Manual to protect your notes.")"
  }
  [ "$(jq -r '.obsidian.conflicts.linter_present' "$j")" = "true" ] && \
    dim "   $(L "Linter 설정이 있습니다 — 기존 모드에서는 건드리지 않습니다(저장 시 서식이 바뀌지 않게)" \
            "You have Linter settings — existing mode leaves them alone, so saving does not reformat")"
  [ "$(jq -r '.obsidian.conflicts.always_update_links' "$j")" != "true" ] && \
    warn "$(L "alwaysUpdateLinks 가 꺼져 있습니다 — 노트를 옮기면 링크가 끊깁니다" \
            "alwaysUpdateLinks is off — moving a note will break its links")"

  local rag
  rag=$(jq -r '.obsidian.rag.smart_connections' "$j")
  if [ "$rag" = "true" ]; then
    ok "$(L "RAG (Smart Connections) 사용 중 · 인덱스" "RAG (Smart Connections) in use · index") $(jq -r '(.obsidian.rag.index_bytes/1048576|floor)' "$j")MB"
    [ "$(jq -r '.obsidian.rag.excluded_configured' "$j")" != "true" ] && \
      dim "   $(L "제외 폴더가 설정되지 않았습니다 — 자동 수집물이 인덱스를 오염시킵니다" \
            "No exclusions configured — auto-collected notes will pollute the index")"
  else
    dim "   $(L "RAG 미사용 (선택 기능)" "RAG not in use (optional)")"
  fi
}

# 진단 결과로 모드를 제안한다. 결정은 사용자가 한다.
_scan_mode() {
  local j="$1" notes="$2" has_dot
  has_dot=$(jq -r '.obsidian.present' "$j")

  _d_section "$(L "제안" "Suggestion")"
  if [ "$notes" -lt 10 ] && [ "$has_dot" != "true" ]; then
    ok "$(L "새로 시작하기 — 빈 볼트입니다" "Start fresh — this vault is empty")"
    dim "   $(L "전체 구조를 만들고 설정을 전부 적용합니다." \
            "Creates the whole structure and applies every setting.")"
  elif [ "$notes" -lt 10 ]; then
    ok "$(L "새로 시작하기 — 노트가 거의 없습니다" "Start fresh — almost no notes here")"
  else
    ok "$(L "기존 볼트에 얹기 — 노트 ${notes}개가 있습니다" \
          "Add to your existing vault — ${notes} notes found")"
    dim "   $(L "기존 폴더를 그대로 쓰고 설정만 매핑합니다. 노트를 움직이지 않습니다." \
            "Uses your folders as-is and only maps settings. Notes are not moved.")"
    dim "   $(L "더 안전하게 하려면 '분리 설치' — 새 하위 트리에만 넣고, 지울 땐 폴더째 지웁니다." \
            "Safer still: isolated install — a new subtree only, removed by deleting the folder.")"
  fi
  echo
  dim "   $(L "적용" "Apply"): devtrail init   $(L "(이 진단 결과로 기본값을 제안합니다)" \
                                                    "(defaults come from this scan)")"
}
