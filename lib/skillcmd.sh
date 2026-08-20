#!/usr/bin/env bash
# DevTrail — `devtrail skills <install|sync|list|remove>`
#
# DevTrail 소유의 AI 스킬을 Claude Code 에 설치한다.
#
# ⚠️ 개인 ~/.claude 설정을 복사하는 게 아니다. DevTrail 이 소유한 스킬을
#    devtrail-* 네임스페이스로 설치한다. 사용자의 기존 스킬과 섞이지 않고,
#    remove 로 깨끗이 지울 수 있다.
#
# ⚠️ 스킬 본문에 경로를 박지 않는다. 실행 시점에 `devtrail path` 로 조회한다.
#    설정을 바꿔도 재설치가 필요 없어야 한다 — 스크립트와 같은 원칙이다.
#
# Claude Code 가 없어도 DevTrail 은 그대로 동작한다. 스킬은 선택 기능이다.

DT_SKILL_SRC="${DEVTRAIL_ROOT}/skills"
DT_SKILL_DEST="${DEVTRAIL_SKILL_DIR:-$HOME/.claude/skills}"
DT_SKILL_PREFIX="devtrail-"

skills_cmd() {
  case "${1:-list}" in
    install) shift; _sk_install "$@" ;;
    sync)    shift; _sk_install --force "$@" ;;
    list)    _sk_list ;;
    remove)  _sk_remove ;;
    *) die "사용법: devtrail skills <install|sync|list|remove>" ;;
  esac
}

_sk_available() {
  [ -d "$DT_SKILL_SRC" ] || return 1
  find "$DT_SKILL_SRC" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

_sk_list() {
  step "DevTrail 스킬"
  local d name installed n=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    n=$((n + 1))
    if [ -d "$DT_SKILL_DEST/${DT_SKILL_PREFIX}${name}" ]; then
      installed="✅ 설치됨"
    else
      installed="—  미설치"
    fi
    printf '  %s  %-16s %s\n' "$installed" "$name" \
      "$(_sk_desc "$d/SKILL.md")"
  done <<EOF
$(_sk_available)
EOF
  [ "$n" = 0 ] && dim "   배포된 스킬이 없습니다"
  echo
  if [ -d "$(dirname "$DT_SKILL_DEST")" ]; then
    dim "   설치 위치: $DT_SKILL_DEST/${DT_SKILL_PREFIX}*"
  else
    dim "   Claude Code 가 없습니다 — 스킬은 선택 기능입니다"
  fi
}

_sk_desc() {
  [ -f "$1" ] || { printf '%s' ''; return 0; }
  sed -n 's/^description: *//p' "$1" | head -1 | cut -c1-52
}

_sk_install() {
  local force=0
  [ "${1:-}" = "--force" ] && { force=1; shift; }

  if [ ! -d "$(dirname "$DT_SKILL_DEST")" ]; then
    warn "Claude Code 를 찾을 수 없습니다 ($HOME/.claude)"
    dim "   스킬은 선택 기능입니다. DevTrail 의 나머지는 그대로 동작합니다."
    return 0
  fi
  _sk_available >/dev/null || { warn "배포할 스킬이 없습니다: $DT_SKILL_SRC"; return 0; }

  mkdir -p "$DT_SKILL_DEST"
  step "스킬 설치"

  local d name dest n=0 kept=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    dest="$DT_SKILL_DEST/${DT_SKILL_PREFIX}${name}"

    if [ -d "$dest" ] && [ "$force" = 0 ]; then
      kept=$((kept + 1)); dim "   유지  ${DT_SKILL_PREFIX}${name}"; continue
    fi
    # 우리 네임스페이스 밖은 절대 건드리지 않는다.
    case "$(basename "$dest")" in
      "${DT_SKILL_PREFIX}"*) ;;
      *) warn "네임스페이스 밖 — 건너뜀: $dest"; continue ;;
    esac
    rm -rf "$dest" && cp -R "$d" "$dest" || { warn "설치 실패: $name"; continue; }
    n=$((n + 1)); ok "설치  ${DT_SKILL_PREFIX}${name}"
  done <<EOF
$(_sk_available)
EOF

  echo
  ok "${n}개 설치 · ${kept}개 유지"
  dim "   Claude Code 에서 /${DT_SKILL_PREFIX}<이름> 으로 실행합니다"
  dim "   경로는 실행 시점에 devtrail path 로 조회합니다 — 설정을 바꿔도 재설치 불필요"
}

_sk_remove() {
  step "스킬 제거"
  local d name n=0
  for d in "$DT_SKILL_DEST/${DT_SKILL_PREFIX}"*; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    # 접두사 확인을 한 번 더 한다 — 글롭이 빗나가면 남의 스킬을 지운다.
    case "$name" in
      "${DT_SKILL_PREFIX}"*) rm -rf "$d" && { n=$((n + 1)); ok "제거  $name"; } ;;
      *) warn "접두사가 다릅니다 — 건너뜀: $name" ;;
    esac
  done
  [ "$n" = 0 ] && dim "   제거할 것이 없습니다"
  return 0
}
