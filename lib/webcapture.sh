#!/usr/bin/env bash
# DevTrail — 일반 웹 링크 캡처.
# capturecmd.sh가 _cap_slug와 공통 안전/저널 함수를 준비한 뒤 불러온다.

# ── 일반 웹 링크 ─────────────────────────────────────────────────────────────
#
# 웹 캡처는 브라우저 자동화나 AI를 하지 않는다. 일반 HTML의 title/OG 메타만
# 읽고, 못 읽으면 원본 URL을 보존한다. 다만 사용자 입력 URL이 내부망을
# 찌르는 통로가 되면 안 되므로, URL·DNS 결과·각 리다이렉트를 모두 검사한다.

_cap_web_clean() {
  # frontmatter 한 줄 값에는 개행·탭을 넣지 않는다. HTML 안의 줄바꿈이 YAML
  # 키를 탈출하는 것을 막고, 사람이 읽기에도 한 줄 메타가 낫다.
  printf '%s' "$1" | tr '\r\n\t' '   ' \
    | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}
_cap_web_yaml() {
  _cap_web_clean "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_cap_web_public_ipv4() {
  # 사설·loopback·link-local·문서용/예약 대역은 요청하지 않는다.
  local ip="$1" a b c d n
  local IFS=.
  read -r a b c d <<EOF
$ip
EOF
  for n in "$a" "$b" "$c" "$d"; do
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#n}" -le 3 ] || return 1
    [ $((10#$n)) -le 255 ] 2>/dev/null || return 1
  done
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c))
  case "$a" in 0|10|127|224|225|226|227|228|229|230|231|232|233|234|235|236|237|238|239|240|241|242|243|244|245|246|247|248|249|250|251|252|253|254|255) return 1 ;; esac
  [ "$a" -eq 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ] && return 1
  [ "$a" -eq 169 ] && [ "$b" -eq 254 ] && return 1
  [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 1
  [ "$a" -eq 192 ] && { [ "$b" -eq 0 ] || [ "$b" -eq 168 ]; } && return 1
  [ "$a" -eq 198 ] && [ "$b" -ge 18 ] && [ "$b" -le 19 ] && return 1
  return 0
}

_cap_web_safe_url() {
  # 결과는 CAP_WEB_*에 둔다. bash 3.2에는 nameref가 없어 호출자가 문자열을
  # 돌려받아 다시 파싱하지 않도록 했다.
  local url="$1" rest authority host port scheme
  case "$url" in
    http://*)  scheme=http ; rest=${url#http://} ;;
    https://*) scheme=https; rest=${url#https://} ;;
    *) return 1 ;;
  esac
  case "$url" in *[[:space:]]*|*\\*) return 1 ;; esac
  authority=${rest%%[/?#]*}
  [ -n "$authority" ] || return 1
  case "$authority" in *'@'*|*'['*|*']'*) return 1 ;; esac
  if [[ "$authority" == *:* ]]; then
    host=${authority%%:*}; port=${authority#*:}
    case "$port" in ''|*[!0-9]*) return 1 ;; esac
  else
    host="$authority"
    [ "$scheme" = https ] && port=443 || port=80
  fi
  [ -n "$host" ] || return 1
  printf '%s' "$host" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' || return 1
  # 비표준 포트는 내부 서비스로 향할 가능성이 커 MVP에서는 받지 않는다.
  { [ "$scheme" = http ] && [ "$port" = 80 ]; } || { [ "$scheme" = https ] && [ "$port" = 443 ]; } || return 1
  host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
  case "$host" in
    localhost|*.localhost|*.local|*.internal|metadata.google.internal) return 2 ;;
  esac
  # 직접 입력한 IP도 URL 검증 단계에서 막는다. 테스트 fixture나 네트워크
  # 폴백 경로가 있어도 내부 주소가 '저장 가능한 URL'로 통과하면 안 된다.
  if printf '%s' "$host" | grep -Eq '^[0-9.]+$'; then
    _cap_web_public_ipv4 "$host" || return 2
  fi
  CAP_WEB_SCHEME="$scheme"; CAP_WEB_HOST="$host"; CAP_WEB_PORT="$port"
  CAP_WEB_ORIGIN="$scheme://$authority"
  return 0
}

