#!/usr/bin/env bash
# DevTrail — `devtrail doctor`
# 설치·인증·권한·자동화 상태를 진단한다.
#
# 원칙: 확인하지 못한 것을 "정상"이라고 말하지 않는다.
#       검증 불가한 항목은 '❔ 확인 불가'로 표시하고 확인 방법을 알려준다.

# 카운터는 전역이다. 헬퍼가 지역변수를 올릴 수 없어 집계가 0으로 나오는
# 버그가 있었다(2026-08-20). 헬퍼에서 직접 올리도록 통일한다.
DT_FAILS=0
DT_WARNS=0
_d_fail() { fail "$*"; DT_FAILS=$((DT_FAILS+1)); }
_d_warn() { warn "$*"; DT_WARNS=$((DT_WARNS+1)); }

doctor_run() {
  DT_FAILS=0; DT_WARNS=0

  _d_section "의존성"
  _d_bin jq        required "설정 파일 파싱 — 없으면 아무것도 동작하지 않음"
  _d_bin gh        required "GitHub PR/이슈 조회"
  _d_bin git       required "볼트 백업"
  _d_bin rsync     required "문서 동기화"
  _d_bin python3   required "볼트 백업(권한 우회 경유)"
  _d_bin fswatch   optional "실시간 파일 감시 (미설치 시 주기 동기화만)"

  local ai; ai=$(cfg '.ai.provider' 'claude')
  if [ "$(cfg '.ai.summary_enabled' 'true')" = "true" ]; then
    _d_bin "$ai" required "PR 쉬운말 요약 (ai.provider=$ai)"
  else
    dim "   ai.summary_enabled=false — AI 요약 비활성"
  fi

  _d_section "인증"
  if has gh; then
    if gh auth status >/dev/null 2>&1; then
      ok "gh 인증됨 ($(gh api user --jq .login 2>/dev/null || echo '?'))"
    else
      _d_fail "gh 미인증 → 'gh auth login' 실행 필요"
    fi
  fi

  if [ "$(cfg '.linear.enabled' 'false')" = "true" ]; then
    local svc; svc=$(cfg '.linear.keychain_service')
    if security find-generic-password -s "$svc" >/dev/null 2>&1; then
      ok "Linear API 키 있음 (keychain: $svc)"
    else
      _d_warn "Linear 활성인데 키체인에 키 없음 → Linear 항목은 조용히 스킵됨"
    fi
  else
    dim "   Linear 비활성 (선택 기능)"
  fi

  _d_section "볼트"
  local vp vr; vp=$(vault_path); vr=$(vault_root)
  if [ -z "$vp" ]; then
    _d_fail "볼트 경로 미설정 → 'devtrail init'"
  elif [ ! -d "$vp" ]; then
    _d_fail "볼트 경로 없음: $vp"
  else
    ok "볼트 존재: $vp"
    [ -d "$vr" ] && ok "루트 폴더: $(cfg '.vault.root')" \
                 || { _d_warn "루트 폴더 없음: $vr"; }
    _d_plugins "$vp"
  fi

  local backend; backend=$(cfg '.vault.backend' 'local')
  case "$backend" in
    icloud) _d_icloud "$vp";  ;;
    gdrive) _d_warn "Google Drive 백엔드는 MVP에서 미검증 — 스트리밍 모드면 파일이 로컬에 없을 수 있음" ;;
    local)  dim "   로컬 저장소 — 클라우드 권한 이슈 없음" ;;
  esac

  _d_section "자동화"
  _d_launchd "com.devtrail.daily"    "매일 $(cfg '.schedule.daily_hour' '10')시"
  _d_launchd "com.devtrail.repodocs" "$(cfg '.schedule.repodocs_interval_sec' '600')초 간격"

  _d_section "AI 스킬"
  if [ -d "$HOME/.claude/skills" ]; then
    local have want
    want=$(find "$DEVTRAIL_ROOT/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    have=$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d -name 'devtrail-*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${have:-0}" -eq "${want:-0}" ] && [ "${want:-0}" -gt 0 ]; then
      ok "스킬 ${have}/${want} 설치됨"
    elif [ "${have:-0}" -gt 0 ]; then
      _d_warn "스킬 ${have}/${want} — 일부 누락 → 'devtrail skills sync'"
    else
      dim "   스킬 미설치 (선택) → 'devtrail skills install'"
    fi
  else
    dim "   Claude Code 없음 — 스킬은 선택 기능입니다"
  fi

  _d_section "요약"
  # 요약 줄은 집계 결과를 '보고'만 한다 — _d_fail/_d_warn을 쓰면 자기 자신을
  # 한 번 더 세어 숫자가 틀어진다.
  if [ "$DT_FAILS" -gt 0 ]; then
    fail "차단 ${DT_FAILS}건 · 경고 ${DT_WARNS}건 — 위 ❌ 항목을 먼저 해결하세요"
    return 1
  elif [ "$DT_WARNS" -gt 0 ]; then
    warn "차단 없음 · 경고 ${DT_WARNS}건 — 동작하지만 일부 기능이 빠집니다"
    return 0
  fi
  ok "모든 항목 정상"
}

