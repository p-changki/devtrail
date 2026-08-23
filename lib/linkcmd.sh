#!/usr/bin/env bash
# DevTrail — `devtrail link <status|create>`
#
# 앱(.app)으로 설치한 사람이 **터미널에서도** devtrail 을 쓰게 해 준다.
#
# ⚠️ 왜 필요한가 (ADR 0006 M4-4b)
#
#    DMG 로 받은 사람의 기계에는 PATH 에 devtrail 이 없다. 앱은 번들 안의
#    CLI 를 절대경로로 부르니 잘 돌지만, 그 사람이 터미널에서
#    `devtrail activity` 를 치면 **없다.** DMG 사용자가 만나는 첫 번째 벽이다.
#
# ⚠️ **덮어쓰지 않는다** (D4 공존).
#
#    이미 devtrail 이 설치돼 있으면 그건 그 사람이 만든 것이다. 앱이 자기
#    것으로 바꿔치기하면, 터미널에서 쓰던 버전이 말없이 달라진다. 우리는
#    상태를 **말해 줄 뿐** 손대지 않는다.
#
# ⚠️ 로직은 여기 있고 UI 에는 없다. 앱은 `link status --json` 을 읽어
#    그리기만 한다.

DT_LINK_DIR="${DEVTRAIL_BIN_DIR:-$HOME/.local/bin}"
DT_LINK_PATH="$DT_LINK_DIR/devtrail"

link_cmd() {
  case "${1:-status}" in
    status) shift; _link_status "$@" ;;
    create) shift; _link_create "$@" ;;
    *) die "$(L "사용법" "Usage"): devtrail link <status|create>" ;;
  esac
}

# 우리가 가리켜야 할 실행 파일.
_link_self() { printf '%s' "$DEVTRAIL_ROOT/bin/devtrail"; }

# ⚠️ 심볼릭 링크를 **따라가서** 최종 목적지를 본다. 한 단계만 읽으면
#    링크가 링크를 가리킬 때 틀린 답을 낸다.
_link_resolve() {
  local p="$1" n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    local t; t=$(readlink "$p")
    case "$t" in
      /*) p="$t" ;;
      *)  p="$(dirname "$p")/$t" ;;
    esac
    n=$((n + 1))
  done
  # 경로를 정규화한다 (../ 가 섞여 있으면 비교가 어긋난다).
  if [ -e "$p" ]; then (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$p")")
  else printf '%s' "$p"; fi
}

# absent | linked_here | linked_other | occupied
_link_state() {
  if [ ! -e "$DT_LINK_PATH" ] && [ ! -L "$DT_LINK_PATH" ]; then
    printf 'absent'; return
  fi
  if [ ! -L "$DT_LINK_PATH" ]; then
    # ⚠️ 심볼릭 링크가 아닌 진짜 파일이다. 누가 어떻게 놓았는지 모른다.
    printf 'occupied'; return
  fi
  local got want
  got=$(_link_resolve "$DT_LINK_PATH")
  want=$(_link_resolve "$(_link_self)")
  [ "$got" = "$want" ] && printf 'linked_here' || printf 'linked_other'
}

# ~/.local/bin 이 PATH 에 있는가. 없으면 링크를 만들어도 소용이 없다.
_link_on_path() {
  case ":$PATH:" in
    *":$DT_LINK_DIR:"*) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

_link_status() {
  local state target on_path
  state=$(_link_state)
  on_path=$(_link_on_path)
  target=""
  [ "$state" = linked_here ] || [ "$state" = linked_other ] \
    && target=$(_link_resolve "$DT_LINK_PATH")
  [ "$state" = occupied ] && target="$DT_LINK_PATH"

  if [ "${1:-}" = "--json" ]; then
    jq -n \
      --arg state "$state" \
      --arg path "$DT_LINK_PATH" \
      --arg self "$(_link_self)" \
      --arg target "$target" \
      --argjson on_path "$on_path" \
      '{ state: $state, path: $path, self: $self, target: $target, on_path: $on_path }'
    return 0
  fi

  case "$state" in
    linked_here)
      ok "$(L "터미널에 연결돼 있습니다" "Linked for the terminal"): $DT_LINK_PATH" ;;
    linked_other)
      warn "$(L "다른 devtrail 이 연결돼 있습니다" "A different devtrail is linked"): $target"
      dim "   $(L "그대로 둡니다. 앱은 번들 안의 것을 씁니다 — 둘은 공존합니다." \
                  "Left as is. The app uses its bundled copy — they coexist.")" ;;
    occupied)
      warn "$(L "이미 파일이 있습니다" "A file is already there"): $DT_LINK_PATH"
      dim "   $(L "심볼릭 링크가 아니라 손대지 않습니다." "Not a symlink — left untouched.")" ;;
    absent)
      dim "$(L "터미널에 연결돼 있지 않습니다" "Not linked for the terminal"): $DT_LINK_PATH"
      dim "   devtrail link create" ;;
  esac
  [ "$on_path" = false ] && {
    warn "$(L "PATH 에 없습니다" "Not on PATH"): $DT_LINK_DIR"
    dim "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  }
  return 0
}

_link_create() {
  local state; state=$(_link_state)

  # ⚠️ 덮어쓰지 않는다. 여기서 -f 를 쓰면 사용자가 쓰던 devtrail 이 말없이
  #    바뀐다 — 되돌릴 방법도 알려주지 못한다.
  case "$state" in
    linked_here)
      ok "$(L "이미 연결돼 있습니다" "Already linked"): $DT_LINK_PATH"
      return 0 ;;
    linked_other)
      die "$(L "다른 devtrail 이 이미 연결돼 있습니다 — 덮어쓰지 않습니다" \
              "A different devtrail is already linked — not overwriting"): $(_link_resolve "$DT_LINK_PATH")" ;;
    occupied)
      die "$(L "이미 파일이 있습니다 — 덮어쓰지 않습니다" \
              "A file is already there — not overwriting"): $DT_LINK_PATH" ;;
  esac

  local self; self=$(_link_self)
  [ -x "$self" ] || die "$(L "연결할 실행 파일이 없습니다" "Nothing to link"): $self"

  mkdir -p "$DT_LINK_DIR" || die "$(L "디렉터리를 만들지 못했습니다" "Could not create directory"): $DT_LINK_DIR"
  ln -s "$self" "$DT_LINK_PATH" || die "$(L "연결하지 못했습니다" "Could not link"): $DT_LINK_PATH"

  ok "$(L "연결했습니다" "Linked"): $DT_LINK_PATH → $self"
  [ "$(_link_on_path)" = false ] && {
    warn "$(L "PATH 에 없습니다" "Not on PATH"): $DT_LINK_DIR"
    dim "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  }
  return 0
}