_cap_web_resolve_public() {
  local host="$1" ips ip first=""
  # 숫자 IP는 DNS를 다시 거치지 않는다.
  if printf '%s' "$host" | grep -Eq '^[0-9.]+$'; then
    _cap_web_public_ipv4 "$host" || return 2
    printf '%s' "$host"
    return 0
  fi
  # dscacheutil은 macOS 기본 DNS 해석기다. 없거나 주소를 못 얻으면 요청을
  # 억지로 보내지 않고 메타데이터 없는 링크 저장으로 폴백한다.
  has dscacheutil || return 1
  ips=$(dscacheutil -q host -a name "$host" 2>/dev/null \
    | sed -n 's/^[[:space:]]*ip_address: //p')
  [ -n "$ips" ] || return 1
  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    # IPv6만 있는 호스트는 이 경량 MVP에서 수집하지 않는다. curl이 다시
    # 해석하도록 두면 DNS rebinding 보호가 깨진다.
    printf '%s' "$ip" | grep -Eq '^[0-9.]+$' || return 1
    _cap_web_public_ipv4 "$ip" || return 2
    [ -n "$first" ] || first="$ip"
  done <<EOF
$ips
EOF
  [ -n "$first" ] || return 1
  printf '%s' "$first"
}

_cap_web_redirect_url() {
  local current="$1" location="$2"
  location=$(_cap_web_clean "$location")
  case "$location" in
    http://*|https://*) printf '%s' "$location" ;;
    //*) printf '%s:%s' "${current%%:*}" "$location" ;;
    /*) _cap_web_safe_url "$current" || return 1; printf '%s%s' "$CAP_WEB_ORIGIN" "$location" ;;
    *) return 1 ;;
  esac
}

_cap_web_fetch() {
  # 성공: $2에 HTML, CAP_WEB_FINAL_URL 설정. 1=네트워크/메타 실패,
  # 2=위험한 대상(저장도 거부)이다.
  local current="$1" out="$2" tmp head body code location next ip n=0 ct
  if [ -n "${DT_WEB_FETCH_FILE:-}" ]; then
    [ -f "$DT_WEB_FETCH_FILE" ] || return 1
    cp "$DT_WEB_FETCH_FILE" "$out" || return 1
    CAP_WEB_FINAL_URL="${DT_WEB_FINAL_URL:-$current}"
    return 0
  fi
  [ -z "${DT_WEB_FETCH_FAIL:-}" ] || return 1
  # curl은 macOS에 기본 포함이지만, 없는 환경에서도 링크 자체를 잃지 않도록
  # 호출부가 메타데이터 없는 저장으로 폴백한다.
  has curl || return 1
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/devtrail-web.XXXXXX") || return 1
  while [ "$n" -lt 4 ]; do
    _cap_web_safe_url "$current"; case $? in 0) ;; 2) rm -rf "$tmp"; return 2 ;; *) rm -rf "$tmp"; return 1 ;; esac
    ip=$(_cap_web_resolve_public "$CAP_WEB_HOST"); case $? in 0) ;; 2) rm -rf "$tmp"; return 2 ;; *) rm -rf "$tmp"; return 1 ;; esac
    head="$tmp/headers"; body="$tmp/body"
    code=$(curl --silent --show-error --proto '=http,https' \
      --connect-timeout 5 --max-time 15 --max-filesize 1048576 --max-redirs 0 \
      --resolve "$CAP_WEB_HOST:$CAP_WEB_PORT:$ip" \
      --header 'User-Agent: DevTrail-WebCapture/1.0 (+https://github.com/p-changki/devtrail)' \
      --dump-header "$head" --output "$body" --write-out '%{http_code}' -- "$current" 2>/dev/null) || { rm -rf "$tmp"; return 1; }
    case "$code" in
      301|302|303|307|308)
        location=$(grep -i '^location:' "$head" | tail -1 | sed 's/^[^:]*:[[:space:]]*//; s/\r$//')
        [ -n "$location" ] || { rm -rf "$tmp"; return 1; }
        next=$(_cap_web_redirect_url "$current" "$location") || { rm -rf "$tmp"; return 1; }
        current="$next"; n=$((n + 1)); continue ;;
      2??) ;;
      *) rm -rf "$tmp"; return 1 ;;
    esac
    ct=$(grep -i '^content-type:' "$head" | tail -1 | sed 's/^[^:]*:[[:space:]]*//; s/\r$//')
    printf '%s' "$ct" | grep -qiE '^(text/html|application/xhtml\+xml)' || { rm -rf "$tmp"; return 1; }
    cp "$body" "$out" || { rm -rf "$tmp"; return 1; }
    CAP_WEB_FINAL_URL="$current"
    rm -rf "$tmp"
    return 0
  done
  rm -rf "$tmp"
  return 1
}

