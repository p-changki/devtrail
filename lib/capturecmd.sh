# devtrail capture — Obsidian 없이 여는 좁은 쓰기 통로 (ADR 0003)
#
# ⚠️ ADR 0002 는 Templater 를 쓰기의 유일한 통로로 정했다. 그 결정은 지금도
#    옳다 — 노트 형식이 두 곳에서 만들어지면 반드시 어긋난다. 이 파일은 그
#    경계를 **한 뼘만** 넓힌다. 넓히는 대가로 네 가지를 지킨다:
#
#      1. 기본이 dry-run    --apply 없이는 파일이 생기지 않는다
#      2. 저널              모든 생성이 devtrail undo 로 사라진다
#      3. 원자적            검증을 다 마친 뒤에만 쓴다
#      4. 템플릿 단일 출처  형식은 볼트의 템플릿에서 온다
#
#    넷 중 하나라도 빼면 두 번째 쓰기 출처가 된다.

# ── URL ──────────────────────────────────────────────────────────────────────
#
# ⚠️ 애매하면 거절한다. 잘못 만든 노트보다 안 만든 게 낫다 — 사람이 나중에
#    지워야 하고, 그때는 왜 생겼는지도 모른다.
#
# 받는 것: watch?v=ID · youtu.be/ID · m.youtube.com · 추가 파라미터
# 받지 않는 것: 채널 · 재생목록만 있는 주소 · 유튜브가 아닌 곳
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
#
# ⚠️ 형식을 여기서 만들지 않는다. 볼트의 템플릿을 읽어 Templater 문법만
#    치환한다 — 그래야 Obsidian 에서 만든 노트와 같은 모양이 된다.
_cap_render() {
  local tpl="$1" title="$2" url="$3" channel="$4" today="$5" now="$6"
  DT_T="$title" DT_U="$url" DT_C="$channel" DT_D="$today" DT_N="$now" \
  python3 - "$tpl" <<'PY'
import io, os, re, sys
raw = io.open(sys.argv[1], encoding='utf-8').read()
env = os.environ
# Templater 의 날짜 호출만 실제 값으로 바꾼다. 나머지 문법이 남으면
# 아래에서 잡아낸다 — 조용히 통과시키지 않는다.
def date_of(m):
    fmt = m.group(1)
    return env['DT_N'] if 'HH' in fmt else env['DT_D']
out = re.sub(r'<%\s*tp\.date\.now\("([^"]+)"\)\s*%>', date_of, raw)
out = re.sub(r'<%\s*tp\.file\.title\s*%>', env['DT_T'], out)
# 캡처가 아는 것만 채운다. 모르는 것은 비워 둔다 —
# 빈 칸은 '아직 없다' 는 사실이고, 지어낸 값은 거짓이다.
for key, val in (('url', env['DT_U']), ('channel', env['DT_C'])):
    if val:
        out = re.sub(r'(?m)^' + key + r':\s*$', key + ': ' + val, out, count=1)
if '<%' in out:
    sys.stderr.write('템플릿 문법이 남았습니다\n')
    raise SystemExit(1)
sys.stdout.write(out)
PY
}

# yt-dlp 출력에서 한 필드를 뽑는다.
#
# ⚠️ 한 줄에 탭으로 이어 붙이지 않는다 — --print 의 서식 문자열에서 \t 는
#    문자 그대로 나가고, 제목과 채널이 한 덩어리가 된다. 2026-08-22 에
#    실제로 그랬다. 줄바꿈이 기준이다.
# ⚠️ 채널을 못 얻으면 빈 값이다. 제목을 채널 자리에 넣지 않는다 —
#    없는 것을 있는 척하는 순간 노트가 거짓을 말한다.
cap_parse_meta() {
  case "${1:-}" in
    title)   sed -n '1p' ;;
    channel) sed -n '2p' ;;
    *)       cat ;;
  esac
}

# 제목·채널을 가져온다. 실패해도 저장은 계속한다 —
# 링크를 잃는 것보다 제목이 없는 편이 낫다.
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

# ── 유튜브 캡처 ──────────────────────────────────────────────────────────────
_cap_youtube() {
  local url="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --url) shift; url="${1:-}" ;;
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq python3

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
    echo
    warn "$(L "이미 저장된 영상입니다" "You already saved this video")"
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
  _cap_render "$tpl" "$title" "$url" "$channel" "$today" "$now" > "$stage" || {
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

  ok "$(basename "$file")"
  dim "   $dir"
  # ⚠️ 분석은 아직 안 했다. 그렇게 말한다 — 빈 칸을 채워 준 척하지 않는다.
  dim "   $(L "요약·적용점은 비어 있습니다. 자막 분석은 유튜브 스킬이 채웁니다." \
             "The summary and takeaways are empty. The YouTube skill fills those in.")"
  dim "   $(L "되돌리기" "Undo"): devtrail undo"
  jr_end
}

capture_cmd() {
  local what="${1:-}"; shift 2>/dev/null || true
  case "$what" in
    youtube) _cap_youtube "$@" ;;
    ""|-h|--help) usage_capture ;;
    *) die "$(L "알 수 없는 대상" "Unknown target"): $what
   $(L "받는 것" "Supported"): youtube" ;;
  esac
}

usage_capture() {
  cat <<EOF
$(L "사용법" "Usage"): devtrail capture youtube --url "<URL>" [--apply]

  $(L "Obsidian 없이 링크를 받아 둡니다. 요약과 적용점은 비어 있고," \
     "Saves a link without Obsidian. The summary and takeaways stay empty;")
  $(L "자막 분석은 유튜브 스킬이 나중에 채웁니다." \
     "the YouTube skill fills those in later.")
EOF
}
