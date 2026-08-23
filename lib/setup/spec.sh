#!/usr/bin/env bash
# DevTrail — 셋업 스펙: 검증 · 기본값 · 정규화.
#
# 스펙은 "무엇을 만들 것인가" 를 담은 JSON 하나다. 대화형 init 은 질문으로
# 이걸 만들고, 앱·CI 는 파일로 준다. 그다음은 같은 길이다.
#
# ⚠️ 적용 경로를 두 벌로 나누면 언젠가 한쪽만 고쳐진다. 2026-08-22 실물 QA 에서
#    잡은 결함 9건 중 4건이 그 유형이었다 — 같은 것이 두 곳에 있었다.
#    그래서 여기서 만든 스펙 하나만 setup_apply 로 흘려보낸다.
#
# ⚠️ 검증에 실패하면 아무것도 쓰지 않는다. 절반만 적용된 볼트가 최악이다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# 이 CLI 가 이해하는 스펙 버전.
#
# ⚠️ 앱과 CLI 의 버전이 어긋났을 때 '조용히 다르게 동작하는 것' 이 가장 나쁘다.
#    모르는 버전은 받지 않고 거절한다.
DT_SPEC_VERSION=1

# sp_validate <파일>  — 문제가 있으면 die. 출력 없음.
#
# ⚠️ 검증과 출력을 나눈 이유: 하나로 두면 호출자가 $(sp_read ...) 로 부르게
#    되고, 그러면 die 의 메시지가 명령 치환에 갇혀 사용자에게 아무것도
#    보이지 않는다 — 실제로 그랬다. 검증은 치환 밖에서 부른다.
sp_validate() {
  local f="$1"
  [ -n "$f" ] || die "$(L "스펙 파일이 필요합니다" "A spec file is required"): --input <file>"
  [ -f "$f" ] || die "$(L "스펙 파일이 없습니다" "No such spec file"): $f"

  jq -e . "$f" >/dev/null 2>&1 \
    || die "$(L "스펙이 유효한 JSON 이 아닙니다" "The spec is not valid JSON"): $f"

  local ver; ver=$(jq -r '.spec_version // empty' "$f")
  [ -n "$ver" ] \
    || die "$(L "spec_version 이 없습니다" "spec_version is missing"): $f
   $(L "이 CLI 는 spec_version ${DT_SPEC_VERSION} 을 씁니다" \
       "This CLI speaks spec_version ${DT_SPEC_VERSION}")"
  [ "$ver" = "$DT_SPEC_VERSION" ] \
    || die "$(L "모르는 spec_version" "Unknown spec_version"): $ver
   $(L "이 CLI 는 ${DT_SPEC_VERSION} 만 압니다. devtrail update 를 확인하세요." \
       "This CLI only speaks ${DT_SPEC_VERSION}. Check devtrail update.")"

  local vp; vp=$(jq -r '.vault.path // empty' "$f")
  [ -n "$vp" ] || die "$(L "vault.path 가 없습니다" "vault.path is missing"): $f"
  case "$vp" in
    /*) ;;
    *) die "$(L "vault.path 는 절대경로여야 합니다" "vault.path must be absolute"): $vp" ;;
  esac

  local mode; mode=$(jq -r '.vault.mode // "existing"' "$f")
  case "$mode" in
    new|existing|isolated) ;;
    *) die "$(L "모르는 설치 방식" "Unknown install mode"): $mode  (new|existing|isolated)" ;;
  esac

  local lang; lang=$(jq -r '.lang // "ko"' "$f")
  case "$lang" in ko|en) ;; *) lang=ko ;; esac

  return 0
}

# sp_normalize <파일>  → 완전한 스펙을 stdout 으로. sp_validate 를 통과한 뒤 부른다.
sp_normalize() {
  local f="$1"
  local lang; lang=$(jq -r '.lang // "ko"' "$f")
  case "$lang" in ko|en) ;; *) lang=ko ;; esac
  local mode; mode=$(jq -r '.vault.mode // "existing"' "$f")

  # 빠진 값에 기본을 채워 '완전한 스펙' 을 낸다. 적용부는 없는 값을 걱정하지
  # 않아도 된다 — 기본값이 적용부에 흩어지면 그게 곧 두 번째 출처가 된다.
  jq --arg lang "$lang" --arg mode "$mode" --argjson v "$DT_SPEC_VERSION" '{
    spec_version: $v,
    lang: $lang,
    vault: {
      backend: (.vault.backend // "local"),
      path:    .vault.path,
      root:    (.vault.root // ""),
      mode:    $mode
    },
    dirs:    (.dirs // {}),
    modules: (if (.modules | type) == "array" and (.modules | length) > 0
              then .modules else ["devlog"] end),
    github: {
      user:           (.github.user // ""),
      src_root:       (.github.src_root // ""),
      repos:          (.github.repos // []),
      project_groups: (.github.project_groups // {})
    },
    ai: { provider: (.ai.provider // "none") },
    bootstrap_plugins: (if .bootstrap_plugins == false then false else true end)
  }' "$f"
}

# sp_from_quick → 최소 입력(언어·볼트·모드)만으로 스펙을.
#
# ⚠️ 앱의 간단 온보딩이 타는 길이다 (ADR 0006 M4-4c).
#
#    비개발자에게 터미널 대화를 강요하지 않으려면 앱이 질문을 받아야 하는데,
#    **앱이 스펙 JSON 을 직접 조립하면 안 된다** — 그러면 스펙의 모양이 두
#    벌이 되고, 이 저장소가 반복해 겪은 결함이 그대로 재현된다.
#
#    그래서 앱은 값 세 개만 넘기고, 스펙은 여기서 만든다. 빠진 값은
#    sp_normalize 가 채운다 — 기본값의 출처도 한 곳이다.
#
# ⚠️ **플러그인은 받지 않는다** (bootstrap_plugins: false).
#
#    두 가지 이유다.
#
#    1) 플러그인 설치는 GitHub 에서 **내려받는다.** 사용자 승인 없는 네트워크
#       요청을 하지 않는 것이 이 프로젝트의 약속이다. 간단 셋업이라고 해서
#       조용히 네 개를 받아오면 안 된다.
#    2) 대화형 경로는 여기서 **묻는다**(`confirm`). 터미널이 붙어 있으면
#       답을 기다리고, 없으면 조용히 건너뛴다 — 즉 **tty 유무로 결과가
#       갈린다.** 앱이 부르는 길에 그런 불확정성을 두지 않는다.
#
#    앱은 셋업을 마친 뒤 `devtrail plugins install` 을 **따로** 권한다.
sp_from_quick() {
  local lang="$1" vault="$2" mode="$3"
  jq -n \
    --argjson v "$DT_SPEC_VERSION" \
    --arg lang "$lang" \
    --arg path "$vault" \
    --arg mode "$mode" \
    '{
       spec_version: $v,
       lang: $lang,
       vault: { backend: "local", path: $path, root: "", mode: $mode },
       bootstrap_plugins: false
     }'
}

# sp_from_init  → 대화형 수집 결과(전역)를 스펙으로.
#
# ⚠️ 여기가 대화형과 비대화형이 만나는 지점이다. 질문이 늘면 이 함수도
#    같이 고쳐야 한다 — 그래야 앱이 그 질문의 결과를 줄 수 있다.
sp_from_init() {
  local backend="$1" vault="$2" root="$3" gh_user="$4" ai="$5"
  jq -n --argjson v "$DT_SPEC_VERSION" \
    --arg lang "${DT_LANG:-ko}" --arg backend "$backend" --arg vault "$vault" \
    --arg root "$root" --arg mode "${DT_MODE:-existing}" \
    --argjson dirs "${DT_DIRS:-\{\}}" \
    --argjson modules "$(_dt_json_array "${DT_MODULES:-devlog}")" \
    --arg gh "$gh_user" --arg src "${DT_SRC_ROOT:-}" \
    --argjson repos "$(_dt_json_array "${DT_SYNC_REPOS:-}")" \
    --argjson projects "$(_dt_json_array "${DT_PROJECTS:-}")" \
    --argjson groups "$(_dt_json_identity "${DT_PROJECTS:-}")" \
    --arg ai "$ai" \
    --argjson boot "$([ "${DT_BOOTSTRAP:-1}" = 1 ] && echo true || echo false)" '{
      spec_version: $v, lang: $lang,
      vault: { backend: $backend, path: $vault, root: $root, mode: $mode },
      dirs: $dirs,
      modules: $modules,
      github: { user: $gh, src_root: $src, repos: $repos,
                project_groups: $groups, sync_repos: $repos, projects: $projects },
      ai: { provider: $ai },
      bootstrap_plugins: $boot
    }'
}

# 스펙을 적용부가 읽는 전역으로 푼다.
#
# ⚠️ 전역을 쓰는 이유: 적용 단계(_init_write_config 등)가 이미 전역을 읽는다.
#    거기까지 한 번에 바꾸면 이 변경이 커져 검증이 어려워진다. 대신 '전역을
#    채우는 곳' 을 여기 한 군데로 모아, 앱 경로에서 전역이 비는 사고를 막는다.
sp_export() {
  local spec="$1"
  DT_LANG=$(printf '%s' "$spec"    | jq -r '.lang')
  DT_MODE=$(printf '%s' "$spec"    | jq -r '.vault.mode')
  DT_DIRS=$(printf '%s' "$spec"    | jq -c '.dirs')
  DT_MODULES=$(printf '%s' "$spec" | jq -r '.modules | join("\n")')
  DT_SRC_ROOT=$(printf '%s' "$spec" | jq -r '.github.src_root')
  DT_SYNC_REPOS=$(printf '%s' "$spec" | jq -r '(.github.sync_repos // .github.repos) | join("\n")')
  DT_PROJECTS=$(printf '%s' "$spec" | jq -r '
    if (.github.projects | type) == "array" then .github.projects
    else (.github.project_groups | keys) end | join("\n")')
  DT_BOOTSTRAP=$(printf '%s' "$spec" | jq -r 'if .bootstrap_plugins then 1 else 0 end')
  DEVTRAIL_LANG="$DT_LANG"
  export DT_LANG DT_MODE DT_DIRS DT_MODULES DT_SRC_ROOT DT_SYNC_REPOS \
         DT_PROJECTS DT_BOOTSTRAP DEVTRAIL_LANG
}