_cap_web_attr() {
  local tag="$1" attr="$2"
  printf '%s\n' "$tag" | sed -nE "s/.*[[:space:]]${attr}[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\\1/p" | head -1
}

_cap_web_meta_value() {
  local html="$1" key="$2" tag value
  while IFS= read -r tag; do
    printf '%s' "$tag" | grep -qiE "^[[:space:]]*meta[[:space:]][^>]*(property|name)[[:space:]]*=[[:space:]]*['\"]?${key}(['\"[:space:]>]|$)" || continue
    value=$(_cap_web_attr "$tag" content)
    [ -n "$value" ] && { _cap_web_clean "$value"; return 0; }
  done < <(tr '<' '\n' < "$html")
  return 1
}

_cap_web_title() {
  local value
  # tr이 마지막 개행도 공백으로 바꾸므로 while read에 넘기면 macOS bash에서
  # 본문이 실행되지 않을 수 있다. 명령 치환으로 먼저 받은 뒤 정리한다.
  value=$(tr '\n' ' ' < "$1" | sed -nE 's@.*<[Tt][Ii][Tt][Ll][Ee][^>]*>([^<]*)</[Tt][Ii][Tt][Ll][Ee]>.*@\1@p' | head -1)
  _cap_web_clean "$value"
}

_cap_web_canonical() {
  local html="$1" tag value
  while IFS= read -r tag; do
    printf '%s' "$tag" | grep -qiE "^[[:space:]]*link[[:space:]][^>]*rel[[:space:]]*=[[:space:]]*['\"]?canonical(['\"[:space:]>]|$)" || continue
    value=$(_cap_web_attr "$tag" href)
    [ -n "$value" ] && { _cap_web_clean "$value"; return 0; }
  done < <(tr '<' '\n' < "$html")
  return 1
}

