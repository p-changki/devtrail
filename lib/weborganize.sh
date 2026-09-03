#!/usr/bin/env bash
# DevTrail — 기존 웹 링크의 보수적 재분류.
# webcapture.sh가 URL 안전 검사·분류·인덱스·저널 함수를 준비한 뒤 불러온다.

_cap_web_fm_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_front = 1; next }
    in_front && $0 == "---" { exit }
    in_front && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

_cap_web_rewrite_classification() {
  local source="$1" target="$2" type="$3" tags="$4" area="$5" topic="$6" kind="$7" stage
  # DevTrail이 만든 JSON 한 줄 태그만 바꾼다. 사용자가 손으로 복잡하게 바꾼
  # YAML 태그 목록은 추측하지 않고 건너뛴다.
  grep -qE '^tags:[[:space:]]*\[' "$source" || return 2
  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-organize.XXXXXX") || return 1
  awk -v type="$type" -v tags="$tags" -v area="$area" -v topic="$topic" -v kind="$kind" '
    NR == 1 && $0 == "---" { in_front = 1; print; next }
    in_front && $0 == "---" {
      if (!seen_type) print "type: " type
      if (!seen_tags) print "tags: " tags
      if (!seen_area) print "area: " area
      if (!seen_topic) print "topic: " topic
      if (!seen_kind) print "source_kind: " kind
      print; in_front = 0; next
    }
    in_front && /^type:[[:space:]]*/ { print "type: " type; seen_type = 1; next }
    in_front && /^tags:[[:space:]]*/ { print "tags: " tags; seen_tags = 1; next }
    in_front && /^area:[[:space:]]*/ { print "area: " area; seen_area = 1; next }
    in_front && /^topic:[[:space:]]*/ { print "topic: " topic; seen_topic = 1; next }
    in_front && /^source_kind:[[:space:]]*/ { print "source_kind: " kind; seen_kind = 1; next }
    { print }
  ' "$source" > "$stage" || { rm -f "$stage"; return 1; }
  [ -s "$stage" ] || { rm -f "$stage"; return 1; }
  if [ "$source" = "$target" ]; then
    jr_backup "$source" >/dev/null || { rm -f "$stage"; return 1; }
    mv "$stage" "$source" || { rm -f "$stage"; return 1; }
  else
    jr_backup "$source" >/dev/null || { rm -f "$stage"; return 1; }
    jr_created "$target"
    mv "$stage" "$target" || { rm -f "$stage"; return 1; }
    rm -f "$source" || return 1
  fi
}

