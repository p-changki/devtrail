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
  cap_taxonomy_web "$1" "$2" "$3" "${4:-}"
  CAP_WEB_TYPE="$CAP_TAX_TYPE"
  CAP_WEB_AREA="$CAP_TAX_AREA"
  CAP_WEB_TOPIC="$CAP_TAX_TOPIC"
  CAP_WEB_SOURCE_KIND="$CAP_TAX_SOURCE_KIND"
  CAP_WEB_TAGS="$CAP_TAX_TAGS"
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
  local tpl="$1" title="$2" type="$3" tags="$4" area="$5" topic="$6" source_kind="$7" source="$8" url="$9" canonical="${10}" description="${11}" image="${12}" saved="${13}" now="${14}"
  # 템플릿은 사용자 볼트의 소유물이다. 다만 이전 버전의 템플릿에 새 검색
  # 필드가 없더라도 링크가 자료실에서 사라지지 않도록, 없는 키만 type 뒤에
  # 추가한다. 이미 있는 값·사용자 템플릿의 본문은 건드리지 않는다.
  local add_area=0 add_topic=0 add_source_kind=0
  grep -qE '^area:' "$tpl" || add_area=1
  grep -qE '^topic:' "$tpl" || add_topic=1
  grep -qE '^source_kind:' "$tpl" || add_source_kind=1
  DT_W_TITLE=$(_cap_web_yaml "$title") DT_W_TYPE=$(_cap_web_yaml "$type") DT_W_TAGS="$tags" \
  DT_W_AREA=$(_cap_web_yaml "$area") DT_W_TOPIC=$(_cap_web_yaml "$topic") DT_W_SOURCE_KIND=$(_cap_web_yaml "$source_kind") \
  DT_W_SOURCE=$(_cap_web_yaml "$source") DT_W_URL=$(_cap_web_yaml "$url") DT_W_CANON=$(_cap_web_yaml "$canonical") \
  DT_W_DESC=$(_cap_web_yaml "$description") DT_W_IMAGE=$(_cap_web_yaml "$image") DT_W_SAVED="$saved" DT_W_CREATED="$now" \
  DT_W_ADD_AREA="$add_area" DT_W_ADD_TOPIC="$add_topic" DT_W_ADD_SOURCE_KIND="$add_source_kind" \
  awk '
    function replace(line, needle, value, p) { p=index(line, needle); return p ? substr(line,1,p-1) value substr(line,p+length(needle)) : line }
    {
      line=$0
      line=replace(line,"{{WEB_TITLE}}",ENVIRON["DT_W_TITLE"])
      line=replace(line,"{{WEB_TYPE}}",ENVIRON["DT_W_TYPE"])
      line=replace(line,"{{WEB_TAGS}}",ENVIRON["DT_W_TAGS"])
      line=replace(line,"{{WEB_AREA}}",ENVIRON["DT_W_AREA"])
      line=replace(line,"{{WEB_TOPIC}}",ENVIRON["DT_W_TOPIC"])
      line=replace(line,"{{WEB_SOURCE_KIND}}",ENVIRON["DT_W_SOURCE_KIND"])
      line=replace(line,"{{WEB_SOURCE}}",ENVIRON["DT_W_SOURCE"])
      line=replace(line,"{{WEB_URL}}",ENVIRON["DT_W_URL"])
      line=replace(line,"{{WEB_CANONICAL}}",ENVIRON["DT_W_CANON"])
      line=replace(line,"{{WEB_DESCRIPTION}}",ENVIRON["DT_W_DESC"])
      line=replace(line,"{{WEB_IMAGE}}",ENVIRON["DT_W_IMAGE"])
      line=replace(line,"{{WEB_SAVED}}",ENVIRON["DT_W_SAVED"])
      line=replace(line,"{{WEB_CREATED}}",ENVIRON["DT_W_CREATED"])
      print line
      if (line ~ /^type:[ \t]*/ && !classification_added) {
        if (ENVIRON["DT_W_ADD_AREA"] == "1") print "area: " ENVIRON["DT_W_AREA"]
        if (ENVIRON["DT_W_ADD_TOPIC"] == "1") print "topic: " ENVIRON["DT_W_TOPIC"]
        if (ENVIRON["DT_W_ADD_SOURCE_KIND"] == "1") print "source_kind: " ENVIRON["DT_W_SOURCE_KIND"]
        classification_added = 1
      }
    }
  ' "$tpl"
}

# 링크 자료실의 허브는 새 링크를 저장할 때만, 없는 파일에만 만든다. 기존
# 사용자가 직접 정리한 _index는 절대 덮어쓰지 않는다.
_cap_web_index_body() {
  local kind="$1" title="$2" from="$3" area="${4:-}" topic="${5:-}"
  case "$kind" in
    root)
      cat <<EOF