_cap_web_classify() {
  local url="$1" host="$2" title="$3" hay topic=""
  hay=$(printf '%s %s %s' "$url" "$host" "$title" | tr '[:upper:]' '[:lower:]')
  CAP_WEB_TYPE=reference
  case "$hay" in
    *docs*|*documentation*|*developer.mozilla.org*) CAP_WEB_TYPE=docs ;;
    *github.com*) CAP_WEB_TYPE=tool ;;
    *icon*|*icons*|*illustration*|*asset*) CAP_WEB_TYPE=asset; topic=assets ;;
    *dribbble*|*behance*|*figma*) CAP_WEB_TYPE=inspiration; topic=design ;;
    *blog*|*news*|*article*|*/read/*) CAP_WEB_TYPE=article ;;
  esac
  case "$hay" in *icon*|*icons*) topic=icons ;; esac
  CAP_WEB_TAGS="[\"type/$CAP_WEB_TYPE\", \"source/$host\""
  [ -n "$topic" ] && CAP_WEB_TAGS="$CAP_WEB_TAGS, \"topic/$topic\""
  CAP_WEB_TAGS="$CAP_WEB_TAGS]"
}

_cap_web_existing() {
  local dir="$1" url="$2" canonical="$3" hit=""
  [ -d "$dir" ] || return 1
  hit=$(grep -rlF -- "$url" "$dir" 2>/dev/null | head -1)
  [ -z "$hit" ] && [ -n "$canonical" ] && hit=$(grep -rlF -- "$canonical" "$dir" 2>/dev/null | head -1)
  [ -n "$hit" ] || return 1
  printf '%s' "$hit"
}

_cap_render_web() {
  local tpl="$1" title="$2" type="$3" tags="$4" source="$5" url="$6" canonical="$7" description="$8" image="$9" saved="${10}" now="${11}"
  DT_W_TITLE=$(_cap_web_yaml "$title") DT_W_TYPE=$(_cap_web_yaml "$type") DT_W_TAGS="$tags" \
  DT_W_SOURCE=$(_cap_web_yaml "$source") DT_W_URL=$(_cap_web_yaml "$url") DT_W_CANON=$(_cap_web_yaml "$canonical") \
  DT_W_DESC=$(_cap_web_yaml "$description") DT_W_IMAGE=$(_cap_web_yaml "$image") DT_W_SAVED="$saved" DT_W_CREATED="$now" \
  awk '
    function replace(line, needle, value, p) { p=index(line, needle); return p ? substr(line,1,p-1) value substr(line,p+length(needle)) : line }
    {
      line=$0
      line=replace(line,"{{WEB_TITLE}}",ENVIRON["DT_W_TITLE"])
      line=replace(line,"{{WEB_TYPE}}",ENVIRON["DT_W_TYPE"])
      line=replace(line,"{{WEB_TAGS}}",ENVIRON["DT_W_TAGS"])
      line=replace(line,"{{WEB_SOURCE}}",ENVIRON["DT_W_SOURCE"])
      line=replace(line,"{{WEB_URL}}",ENVIRON["DT_W_URL"])
      line=replace(line,"{{WEB_CANONICAL}}",ENVIRON["DT_W_CANON"])
      line=replace(line,"{{WEB_DESCRIPTION}}",ENVIRON["DT_W_DESC"])
      line=replace(line,"{{WEB_IMAGE}}",ENVIRON["DT_W_IMAGE"])
      line=replace(line,"{{WEB_SAVED}}",ENVIRON["DT_W_SAVED"])
      line=replace(line,"{{WEB_CREATED}}",ENVIRON["DT_W_CREATED"])
      print line
    }
  ' "$tpl"
}

_cap_web() {
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
  require_config; require_bins jq
  [ -n "$url" ] || die "$(L "URL 이 필요합니다" "A URL is required"): --url \"https://…\""
  url=${url%%#*}
  _cap_web_safe_url "$url"; case $? in
    0) ;;
    2) die "$(L "내부·로컬 주소는 저장하지 않습니다" "Internal or local addresses are not accepted"): $url" ;;
    *) die "$(L "http 또는 https의 올바른 URL이 필요합니다" "A valid http or https URL is required"): $url" ;;
  esac

  local root rel dir trel tpl stage title="" description="" image="" canonical="" final_url="$url" site="" og_type="" now today file base slug n=2 dup fetch_rc source_host
  root=$(vault_root); rel=$(dt_dir inbox)
  [ -n "$rel" ] || die "$(L "자료실 Inbox 폴더가 설정에 없습니다" "The Library Inbox folder is not configured")"
  dir="$root/$rel"; trel=$(dt_dir templates)
  tpl="$root/$trel/$(L "웹 링크 노트 템플릿.md" "Web link note.md")"
  [ -f "$tpl" ] || die "$(L "웹 링크 노트 템플릿이 없습니다" "The web link note template is missing"): $tpl
   $(L "먼저" "First"): devtrail obsidian"

  step "$(L "웹 링크 저장" "Capture web link")"
  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-note.XXXXXX") || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
  if _cap_web_fetch "$url" "$stage"; then
    final_url="$CAP_WEB_FINAL_URL"
    title=$(_cap_web_meta_value "$stage" 'og:title' || true); [ -n "$title" ] || title=$(_cap_web_title "$stage" || true)
    description=$(_cap_web_meta_value "$stage" 'og:description' || true); [ -n "$description" ] || description=$(_cap_web_meta_value "$stage" 'description' || true)
    image=$(_cap_web_meta_value "$stage" 'og:image' || true)
    site=$(_cap_web_meta_value "$stage" 'og:site_name' || true)
    og_type=$(_cap_web_meta_value "$stage" 'og:type' || true)
    canonical=$(_cap_web_canonical "$stage" || true)
    rm -f "$stage"
  else
    fetch_rc=$?; rm -f "$stage"
    [ "$fetch_rc" -eq 2 ] && die "$(L "내부·로컬 주소로 향하는 요청을 막았습니다" "Blocked a request to an internal or local address")"
    warn "$(L "메타데이터를 읽지 못했지만 링크는 저장합니다" "Could not fetch metadata; saving the link anyway")"
  fi
  source_host="$CAP_WEB_HOST"
  # canonical이 상대 경로·다른 scheme이면 추측해서 합치지 않는다. URL 하나를
  # 틀리게 만드는 것보다 비워 두는 쪽이 검색과 중복 판정에 안전하다.
  _cap_web_safe_url "$canonical" >/dev/null 2>&1 || canonical=""
  title=$(_cap_web_clean "$title"); [ -n "$title" ] || title="$source_host"
  _cap_web_classify "$final_url" "$source_host" "$title"
  today=$(date +%F); now=$(date '+%Y-%m-%d %H:%M')
  slug=$(_cap_slug "$title"); [ -n "$slug" ] || slug=$(_cap_slug "$source_host")
  [ -n "$slug" ] || slug="web-link"
  base="$dir/$today-$slug"; file="$base.md"

  info "  $(L "제목" "Title"): $title"
  info "  $(L "도메인" "Domain"): $source_host"
  info "  type: $CAP_WEB_TYPE"
  info "  tags: $CAP_WEB_TAGS"
  [ -n "$site" ] && dim "   $(L "사이트" "Site"): $site"
  [ -n "$og_type" ] && dim "   OG type: $og_type"
  dup=$(_cap_web_existing "$dir" "$url" "$canonical")
  if [ -n "$dup" ]; then
    warn "$(L "이미 저장된 링크입니다" "You already saved this link")"
    printf 'DEVTRAIL_CAPTURE_DUPLICATE=%s\n' "$dup"
    dim "   $dup"
    return 0
  fi
  # URL은 다른데 제목만 같은 페이지가 있어도 기존 파일을 덮어쓰지 않는다.
  # 중복 URL은 위에서 막고, 이름 충돌은 안전한 번호 접미사로만 푼다.
  while [ -e "$file" ]; do file="$base-$n.md"; n=$((n + 1)); done
  if [ "$apply" != 1 ]; then
    dim "   $(L "만들 노트" "Would create"): $file"
    dim "   $(L "(dry-run — 실제로 만들려면 --apply)" "(dry run — pass --apply to create it)")"
    dim "   $(L "적용" "Apply"): devtrail capture web --url \"$url\" --apply"
    return 0
  fi

  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-note.XXXXXX") || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
  _cap_render_web "$tpl" "$title" "$CAP_WEB_TYPE" "$CAP_WEB_TAGS" "$source_host" "$url" "$canonical" "$description" "$image" "$today" "$now" > "$stage" || { rm -f "$stage"; die "$(L "웹 링크 노트를 만들지 못했습니다" "Could not build the web link note")"; }
  [ -s "$stage" ] || { rm -f "$stage"; die "$(L "빈 노트가 나왔습니다" "The note came out empty")"; }
  grep -q '{{WEB_' "$stage" && { rm -f "$stage"; die "$(L "템플릿 값이 남았습니다" "A template value was left unresolved")"; }

  jr_begin capture-web
  jr_mkdir "$dir" || { rm -f "$stage"; jr_end; die "$(L "자료실 Inbox를 만들지 못했습니다" "Could not create the Library Inbox")"; }
  # 같은 디렉터리의 임시 파일을 mv해 원자적으로 완성본만 보이게 한다.
  local target_tmp="$dir/.devtrail-web-$$.tmp"
  cp "$stage" "$target_tmp" && mv "$target_tmp" "$file" || { rm -f "$stage" "$target_tmp"; jr_end; die "$(L "저장하지 못했습니다" "Could not save")"; }
  rm -f "$stage"
  jr_created "$file"
  printf 'DEVTRAIL_CAPTURE_PATH=%s\n' "$file"
  ok "$(basename "$file")"
  dim "   $(L "되돌리기" "Undo"): devtrail undo"
  jr_end
}