_cap_web_organize() {
  local apply="$1" root inbox_rel library_rel links_rel scan file url title description source area topic folder target_dir target changed=0 planned=0 skipped=0 scaffold=0 rc=0
  require_config; require_bins jq
  root=$(vault_root); inbox_rel=$(dt_dir inbox)
  [ -n "$inbox_rel" ] || die "$(L "자료실 Inbox 폴더가 설정에 없습니다" "The Library Inbox folder is not configured")"
  library_rel=${inbox_rel%/*}; [ "$library_rel" = "$inbox_rel" ] && library_rel=""
  links_rel="${library_rel:+$library_rel/}$(L '링크' 'Links')"
  scan="$root/$links_rel"
  [ -d "$scan" ] || { info "$(L "정리할 링크 자료실이 없습니다" "No link library to organize")"; return 0; }

  step "$(L "기존 링크 분류" "Organize saved links")"
  [ "$apply" = 1 ] && jr_begin capture-web-organize
  # 기존 자료실도 이 명령 한 번으로 분야별 탐색 표를 최신 형식으로 고친다.
  # 링크를 재분류하지 못해도 `_index` 표기가 남아 사용자를 헷갈리게 하면 안 된다.
  if [ "$apply" = 1 ]; then
    _cap_web_ensure_root_navigation "$scan/_index.md" "$(vault_rel "$links_rel")" || {
      jr_end; die "$(L "링크 자료실 허브를 갱신하지 못했습니다" "Could not update link library index")"
    }
    # ⚠️ 링크가 지나간 폴더의 표만 고치면 폴더마다 표가 다르게 보인다.
    #    사용자는 그것을 "안 바뀌었다"가 아니라 "고장났다"로 읽는다.
    #    허브의 library_level 이 어떤 표를 써야 하는지 이미 알고 있다.
    while IFS= read -r hub; do
      _cap_web_ensure_link_table "$hub" "$(_cap_web_fm_value "$hub" library_level)" || {
        jr_end; die "$(L "자료실 표를 갱신하지 못했습니다" "Could not update the library table")"
      }
    done < <(find "$scan" -type f -name '_index.md' | sort)
  fi
  while IFS= read -r file; do
    url=$(_cap_web_fm_value "$file" url)
    [ -n "$url" ] || continue
    area=$(_cap_web_fm_value "$file" area)
    topic=$(_cap_web_fm_value "$file" topic)
    # 사용자가 이미 고른 카테고리는 자동 변경하지 않는다.
    if [ -n "$area" ] && { [ "$area" != common ] || [ "$topic" != uncategorized ]; }; then continue; fi
    _cap_web_safe_url "$url" >/dev/null 2>&1 || { warn "$(L "URL 형식이 달라 건너뜀" "Skipping malformed URL"): $(basename "$file")"; skipped=$((skipped + 1)); continue; }
    source="$CAP_WEB_HOST"; title=$(_cap_web_fm_value "$file" title); description=$(_cap_web_fm_value "$file" description)
    _cap_web_classify "$url" "$source" "$title" "$description"
    # 분류는 다시 계산하지만 사용자가 붙인 프로젝트는 그대로 되돌려 놓는다.
    CAP_WEB_TAGS=$(_cap_web_merge_project_tags "$CAP_WEB_TAGS" "$(_cap_web_fm_projects "$file")")
    # 근거 없는 추측은 하지 않는다.
    [ "$CAP_WEB_AREA/$CAP_WEB_TOPIC" != common/uncategorized ] || continue
    folder=$(cap_taxonomy_folder "$CAP_WEB_AREA" "$CAP_WEB_TOPIC")
    target_dir="$scan/$folder"; target="$target_dir/$(basename "$file")"
    if [ "$file" != "$target" ] && [ -e "$target" ]; then
      warn "$(L "같은 이름의 링크가 있어 건너뜀" "Skipping name collision"): $(basename "$file")"; skipped=$((skipped + 1)); continue
    fi
    planned=$((planned + 1)); info "  $(L "분류" "Classify"): $(basename "$file") → $CAP_WEB_AREA / $CAP_WEB_TOPIC"
    [ "$apply" = 1 ] || continue
    jr_mkdir "$target_dir" || { jr_end; die "$(L "분류 폴더를 만들지 못했습니다" "Could not create a category folder")"; }
    _cap_web_rewrite_classification "$file" "$target" "$CAP_WEB_TYPE" "$CAP_WEB_TAGS" "$CAP_WEB_AREA" "$CAP_WEB_TOPIC" "$CAP_WEB_SOURCE_KIND" || {
      rc=$?; [ "$rc" -eq 2 ] && warn "$(L "사용자 태그 형식이라 건너뜀" "Skipping custom tag format"): $(basename "$file")" || { jr_end; die "$(L "링크 분류를 저장하지 못했습니다" "Could not save link classification")"; }
      skipped=$((skipped + 1)); continue
    }
    _cap_web_write_index "$scan" "$links_rel" root "$(L '링크 자료실' 'Link library')" || { jr_end; die "$(L "링크 자료실 허브를 만들지 못했습니다" "Could not create link library index")"; }
    _cap_web_ensure_root_navigation "$scan/_index.md" "$(vault_rel "$links_rel")" || { jr_end; die "$(L "링크 자료실 허브를 보완하지 못했습니다" "Could not update link library index")"; }
    _cap_web_write_index "$scan/${folder%%/*}" "$links_rel/${folder%%/*}" area "${folder%%/*}" "$CAP_WEB_AREA" || { jr_end; die "$(L "분야 허브를 만들지 못했습니다" "Could not create area index")"; }
    _cap_web_ensure_link_table "$scan/${folder%%/*}/_index.md" area || { jr_end; die "$(L "분야 표를 갱신하지 못했습니다" "Could not update the area table")"; }
    _cap_web_write_index "$target_dir" "$links_rel/$folder" topic "${folder##*/}" "$CAP_WEB_AREA" "$CAP_WEB_TOPIC" || { jr_end; die "$(L "세부 분류 허브를 만들지 못했습니다" "Could not create topic index")"; }
    _cap_web_ensure_link_table "$target_dir/_index.md" topic || { jr_end; die "$(L "세부 분류 표를 갱신하지 못했습니다" "Could not update the topic table")"; }
    changed=$((changed + 1))
  done < <(find "$scan" -type f -name '*.md' ! -name '_index.md' | sort)
  # 분류와 별개로, 맥락 칸이 없는 노트에 빈 칸을 만들어 둔다. 분류가 이미
  # 끝난 노트도 대상이다 — 채워 넣을 자리가 없는 것은 분류와 무관하다.
  while IFS= read -r file; do
    if [ "$apply" != 1 ]; then
      grep -qE '^why:' "$file" && grep -qE '^projects:' "$file" || scaffold=$((scaffold + 1))
      continue
    fi
    _cap_web_ensure_context_fields "$file"; rc=$?
    case "$rc" in
      0) scaffold=$((scaffold + 1)) ;;
      2) ;;
      *) jr_end; die "$(L "맥락 칸을 만들지 못했습니다" "Could not add the context fields"): $(basename "$file")" ;;
    esac
  done < <(find "$scan" -type f -name '*.md' ! -name '_index.md' | sort)

  if [ "$apply" != 1 ]; then
    info "$(L "정리 예정" "Would organize"): $planned$(L '개 링크' ' links')"
    [ "$scaffold" -gt 0 ] && info "$(L "맥락 칸 추가 예정" "Would add context fields"): $scaffold$(L '개 링크' ' links')"
    [ "$planned" -gt 0 ] && dim "   $(L '적용' 'Apply'): devtrail capture web --organize --apply"
    return 0
  fi
  [ "$changed" -gt 0 ] && ok "$(L "기존 링크를 분야별로 정리했습니다" "Organized saved links by area"): $changed$(L '개' '')" || info "$(L "새로 분류할 링크가 없습니다" "No saved links needed reclassification")"
  # 값은 비운 채로 만든다. 표에서 비어 보이는 것이 지어낸 이유보다 낫다.
  [ "$scaffold" -gt 0 ] && ok "$(L "저장 이유·프로젝트 칸을 만들었습니다 (값은 비어 있습니다)" "Added empty reason and project fields"): $scaffold$(L '개' '')"
  # ⚠️ 집계는 링크가 다 옮겨진 **뒤에** 계산한다. 먼저 계산하면 방금 옮긴
  #    분야가 집계에 안 나온다.
  _cap_web_ensure_rollup "$scan/_index.md" "$(vault_rel "$links_rel")" || {
    jr_end; die "$(L "분야별 집계를 넣지 못했습니다" "Could not add the by-area rollup")"
  }
  [ "$skipped" -gt 0 ] && warn "$(L "건너뜀" "Skipped"): $skipped"
  [ "$changed" -gt 0 ] && dim "   $(L "되돌리기" "Undo"): devtrail undo"
  jr_end
}