---
type: moc
scope: library-links
library_level: root
---

# 🔗 $(L '링크 자료실' 'Link library')

$(L 'URL만 저장하면 분야와 용도별로 정리됩니다. 아래 표와 폴더에서 바로 찾으세요.' 'Saved URLs are organized by area and purpose. Browse the folders or use the table below.')

## $(L '최근 저장한 링크' 'Recently saved links')

## $(L '분야별 자료실' 'Browse by area')

<!-- devtrail:link-library:areas:start -->

\`\`\`dataview
LIST file.link
FROM "$from"
WHERE scope = "library-links" AND library_level = "area"
SORT file.name ASC
\`\`\`

<!-- devtrail:link-library:areas:end -->

\`\`\`dataview
TABLE type AS "$(L '형태' 'Type')", area AS "$(L '분야' 'Area')", topic AS "$(L '주제' 'Topic')", source AS "$(L '출처' 'Source')", saved AS "$(L '저장일' 'Saved')"
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
    area)
      cat <<EOF
---
type: moc
scope: library-links
library_level: area
library_area: $area
---

# 🔗 $title

$(L '세부 용도 폴더를 열거나, 아래 표에서 자료를 바로 찾으세요.' 'Open a purpose folder or find a link directly in the table below.')

\`\`\`dataview
TABLE topic AS "$(L '주제' 'Topic')", type AS "$(L '형태' 'Type')", source AS "$(L '출처' 'Source')", saved AS "$(L '저장일' 'Saved')"
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
    *)
      cat <<EOF
---
type: moc
scope: library-links
library_level: topic
library_area: $area
library_topic: $topic
---

# 🔗 $title

\`\`\`dataview
TABLE type AS "$(L '형태' 'Type')", source AS "$(L '출처' 'Source')", saved AS "$(L '저장일' 'Saved')"
FROM "$from"
WHERE url
SORT saved DESC
\`\`\`
EOF
      ;;
  esac
}

# 이전 버전에서 만들어진 루트 자료실에는 분야별 허브 목록이 없다. 사용자가
# 직접 쓴 본문은 건드리지 않고, 전용 마커가 없을 때에만 목록 블록을 끝에
# 한 번 덧붙인다. 호출 시점은 항상 jr_begin 뒤라 undo로 원래 파일로 돌아간다.
_cap_web_ensure_root_navigation() {
  local file="$1" from="$2" tmp
  [ -f "$file" ] || return 0
  grep -qF '<!-- devtrail:link-library:areas:start -->' "$file" && return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-root.XXXXXX") || return 1
  cp "$file" "$tmp" || { rm -f "$tmp"; return 1; }
  cat >> "$tmp" <<EOF

## $(L '분야별 자료실' 'Browse by area')

<!-- devtrail:link-library:areas:start -->
\`\`\`dataview
LIST file.link
FROM "$from"
WHERE scope = "library-links" AND library_level = "area"
SORT file.name ASC
\`\`\`
<!-- devtrail:link-library:areas:end -->
EOF
  jr_backup "$file" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

_cap_web_write_index() {
  local abs="$1" rel="$2" kind="$3" title="$4" area="${5:-}" topic="${6:-}" file stage tmp
  file="$abs/_index.md"
  [ -f "$file" ] && return 0
  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-index.XXXXXX") || return 1
  _cap_web_index_body "$kind" "$title" "$(vault_rel "$rel")" "$area" "$topic" > "$stage" || { rm -f "$stage"; return 1; }
  tmp="$abs/.devtrail-index-$$.tmp"
  cp "$stage" "$tmp" && mv "$tmp" "$file" || { rm -f "$stage" "$tmp"; return 1; }
  rm -f "$stage"; jr_created "$file"
}

_cap_web() {
  local url="" apply=0 organize=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --url) shift; url="${1:-}" ;;
      --organize) organize=1 ;;
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  if [ "$organize" = 1 ]; then
    [ -z "$url" ] || die "$(L "링크 저장과 기존 링크 정리는 함께 실행할 수 없습니다" "Capture and organize cannot be used together")"
    _cap_web_organize "$apply"
    return
  fi
  require_config; require_bins jq
  [ -n "$url" ] || die "$(L "URL 이 필요합니다" "A URL is required"): --url \"https://…\""
  url=${url%%#*}
  _cap_web_safe_url "$url"; case $? in
    0) ;;
    2) die "$(L "내부·로컬 주소는 저장하지 않습니다" "Internal or local addresses are not accepted"): $url" ;;
    *) die "$(L "http 또는 https의 올바른 URL이 필요합니다" "A valid http or https URL is required"): $url" ;;
  esac

  local root inbox_rel library_rel links_rel rel dir trel tpl stage title="" description="" image="" canonical="" final_url="$url" site="" og_type="" now today file base slug n=2 dup fetch_rc source_host folder root_dir area_dir
  root=$(vault_root); rel=$(dt_dir inbox)
  [ -n "$rel" ] || die "$(L "자료실 Inbox 폴더가 설정에 없습니다" "The Library Inbox folder is not configured")"
  # Inbox는 기존 빠른 기록용으로 보존한다. 새 웹 링크만 같은 자료실 아래
  # 링크/분야/용도에 넣어, 과거 노트를 움직이지 않고도 관리 방식을 개선한다.
  inbox_rel="$rel"
  library_rel=${inbox_rel%/*}
  [ "$library_rel" = "$inbox_rel" ] && library_rel=""
  links_rel="${library_rel:+$library_rel/}$(L '링크' 'Links')"
  trel=$(dt_dir templates)
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
  _cap_web_classify "$final_url" "$source_host" "$title" "$description"
  folder=$(cap_taxonomy_folder "$CAP_WEB_AREA" "$CAP_WEB_TOPIC")
  rel="$links_rel/$folder"; dir="$root/$rel"
  root_dir="$root/$links_rel"; area_dir="$root/$links_rel/${folder%%/*}"
  today=$(date +%F); now=$(date '+%Y-%m-%d %H:%M')
  slug=$(_cap_slug "$title"); [ -n "$slug" ] || slug=$(_cap_slug "$source_host")
  [ -n "$slug" ] || slug="web-link"
  base="$dir/$today-$slug"; file="$base.md"

  info "  $(L "제목" "Title"): $title"
  info "  $(L "도메인" "Domain"): $source_host"
  info "  type: $CAP_WEB_TYPE"
  info "  $(L "분류" "Category"): $CAP_WEB_AREA / $CAP_WEB_TOPIC"
  info "  tags: $CAP_WEB_TAGS"
  [ -n "$site" ] && dim "   $(L "사이트" "Site"): $site"
  [ -n "$og_type" ] && dim "   OG type: $og_type"
  dup=$(_cap_web_existing "$root/${library_rel:-.}" "$url" "$canonical")
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
    dim "   $(L "자료실 허브" "Library indexes"): $links_rel/_index.md"
    dim "   $(L "(dry-run — 실제로 만들려면 --apply)" "(dry run — pass --apply to create it)")"
    dim "   $(L "적용" "Apply"): devtrail capture web --url \"$url\" --apply"
    return 0
  fi

  stage=$(mktemp "${TMPDIR:-/tmp}/devtrail-web-note.XXXXXX") || die "$(L "임시 파일을 만들지 못했습니다" "Could not create a temporary file")"
  _cap_render_web "$tpl" "$title" "$CAP_WEB_TYPE" "$CAP_WEB_TAGS" "$CAP_WEB_AREA" "$CAP_WEB_TOPIC" "$CAP_WEB_SOURCE_KIND" "$source_host" "$url" "$canonical" "$description" "$image" "$today" "$now" > "$stage" || { rm -f "$stage"; die "$(L "웹 링크 노트를 만들지 못했습니다" "Could not build the web link note")"; }
  [ -s "$stage" ] || { rm -f "$stage"; die "$(L "빈 노트가 나왔습니다" "The note came out empty")"; }
  grep -q '{{WEB_' "$stage" && { rm -f "$stage"; die "$(L "템플릿 값이 남았습니다" "A template value was left unresolved")"; }

  jr_begin capture-web
  jr_mkdir "$dir" || { rm -f "$stage"; jr_end; die "$(L "자료실 링크 폴더를 만들지 못했습니다" "Could not create the Library link folder")"; }
  _cap_web_write_index "$root_dir" "$links_rel" root "$(L '링크 자료실' 'Link library')" || { rm -f "$stage"; jr_end; die "$(L "링크 자료실 허브를 만들지 못했습니다" "Could not create the link library index")"; }
  _cap_web_ensure_root_navigation "$root_dir/_index.md" "$(vault_rel "$links_rel")" || { rm -f "$stage"; jr_end; die "$(L "링크 자료실 허브를 보완하지 못했습니다" "Could not update the link library index")"; }
  _cap_web_write_index "$area_dir" "$links_rel/${folder%%/*}" area "${folder%%/*}" "$CAP_WEB_AREA" || { rm -f "$stage"; jr_end; die "$(L "분야 허브를 만들지 못했습니다" "Could not create the area index")"; }
  _cap_web_write_index "$dir" "$rel" topic "${folder##*/}" "$CAP_WEB_AREA" "$CAP_WEB_TOPIC" || { rm -f "$stage"; jr_end; die "$(L "세부 분류 허브를 만들지 못했습니다" "Could not create the topic index")"; }
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

. "$DEVTRAIL_ROOT/lib/weborganize.sh"
