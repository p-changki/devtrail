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

# 이 경로가 **떼어낼 수 있는 읽기전용 볼륨**(마운트된 디스크 이미지) 위에 있나.
#
# ⚠️ 왜 필요한가 (2026-08-24 실물 QA)
#
#    DMG 를 열면 앱이 /Volumes/… 에서 그대로 **잘 돈다.** 설치된 줄 알기 쉽다.
#    그 상태에서 터미널 연결을 만들면 링크가 DMG 안을 가리키고, **DMG 를 빼는
#    순간 죽는다.** 더 나쁜 것은 그 다음이다 — 나중에 제대로 설치하고 다시
#    눌러도, 끊어진 링크를 "남의 것" 으로 보고 거부해 **영영 못 고친다.**
#
# ⚠️ `/` 도 read-only 다(봉인된 시스템 볼륨). 그래서 두 조건을 함께 본다:
#    /Volumes/ 아래일 것 **그리고** 그 볼륨이 read-only 일 것.
#    /Applications 는 어느 쪽도 아니라 걸리지 않는다.
_link_on_readonly_volume() {
  case "$1" in
    /Volumes/*) ;;
    *) return 1 ;;
  esac
  local rest vol
  rest="${1#/Volumes/}"
  vol="/Volumes/$(printf '%s' "$rest" | cut -d/ -f1)"
  mount | grep -F " on $vol (" | grep -q 'read-only'
}

# absent | linked_here | linked_other | broken | occupied
_link_state() {
  if [ ! -e "$DT_LINK_PATH" ] && [ ! -L "$DT_LINK_PATH" ]; then
    printf 'absent'; return
  fi
  if [ ! -L "$DT_LINK_PATH" ]; then
    # ⚠️ 심볼릭 링크가 아닌 진짜 파일이다. 누가 어떻게 놓았는지 모른다.
    printf 'occupied'; return
  fi
  # ⚠️ **끊어진 링크는 "남의 것" 이 아니다.** 아무것도 가리키지 않는 죽은
  #    링크이고, 그대로 두면 터미널 devtrail 이 계속 안 된다. 이걸
  #    linked_other 로 보면 create 가 거부해서 사용자가 영영 못 고친다
  #    (2026-08-24 실물 QA 에서 이 기계가 정확히 그 상태였다).
  [ -e "$DT_LINK_PATH" ] || { printf 'broken'; return; }
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
  case "$state" in
    linked_here|linked_other|broken) target=$(_link_resolve "$DT_LINK_PATH") ;;
    occupied) target="$DT_LINK_PATH" ;;
  esac

  # ⚠️ 판정은 여기서 한다. 화면은 이 값을 읽어 그리기만 한다.
  local ro=false
  _link_on_readonly_volume "$(_link_self)" && ro=true

  if [ "${1:-}" = "--json" ]; then
    jq -n \
      --arg state "$state" \
      --arg path "$DT_LINK_PATH" \
      --arg self "$(_link_self)" \
      --arg target "$target" \
      --argjson on_path "$on_path" \
      --argjson self_readonly "$ro" \
      '{ state: $state, path: $path, self: $self, target: $target,
         on_path: $on_path, self_readonly: $self_readonly }'
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
    broken)
      warn "$(L "연결이 끊어져 있습니다" "The link is broken"): $DT_LINK_PATH → $target"
      dim "   devtrail link create   ($(L "다시 연결합니다" "relinks"))" ;;
    absent)
      dim "$(L "터미널에 연결돼 있지 않습니다" "Not linked for the terminal"): $DT_LINK_PATH"
      dim "   devtrail link create" ;;
  esac
  [ "$ro" = true ] && {
    warn "$(L "떼어낼 수 있는 볼륨에서 실행 중입니다" "Running from a removable volume"): $(_link_self)"
    dim "   $(L "먼저 응용 프로그램 폴더로 옮기세요 — 지금 연결하면 볼륨을 빼는 순간 끊어집니다." \
                "Move it to Applications first — a link made now dies when the volume is ejected.")"
  }
  [ "$on_path" = false ] && {
    warn "$(L "PATH 에 없습니다" "Not on PATH"): $DT_LINK_DIR"
    dim "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  }
  return 0
}

_link_create() {
  local state; state=$(_link_state)

  # ⚠️ **떼어낼 수 있는 볼륨에서는 만들지 않는다.** 만들어도 볼륨을 빼는
  #    순간 죽고, 죽은 링크는 사용자가 스스로 고치기 어렵다. 만들기 전에
  #    막는 편이 훨씬 싸다.
  if _link_on_readonly_volume "$(_link_self)"; then
    die "$(L "떼어낼 수 있는 볼륨에서는 연결하지 않습니다 — 먼저 응용 프로그램 폴더로 옮기세요" \
            "Not linking from a removable volume — move it to Applications first"): $(_link_self)"
  fi

  # ⚠️ 덮어쓰지 않는다. 여기서 -f 를 쓰면 사용자가 쓰던 devtrail 이 말없이
  #    바뀐다 — 되돌릴 방법도 알려주지 못한다.
  case "$state" in
    linked_here)
      ok "$(L "이미 연결돼 있습니다" "Already linked"): $DT_LINK_PATH"
      return 0 ;;
    broken)
      # ⚠️ 끊어진 링크는 아무것도 안 가리킨다. 이건 "남의 것" 이 아니라
      #    **고쳐야 할 것**이다. 지우고 다시 만든다.
      rm -f "$DT_LINK_PATH" || die "$(L "끊어진 링크를 지우지 못했습니다" \
                                       "Could not remove the broken link"): $DT_LINK_PATH" ;;
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
