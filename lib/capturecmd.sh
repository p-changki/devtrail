# ── URL ──────────────────────────────────────────────────────────────────────
cap_video_id() {
  local url="$1" id=""
  case "$url" in
    *youtube.com/watch\?*|*youtube.com/watch\&*)
      id=$(printf '%s' "$url" | sed -n 's/.*[?&]v=\([A-Za-z0-9_-]\{11\}\).*/\1/p') ;;
    *youtu.be/*)
      id=$(printf '%s' "$url" | sed -n 's#.*youtu\.be/\([A-Za-z0-9_-]\{11\}\).*#\1#p') ;;
    *youtube.com/shorts/*)
      id=$(printf '%s' "$url" | sed -n 's#.*/shorts/\([A-Za-z0-9_-]\{11\}\).*#\1#p') ;;
  esac
  [ -n "$id" ] || return 1
  printf '%s' "$id"
}

# 같은 영상의 노트가 이미 있는가. id 로 찾는다 — URL 은 파라미터가 붙어
# 제각각이지만 id 는 하나다.
cap_existing() {
  local dir="$1" id="$2"
  [ -d "$dir" ] || return 1
  grep -rl -- "$id" "$dir" 2>/dev/null | head -1
}

# ── 템플릿 ───────────────────────────────────────────────────────────────────
_cap_render() {
  local tpl="$1" title="$2" url="$3" channel="$4" today="$5" now="$6" purpose="${7:-}"
  # 기존 볼트는 템플릿을 사용자가 이미 고쳐 두었을 수 있다. 새 분류 필드가
  # 없는 옛 YouTube 템플릿도 캡처 자체가 미분류가 되지 않도록, 빈 필드만
  # category 바로 뒤에 보수적으로 덧붙인다. 템플릿의 다른 내용은 바꾸지 않는다.
  local add_area=0 add_topic=0 add_source_kind=0 add_learning_goal=0 purpose_yaml
  grep -qE '^area:' "$tpl" || add_area=1
  grep -qE '^topic:' "$tpl" || add_topic=1
  grep -qE '^source_kind:' "$tpl" || add_source_kind=1
  grep -qE '^learning_goal:' "$tpl" || add_learning_goal=1
  # 입력 목적은 YAML 한 줄 문자열로만 저장한다. 줄바꿈·따옴표가 frontmatter를
  # 깨거나 새 속성을 만들지 못하게 한다.
  purpose_yaml=$(printf '%s' "$purpose" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//; s/\\/\\\\/g; s/"/\\"/g')
  # 값은 정규식 치환이 아닌 splice로 문자 그대로 넣고, 남은 Templater
  # 문법은 아래 검사에서 실패시킨다.
  DT_T="$title" DT_U="$url" DT_C="$channel" DT_D="$today" DT_N="$now" DT_Y_GOAL="$purpose_yaml" \
  DT_Y_ADD_AREA="$add_area" DT_Y_ADD_TOPIC="$add_topic" DT_Y_ADD_SOURCE_KIND="$add_source_kind" DT_Y_ADD_LEARNING_GOAL="$add_learning_goal" \
  awk '
    function splice(s, val,   out) {
      # RSTART/RLENGTH 자리를 val 로 바꿔 이어 붙인다 (문자 그대로).
      out = substr(s, 1, RSTART - 1) val substr(s, RSTART + RLENGTH)
      return out
    }
    {
      line = $0

      # <% tp.date.now("...") %>  →  형식에 HH 가 있으면 시각, 없으면 날짜
      guard = 0
      while (match(line, /<%[ \t]*tp\.date\.now\("[^"]*"\)[ \t]*%>/)) {
        before = length(line)
        m = substr(line, RSTART, RLENGTH)
        q = index(m, "\"")
        rest = substr(m, q + 1)
        fmt = substr(rest, 1, index(rest, "\"") - 1)
        line = splice(line, (index(fmt, "HH") > 0) ? ENVIRON["DT_N"] : ENVIRON["DT_D"])
        # ⚠️ 진행하지 않으면 멈춘다. 아래 <% 검사가 소리내어 실패시킨다.
        if (length(line) >= before || ++guard > 1000) break
      }

      # <% tp.file.title %>
      guard = 0
      while (match(line, /<%[ \t]*tp\.file\.title[ \t]*%>/)) {
        before = length(line)
        line = splice(line, ENVIRON["DT_T"])
        if (length(line) >= before || ++guard > 1000) break
      }

      buf[n++] = line
      # 새 템플릿은 자체 필드를 쓰고, 이전 템플릿에만 누락된 필드를 넣는다.
      # category는 frontmatter에만 등장하는 DevTrail 계약 필드다.
      if (line ~ /^category:[ \t]*/ && !classification_added) {
        if (ENVIRON["DT_Y_ADD_AREA"] == "1") buf[n++] = "area:"
        if (ENVIRON["DT_Y_ADD_TOPIC"] == "1") buf[n++] = "topic:"
        if (ENVIRON["DT_Y_ADD_SOURCE_KIND"] == "1") buf[n++] = "source_kind: youtube"
        if (ENVIRON["DT_Y_ADD_LEARNING_GOAL"] == "1") buf[n++] = "learning_goal:"
        classification_added = 1
      }
    }
    END {
      # 캡처가 아는 것만 채운다. 모르는 것은 비워 둔다 —
      # 빈 칸은 "아직 없다" 는 사실이고, 지어낸 값은 거짓이다.
      # ⚠️ 각 키의 **첫 줄만** 채운다 (python 의 count=1 과 같다).
      split("url channel learning_goal", keys, " ")
      vals["url"] = ENVIRON["DT_U"]
      vals["channel"] = ENVIRON["DT_C"]
      vals["learning_goal"] = ENVIRON["DT_Y_GOAL"]
      for (k = 1; k <= 3; k++) {
        key = keys[k]
        if (vals[key] == "") continue
        for (i = 0; i < n; i++) {
          if (buf[i] ~ ("^" key ":[ \t]*$")) { buf[i] = key ": " vals[key]; break }
        }
      }
      for (i = 0; i < n; i++) {
        if (index(buf[i], "<%") > 0) {
          print "템플릿 문법이 남았습니다" > "/dev/stderr"
          exit 1
        }
      }
      for (i = 0; i < n; i++) printf "%s\n", buf[i]
    }
  ' "$tpl"
}

# yt-dlp --print의 두 줄에서 제목·채널을 각각 읽는다.
cap_parse_meta() {
  case "${1:-}" in
    title)   sed -n '1p' ;;
    channel) sed -n '2p' ;;
    *)       cat ;;
  esac
}

