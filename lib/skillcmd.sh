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
    *) die "$(L "사용법" "Usage"): devtrail skills <install|sync|list|remove>" ;;
  esac
}

_sk_available() {
  [ -d "$DT_SKILL_SRC" ] || return 1
  find "$DT_SKILL_SRC" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

_sk_list() {
  step "$(L "DevTrail 스킬" "DevTrail skills")"
  local d name installed n=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    n=$((n + 1))
    if [ -d "$DT_SKILL_DEST/${DT_SKILL_PREFIX}${name}" ]; then
      installed="✅ $(L "설치됨" "installed")"
    else
      installed="—  $(L "미설치" "not installed")"
    fi
    printf '  %s  %-16s %s\n' "$installed" "$name" \
      "$(_sk_desc "$d/SKILL.md")"
  done <<EOF
$(_sk_available)
EOF
  [ "$n" = 0 ] && dim "   $(L "배포된 스킬이 없습니다" "No skills shipped")"
  echo
  if [ -d "$(dirname "$DT_SKILL_DEST")" ]; then
    dim "   $(L "설치 위치" "Installed at"): $DT_SKILL_DEST/${DT_SKILL_PREFIX}*"
  else
    dim "   $(L "Claude Code 가 없습니다 — 스킬은 선택 기능입니다" "No Claude Code — skills are optional")"
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
    warn "$(L "Claude Code 를 찾을 수 없습니다" "Cannot find Claude Code") ($HOME/.claude)"
    dim "   $(L "스킬은 선택 기능입니다. DevTrail 의 나머지는 그대로 동작합니다." \
            "Skills are optional. Everything else in DevTrail still works.")"
    return 0
  fi
  _sk_available >/dev/null || { warn "$(L "배포할 스킬이 없습니다" "No skills to install"): $DT_SKILL_SRC"; return 0; }

  mkdir -p "$DT_SKILL_DEST"
  step "$(L "스킬 설치" "Installing skills")"

  local d name dest n=0 kept=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    dest="$DT_SKILL_DEST/${DT_SKILL_PREFIX}${name}"

    if [ -d "$dest" ] && [ "$force" = 0 ]; then
      kept=$((kept + 1)); dim "   $(L "유지" "keep  ")  ${DT_SKILL_PREFIX}${name}"; continue
    fi
    # 우리 네임스페이스 밖은 절대 건드리지 않는다.
    case "$(basename "$dest")" in
      "${DT_SKILL_PREFIX}"*) ;;
      *) warn "$(L "네임스페이스 밖 — 건너뜀" "Outside our namespace — skipping"): $dest"; continue ;;
    esac
    rm -rf "$dest" && cp -R "$d" "$dest" || { warn "$(L "설치 실패" "Install failed"): $name"; continue; }
    n=$((n + 1)); ok "$(L "설치" "install")  ${DT_SKILL_PREFIX}${name}"
  done <<EOF
$(_sk_available)
EOF

  echo
  ok "$(L "${n}개 설치 · ${kept}개 유지" "${n} installed · ${kept} kept")"
  dim "   $(L "Claude Code 에서 /${DT_SKILL_PREFIX}<이름> 으로 실행합니다" \
            "Run them in Claude Code as /${DT_SKILL_PREFIX}<name>")"
  dim "   $(L "경로는 실행 시점에 devtrail path 로 조회합니다 — 설정을 바꿔도 재설치 불필요" \
            "Paths are resolved at run time via devtrail path — no reinstall after a config change")"
}

_sk_remove() {
  step "$(L "스킬 제거" "Removing skills")"
  local d name n=0
  for d in "$DT_SKILL_DEST/${DT_SKILL_PREFIX}"*; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    # 접두사 확인을 한 번 더 한다 — 글롭이 빗나가면 남의 스킬을 지운다.
    case "$name" in
      "${DT_SKILL_PREFIX}"*) rm -rf "$d" && { n=$((n + 1)); ok "$(L "제거" "remove ")  $name"; } ;;
      *) warn "$(L "접두사가 다릅니다 — 건너뜀" "Different prefix — skipping"): $name" ;;
    esac
  done
  [ "$n" = 0 ] && dim "   $(L "제거할 것이 없습니다" "Nothing to remove")"
  return 0
}