# ── helpers ──────────────────────────────────────────────────────────────────
_d_section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }

_d_bin() {
  local bin="$1" mode="$2" why="$3"
  if has "$bin"; then
    ok "$bin"
  elif [ "$mode" = required ]; then
    _d_fail "$bin 없음 — $why"
    return 1
  else
    _d_warn "$bin 없음 (선택) — $why"
  fi
}

# 필수 = DevTrail이 실제로 의존하는 것만 넣는다.
#   obsidian-shellcommands : Obsidian에서 스크립트를 실행하는 통로
#   templater-obsidian     : 개발일지를 템플릿으로 생성(활동 삽입의 전제)
#   dataview               : 주간리뷰 노트는 본문 전체가 Dataview 쿼리다.
#                            없으면 주간리뷰가 빈 코드블록으로만 보인다.
#
# auto-note-mover 는 필수에서 뺐다. DevTrail 코드가 이 플러그인을 전혀 쓰지
# 않는데 없다고 ❌ 를 띄우면, 진짜 차단 항목과 구분이 안 된다.
_d_plugins() {
  local vp="$1" pf="$1/.obsidian/community-plugins.json"
  local need=(obsidian-shellcommands templater-obsidian dataview)
  local nice=(auto-note-mover)
  if [ ! -f "$pf" ]; then
    _d_warn "Obsidian 설정 없음 (.obsidian/community-plugins.json) — 볼트를 한 번 열어야 생성됩니다"
    return
  fi
  local missing=() p
  for p in "${need[@]}"; do
    jq -e --arg p "$p" 'index($p)' "$pf" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "필수 플러그인 ${#need[@]}/${#need[@]}"
  else
    _d_fail "플러그인 누락: ${missing[*]}"
    case " ${missing[*]} " in
      *" dataview "*) dim "     dataview 없이도 나머지는 돌지만 주간리뷰가 빈 화면이 됩니다" ;;
    esac
  fi
  for p in "${nice[@]}"; do
    jq -e --arg p "$p" 'index($p)' "$pf" >/dev/null 2>&1 \
      || dim "   $p 없음 (선택) — DevTrail은 쓰지 않습니다. 노트 자동 정리용"
  done
}

# iCloud + launchd 조합은 TCC(전체 디스크 접근) 권한이 없으면 조용히 실패한다.
# 대화형 셸에서는 권한이 있어도 launchd 컨텍스트에는 없을 수 있어 직접 검증이 불가능하다.
_d_icloud() {
  local vp="$1"
  case "$vp" in
    *com~apple~CloudDocs*)
      ok "iCloud 경로 확인"
      _d_warn "launchd에서의 접근 권한은 이 명령으로 검증할 수 없습니다"
      dim "     확인: 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한"
      dim "           /bin/bash 와 /usr/bin/python3 가 켜져 있어야 합니다"
      dim "           (git 바이너리는 iCloud 직접 접근이 막혀 python 경유로 백업합니다)"
      ;;
    *) _d_warn "backend=icloud 인데 경로에 CloudDocs가 없습니다: $vp" ;;
  esac
  return 0
}

_d_launchd() {
  local label="$1" desc="$2"
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  if [ ! -f "$plist" ]; then
    _d_warn "$label 미설치 ($desc) → 'devtrail install-schedule'"
    return
  fi
  if launchctl list 2>/dev/null | grep -q "$label"; then
    local last_exit
    last_exit=$(launchctl list | awk -v l="$label" '$3==l {print $2}')
    if [ "${last_exit:-0}" = "0" ]; then
      ok "$label 로드됨 · 마지막 종료코드 0 ($desc)"
    else
      _d_fail "$label 로드됐으나 마지막 종료코드 $last_exit — 로그: $DEVTRAIL_HOME/logs/$label.err.log"
    fi
  else
    _d_fail "$label plist는 있으나 미로드 → launchctl load -w '$plist'"
  fi
}