_cap_meta() {
  local url="$1"
  command -v yt-dlp >/dev/null 2>&1 || return 1
  # --print 를 두 번 주면 두 줄로 나온다.
  yt-dlp --skip-download --print '%(title)s' --print '%(channel)s' \
         --no-warnings -- "$url" 2>/dev/null
}

_cap_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^[:alnum:]가-힣]\{1,\}/-/g; s/^-//; s/-$//' | cut -c1-60
}

. "$DEVTRAIL_ROOT/lib/taxonomy.sh"
. "$DEVTRAIL_ROOT/lib/webcapture.sh"

# ── 개발일지 ─────────────────────────────────────────────────────────────────
#
# 메뉴바용 생성기는 CLI가 해석한 파일명·헤딩으로 즉시 쓸 기본 일지를 만든다.
_cap_devlog() {
  local apply=0 repair_empty=0 repair_template=0 repair_order=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      --repair-empty) repair_empty=1 ;;
      --repair-template) repair_template=1 ;;
      --repair-order) repair_order=1 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq

  local root rel dir today file issues worklog morning youtube_rel root_rel
  root=$(vault_root); rel=$(dt_dir devlog)
  [ -n "$rel" ] || die "$(L "개발일지 폴더가 설정에 없습니다" "The devlog folder is not configured")"
  dir="$root/$rel"; today=$(date +%F); file="$dir/$(dt_devlog_name "$today")"
  issues=$(cfg '.headings.issues_pr' '## Issues / PRs')
  worklog=$(cfg '.headings.worklog' '## Work log')
  morning=$(cfg '.headings.morning' '### Morning')
  youtube_rel=$(vault_rel "$(dt_dir youtube)")
  root_rel=$(cfg '.vault.root')

  step "$(L "오늘 개발일지" "Today's devlog")"
  if [ "$repair_order" = 1 ] && [ -f "$file" ]; then
    [ "$apply" = 1 ] || {
      dim "   $(L "정리할 순서: 오늘 할 것 → 작업 로그 → 오늘의 이슈 / PR" \
                 "Would order: top 3 → work log → issues / PRs")"
      return 0
    }
    local stage_order; stage_order=$(mktemp "${TMPDIR:-/tmp}/devtrail-devlog-order.XXXXXX") \
      || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
    _cap_devlog_order "$file" "$issues" "$worklog" > "$stage_order" || {
      rm -f "$stage_order"
      die "$(L "일지 순서를 안전하게 찾지 못했습니다 — 파일은 바꾸지 않았습니다" \
               "Could not safely identify the devlog sections — the file was not changed")"
    }
    jr_begin capture-devlog-reorder
    jr_backup "$file" >/dev/null || { rm -f "$stage_order"; jr_end; die "$(L "개발일지를 백업하지 못했습니다" "Could not back up the devlog")"; }
    cp "$stage_order" "$file" || { rm -f "$stage_order"; jr_end; die "$(L "개발일지 순서를 저장하지 못했습니다" "Could not save the devlog order")"; }
    rm -f "$stage_order"
    ok "$(L "개발일지 순서를 정리했습니다" "Reordered the devlog")"
    printf 'PATH=%s\n' "$file"
    jr_end
    return 0
  fi
  if [ -f "$file" ] && { [ "$repair_empty" != 1 ] || [ -s "$file" ]; }; then
    if [ "$repair_template" = 1 ] && ! grep -qF '## 📺 오늘 본 유튜브' "$file"; then
      [ "$apply" = 1 ] || { dim "   $(L "보완할 자동 집계 영역" "Would restore automatic sections"): $(basename "$file")"; return 0; }
      jr_begin capture-devlog-template-repair
      jr_backup "$file" >/dev/null || { jr_end; die "$(L "개발일지를 백업하지 못했습니다" "Could not back up the devlog")"; }
      _cap_devlog_auto_sections "$youtube_rel" "$root_rel" "$today" >> "$file" \
        || { jr_end; die "$(L "자동 집계 영역을 보완하지 못했습니다" "Could not restore automatic sections")"; }
      ok "$(L "자동 집계 영역을 보완했습니다" "Restored automatic sections"): $(basename "$file")"
      printf 'PATH=%s\n' "$file"; jr_end; return 0
    fi
    ok "$(L "이미 있습니다" "Already exists"): $(basename "$file")"
    printf 'PATH=%s\n' "$file"
    return 0
  fi
  if [ "$apply" != 1 ]; then
    dim "   $(L "만들 노트" "Would create"): $file"
    dim "   $(L "(dry-run — 실제로 만들려면 --apply)" "(dry run — pass --apply to create it)")"
    return 0
  fi

  local stage; stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-devlog.XXXXXX") \
    || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
  cat > "$stage" <<EOF
