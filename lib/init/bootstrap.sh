#!/usr/bin/env bash
# DevTrail — init: Obsidian 을 사용할 수 있는 상태로 만든다.
#
# 예전 셋업은 여기서 사용자를 GUI 로 내보냈다:
#   "Obsidian 에서 볼트를 열고 → 플러그인 4개 깔고 → 재시작한 뒤 → 다시 오세요"
# 터미널 ↔ GUI 왕복이 셋업에서 가장 큰 마찰이었다.
#
# 이 파일이 그 왕복을 없앤다:
#   1. .obsidian/ 을 만든다            (그냥 폴더다)
#   2. 플러그인을 받아 넣고 켠다        (동의 후)
#   3. Obsidian 레지스트리에 등록한다   (볼트 목록에 뜨게)
#   4. 설정을 병합한다                 (devtrail obsidian)
#   5. Obsidian 을 연다                (완성된 상태로)
#
# 실패해도 셋업 전체를 죽이지 않는다. 여기서 죽으면 사용자는 설정 파일만
# 남고 아무 안내도 못 받는다 — 무엇이 안 됐는지 말하고 넘어가는 게 낫다.
#
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# 결과를 호출자에게 알린다. _init_next_steps 가 무엇을 안내할지 정할 때 쓴다.
DT_BOOT_PLUGINS=skip     # ok | failed | skip
DT_BOOT_OPENED=0

# Obsidian 이 실행 중이면 레지스트리를 못 쓴다 — 종료할 때 자기 상태로
# 덮어쓰기 때문이다. 볼트 등록만 포기하고 나머지는 그대로 한다.
_init_boot_registry() {
  local vault="$1"
  if oa_running; then
    warn "$(L "Obsidian 이 실행 중이라 볼트 등록을 건너뜁니다" \
            "Obsidian is running, so vault registration is skipped")"
    dim "   $(L "Obsidian 을 종료한 뒤" "Quit Obsidian, then"): devtrail obsidian"
    return 1
  fi
  oa_register "$vault" && return 0
  warn "$(L "볼트 등록 실패 — Obsidian 에서 직접 열어야 합니다" \
          "Could not register the vault — you will have to open it in Obsidian yourself")"
  return 1
}

# init_bootstrap <볼트경로>
init_bootstrap() {
  local vault="$1"
  . "$DEVTRAIL_ROOT/lib/obsidian_app.sh"
  . "$DEVTRAIL_ROOT/lib/plugins.sh"

  echo
  step "$(L "Obsidian 준비" "Preparing Obsidian")"

  if ! oa_installed; then
    warn "$(L "Obsidian 이 설치돼 있지 않습니다" "Obsidian is not installed")"
    dim "   https://obsidian.md/download"
    dim "   $(L "설치한 뒤" "After installing"): devtrail obsidian"
    return 0
  fi

  jr_begin init-bootstrap

  # 1. .obsidian/
  if oa_ensure_dot "$vault"; then
    ok "$(L "Obsidian 설정 폴더" "Obsidian config folder"): .obsidian/"
  else
    warn "$(L "Obsidian 설정 폴더를 만들지 못했습니다" "Could not create the Obsidian config folder")"
    jr_end
    return 0
  fi

  # 2. 플러그인
  if pl_install "$vault/.obsidian"; then
    DT_BOOT_PLUGINS=ok
  else
    DT_BOOT_PLUGINS=failed
  fi

  # 3. 레지스트리
  _init_boot_registry "$vault" && ok "$(L "Obsidian 볼트 목록에 등록" "Registered in Obsidian's vault list")"

  jr_end
  return 0
}

# 설정 병합 + 열기. 설정 파일이 저장된 '뒤에' 불러야 한다 —
# obsidian_apply 가 require_config 를 한다.
init_bootstrap_apply() {
  local vault="$1"
  oa_installed || return 0

  echo
  # 같은 셸에서 obsidian.sh 를 읽으면 DT_MERGERS 등 전역이 섞인다.
  # 서브셸로 격리한다 — 여기서 실패해도 셋업 요약은 나와야 한다.
  ( . "$DEVTRAIL_ROOT/lib/obsidian.sh"; obsidian_apply ) || {
    warn "$(L "Obsidian 설정 병합에 실패했습니다" "Merging Obsidian settings failed")"
    dim "   $(L "다시" "Retry"): devtrail obsidian"
    return 0
  }

  echo
  if confirm "$(L "Obsidian 을 지금 열까요?" "Open Obsidian now?")"; then
    oa_open "$vault" && DT_BOOT_OPENED=1
  fi
  return 0
}