---
tags:
  - type/devlog
type: devlog
projects: []
date: $today
created: $today
updated: $today
---

# 📅 $today 개발일지

## ☀️ 아침 — 오늘 할 것 (Top 3)

- [ ]
- [ ]
- [ ]

$worklog

$morning

####
-

### 오후

-

$issues

<!-- DevTrail이 이 헤딩 바로 아래에 GitHub/Linear 활동을 자동 삽입합니다. -->

$( _cap_devlog_auto_sections "$youtube_rel" "$root_rel" "$today" )
EOF
  [ -s "$stage" ] || { rm -f "$stage"; die "$(L "빈 일지가 만들어졌습니다" "The devlog came out empty")"; }

  jr_begin capture-devlog
  jr_mkdir "$dir" || { rm -f "$stage"; jr_end; die "$(L "폴더를 만들지 못했습니다" "Could not create the folder")"; }
  if [ -e "$file" ] && { [ "$repair_empty" != 1 ] || [ -s "$file" ]; }; then
    rm -f "$stage"; jr_end
    ok "$(L "이미 있습니다" "Already exists"): $(basename "$file")"
    printf 'PATH=%s\n' "$file"
    return 0
  fi
  local existed=0; [ -e "$file" ] && existed=1
  if [ "$existed" = 1 ]; then
    jr_backup "$file" >/dev/null || {
      rm -f "$stage"; jr_end
      die "$(L "기존 빈 일지를 백업하지 못했습니다" "Could not back up the empty devlog")"
    }
  fi
  cp "$stage" "$file" || { rm -f "$stage"; jr_end; die "$(L "개발일지를 저장하지 못했습니다" "Could not save the devlog")"; }
  rm -f "$stage"; [ "$existed" = 1 ] || jr_created "$file"
  ok "$(basename "$file")"
  printf 'PATH=%s\n' "$file"
  dim "   $(L "GitHub 활동은 생성 직후 자동으로 채워집니다." "GitHub activity is filled automatically after creation.")"
  jr_end
}

# 이미 만든 오늘 일지도 같은 순서로 바꾼다. 헤딩·본문 전체를 문자열 치환하지
# 않는다. 사용자가 기록한 PR 표·작업 로그가 섞여 있으므로, 검증된 세 섹션만
# 통째로 이동하고 형식이 다르면 파일을 건드리지 않는다.
_cap_devlog_order() {
  local file="$1" issues="$2" worklog="$3"
  awk -v issues="$issues" -v worklog="$worklog" '
    BEGIN { state="before"; found_issues=0; found_worklog=0 }
    $0 == issues && state == "before" {
      state="issues"; found_issues=1; issue = issue $0 ORS; next
    }
    $0 == worklog && state == "issues" {
      state="worklog"; found_worklog=1; work = work $0 ORS; next
    }
    state == "issues" { issue = issue $0 ORS; next }
    state == "worklog" && /^## / {
      state="after"; after = after $0 ORS; next
    }
    state == "before" { before = before $0 ORS; next }
    state == "worklog" { work = work $0 ORS; next }
    { after = after $0 ORS }
    END {
      if (!found_issues || !found_worklog) exit 1
      printf "%s%s%s%s", before, work, issue, after
    }
  ' "$file"
}

# CLI로 만든 일지에도 원래 Templater 양식의 읽기 전용 집계 영역을 보존한다.
# 이 블록은 볼트에 쓰지 않고 Dataview가 열 때 읽을 경로만 담는다.
_cap_devlog_auto_sections() {
  local youtube="$1" root="$2" today="$3"
  cat <<EOF

## 📺 오늘 본 유튜브 (자동 집계 — 없으면 섹션째 삭제)

\`\`\`dataview
TABLE WITHOUT ID
  file.link AS "영상",
  channel AS "채널",
  tl_dr_oneline AS "한 줄 요약"
FROM "$youtube"
WHERE type = "youtube" AND watched_at = date(this.date)
SORT file.ctime ASC
\`\`\`

## 💡 오늘 배운 것 (1개만 — 없으면 "없음")

-

## 🔗 오늘 만든 노트 (자동 집계)

\`\`\`dataview
TABLE dateformat(file.ctime, "yyyy-MM-dd HH:mm") AS "생성일시"
FROM "$root"
WHERE file.ctime >= date(this.date) AND file.ctime < date(this.date) + dur(1 day)
  AND file.name != this.file.name
SORT file.ctime DESC
LIMIT 20
\`\`\`

---

## ⏮ 어제 개발일지

\`\`\`dataview
LIST
FROM "$(vault_rel "$(dt_dir devlog)")"
WHERE file.day < this.file.day AND file.day >= this.file.day - dur(7 days)
SORT file.day DESC
LIMIT 1
\`\`\`
EOF
}

# ── 유튜브 캡처 ──────────────────────────────────────────────────────────────
# 자막 확보와 AI 정리는 captureai.sh 가 맡는다 — 이 파일은 노트 생성 흐름만 본다.
. "$DEVTRAIL_ROOT/lib/captureai.sh"

_cap_youtube() {
  local url="" purpose="" apply=0 ai=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --url) shift; url="${1:-}" ;;
      --purpose) shift; purpose="${1:-}" ;;
      --apply) apply=1 ;;
      --ai) ai=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq

  [ -n "$url" ] || die "$(L "URL 이 필요합니다" "A URL is required"): --url \"https://…\""
  local id
  id=$(cap_video_id "$url") || die "$(L "유튜브 동영상 주소가 아닙니다" \
    "That is not a YouTube video URL"): $url
   $(L "받는 형태: watch?v=… · youtu.be/… · shorts/…" \
      "Accepted: watch?v=… · youtu.be/… · shorts/…")"

  # ⚠️ 경로는 dt_dir 하나에서만 온다. 여기서 기본값을 따로 갖지 않는다 —
  #    이 저장소는 dirs.devlog 의 기본값을 네 곳이 각자 가져 같은 결함을
  #    네 번 고쳤다.
  # ⚠️ vault_root() 가 볼트 + 루트 폴더까지 붙여 준다. 여기서 다시 조립하면
  #    루트가 비었을 때 "//유튜브" 같은 경로가 나온다.
  local root rel dir
  root=$(vault_root)
  rel=$(dt_dir youtube)
  [ -n "$rel" ] || die "$(L "유튜브 폴더가 설정에 없습니다" \
    "The YouTube folder is not configured")
   $(L "확인" "Check"): devtrail config effective"
  dir="$root/$rel"

  step "$(L "유튜브 캡처" "Capture from YouTube")"
  info "  $(L "동영상" "Video"): $id"

  # ⚠️ 중복은 만들기 전에 본다. 만들고 나서 지우면 저널에 흔적이 남고,
  #    사용자는 왜 두 개가 생겼다 하나가 사라졌는지 모른다.
  local dup; dup=$(cap_existing "$dir" "$id")
  if [ -n "$dup" ]; then
    # 사용자가 같은 링크에서 "저장하고 정리"를 다시 눌렀다면, 새 파일을
    # 만들지 말고 비어 있는 기존 노트의 AI 정리만 재시도한다.
    if [ "$apply" = 1 ] && [ "$ai" = 1 ]; then
      jr_begin capture-youtube-ai-retry
      jr_backup "$dup" >/dev/null || { jr_end; die "$(L "AI 정리 전 백업에 실패했습니다" "Could not back up before AI analysis")"; }
      printf 'DEVTRAIL_CAPTURE_PATH=%s\n' "$dup"
      _cap_youtube_ai "$url" "$dup" "$root" "$purpose"
      ok "$(L "기존 유튜브 노트를 다시 정리했습니다" "Retried the existing YouTube note")"
      dim "   $(basename "$dup")"
      jr_end
      return 0
    fi
    echo
    warn "$(L "이미 저장된 영상입니다" "You already saved this video")"
    # 앱에서는 이 결과를 재실행 성공으로 오해하지 않고 기존 노트 안내로
    # 보여 준다. 같은 URL을 다시 눌러도 새 파일은 만들지 않는다.
    printf 'DEVTRAIL_CAPTURE_DUPLICATE=%s\n' "$dup"
    dim "   $(basename "$dup")"
    dim "   $dir"
    return 0
  fi

  local trel; trel=$(dt_dir templates)
  local tpl="$root/$trel/$(L "유튜브 노트 템플릿.md" "YouTube note.md")"
  [ -f "$tpl" ] || die "$(L "유튜브 노트 템플릿이 없습니다" "The YouTube note template is missing"): $tpl
   $(L "먼저" "First"): devtrail obsidian"

  local title="" channel="" meta
  if [ "$apply" = 1 ] && [ -z "${DT_CAPTURE_NO_NET:-}" ]; then
    # ⚠️ URL 을 붙여넣는 것만으로 요청하지 않는다. 저장할 때만 한 번.
    meta=$(_cap_meta "$url") || meta=""
    title=$(printf '%s' "$meta" | cap_parse_meta title)
    channel=$(printf '%s' "$meta" | cap_parse_meta channel)
  fi
  [ -n "$title" ] || title="$id"

  local today now file
  today=$(date +%F); now=$(date '+%Y-%m-%d %H:%M')
  file="$dir/$today-$(_cap_slug "$title").md"

  info "  $(L "제목" "Title"): $title"
  [ -n "$channel" ] && info "  $(L "채널" "Channel"): $channel"

  if [ "$apply" != 1 ]; then
    echo
    dim "   $(L "만들 노트" "Would create"): $(basename "$file")"
    dim "   $(L "(dry-run — 실제로 만들려면 --apply)" "(dry run — pass --apply to create it)")"
    dim "   $(L "적용" "Apply"): devtrail capture youtube --url \"$url\" --apply"
    return 0
  fi

  # ── 준비 ─────────────────────────────────────────────────────────────────
  # ⚠️ 볼트 밖에서 다 만들어 본 뒤에만 옮긴다. 절반만 쓴 노트가 최악이다 —
  #    frontmatter 는 있는데 본문이 없으면 Obsidian 은 그것을 정상 노트로 읽는다.
  local stage; stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-cap.XXXXXX") \
    || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
  if [ -n "${DT_CAPTURE_FAIL:-}" ]; then
    rm -f "$stage"; die "$(L "테스트용 실패" "Simulated failure")"
  fi
  _cap_render "$tpl" "$title" "$url" "$channel" "$today" "$now" "$purpose" > "$stage" || {
    rm -f "$stage"
    die "$(L "노트를 만들지 못했습니다 — 볼트는 그대로입니다" \
             "Could not build the note — the vault is unchanged")"
  }
  [ -s "$stage" ] || { rm -f "$stage"; die "$(L "빈 노트가 나왔습니다" "The note came out empty")"; }

  jr_begin capture-youtube
  mkdir -p "$dir"
  cp "$stage" "$file" || { rm -f "$stage"; jr_end; die "$(L "저장하지 못했습니다" "Could not save")"; }
  rm -f "$stage"
  jr_created "$file"
  # 이후 AI 단계가 외부 영상 권한 때문에 중단돼도 앱은 이 표식으로
  # "링크 노트는 저장됨"을 정확히 구분한다.
  printf 'DEVTRAIL_CAPTURE_PATH=%s\n' "$file"

  # AI가 같은 노트를 보완하므로 생성 직후 상태를 같은 저널에 백업한다.
  # undo 하면 링크를 지우거나(생성 저널) 분석 전 상태로 되돌릴 수 있다.
  if [ "$ai" = 1 ]; then
    jr_backup "$file" >/dev/null || { jr_end; die "$(L "AI 정리 전 백업에 실패했습니다" "Could not back up before AI analysis")"; }
    _cap_youtube_ai "$url" "$file" "$root" "$purpose"
  fi

  ok "$(basename "$file")"
  dim "   $dir"
  if [ "$ai" != 1 ]; then
    dim "   $(L "요약·적용점은 비어 있습니다. --ai를 붙이면 유튜브 스킬이 채웁니다." \
               "The summary and takeaways are empty. Pass --ai to run the YouTube skill.")"
  fi
  dim "   $(L "되돌리기" "Undo"): devtrail undo"
  jr_end
}

capture_cmd() {
  local what="${1:-}"; shift 2>/dev/null || true
  case "$what" in
    youtube) _cap_youtube "$@" ;;
    web)     _cap_web "$@" ;;
    devlog)  _cap_devlog "$@" ;;
    ""|-h|--help) usage_capture ;;
    *) die "$(L "알 수 없는 대상" "Unknown target"): $what
   $(L "받는 것" "Supported"): youtube, web, devlog" ;;
  esac
}

usage_capture() {
  cat <<EOF
$(L "사용법" "Usage"): devtrail capture <youtube|web|devlog> [options] [--apply]

  $(L "Obsidian 없이 링크를 받아 둡니다. 요약과 적용점은 비어 있고," \
     "Saves a link without Obsidian. The summary and takeaways stay empty;")
  $(L "자막 분석은 유튜브 스킬이 나중에 채웁니다." \
     "the YouTube skill fills those in later.")

  $(L "일반 웹 링크는 AI 없이 title·Open Graph 메타를 읽어 자료실 링크 폴더에 분류해 저장합니다." \
     "General web links read title and Open Graph metadata and file them into categorized Library links without AI.")
  devtrail capture web --url "https://example.com" [--apply]
EOF
}
