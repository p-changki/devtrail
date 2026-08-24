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

  _d_section "$(L "의존성" "Dependencies")"
  _d_bin jq        required "$(L "설정 파일 파싱 — 없으면 아무것도 동작하지 않음" "parses the config — nothing works without it")"
  _d_bin gh        required "$(L "GitHub PR/이슈 조회" "reads GitHub PRs and issues")"
  _d_bin git       required "$(L "볼트 백업" "vault backups")"
  _d_bin rsync     required "$(L "문서 동기화" "doc sync")"
  _d_bin python3   required "$(L "볼트 백업(권한 우회 경유)" "vault backups (works around permissions)")"
  _d_bin fswatch   optional "$(L "실시간 파일 감시 (미설치 시 주기 동기화만)" "live file watching (without it, periodic sync only)")"

  # ⚠️ 생성기를 **누가 돌리는지** 말한다. 조용히 폴백하면, python3 가 없는
  #    기계에서 왜 안 되는지 아무도 모른다 (ADR 0006 M3).
  local _h
  if _h=$(dt_helper); then
    ok "$(L "생성기" "Generators"): devtrail-helper"
    dim "   $_h"
    dim "   $(L "python3 없이 동작합니다" "Works without python3")"
  else
    warn "$(L "생성기" "Generators"): python3 $(L "폴백" "fallback")"
    dim "   $(L "헬퍼 실행 파일이 없어 python 스크립트로 돕니다." \
                "No helper binary — running the python scripts.")"
    dim "   $(L "빌드" "Build"): (cd app && swift build -c release --product DevTrailHelper)"
  fi

  local ai; ai=$(cfg '.ai.provider' 'claude')
  if [ "$(cfg '.ai.summary_enabled' 'true')" = "true" ]; then
    _d_bin "$ai" required "$(L "PR 쉬운말 요약" "plain-language PR summaries") (ai.provider=$ai)"
  else
    dim "   ai.summary_enabled=false — $(L "AI 요약 비활성" "AI summaries off")"
  fi

  _d_section "$(L "인증" "Auth")"
  if has gh; then
    if gh auth status >/dev/null 2>&1; then
      ok "$(L "gh 인증됨" "gh authenticated") ($(gh api user --jq .login 2>/dev/null || echo '?'))"
    else
      _d_fail "$(L "gh 미인증 → 'gh auth login' 실행 필요" "gh not authenticated → run 'gh auth login'")"
    fi
  fi

  if [ "$(cfg '.linear.enabled' 'false')" = "true" ]; then
    local svc; svc=$(cfg '.linear.keychain_service')
    if security find-generic-password -s "$svc" >/dev/null 2>&1; then
      ok "$(L "Linear API 키 있음" "Linear API key found") (keychain: $svc)"
    else
      _d_warn "$(L "Linear 활성인데 키체인에 키 없음 → Linear 항목은 조용히 스킵됨" \
              "Linear is on but there is no key in the keychain → Linear items are skipped silently")"
    fi
  else
    dim "   $(L "Linear 비활성 (선택 기능)" "Linear off (optional)")"
  fi

  _d_section "$(L "볼트" "Vault")"
  local vp vr; vp=$(vault_path); vr=$(vault_root)
  if [ -z "$vp" ]; then
    _d_fail "$(L "볼트 경로 미설정" "No vault path configured") → 'devtrail init'"
  elif [ ! -d "$vp" ]; then
    _d_fail "$(L "볼트 경로 없음" "Vault not found"): $vp"
  else
    ok "$(L "볼트 존재" "Vault found"): $vp"
    [ -d "$vr" ] && ok "$(L "루트 폴더" "Root folder"): $(cfg '.vault.root')" \
                 || { _d_warn "$(L "루트 폴더 없음" "Root folder missing"): $vr"; }
    _d_plugins "$vp"
    _d_command_center
    _d_naming "$vp" "$vr"
  fi

  local backend; backend=$(cfg '.vault.backend' 'local')
  case "$backend" in
    icloud) _d_icloud "$vp";  ;;
    gdrive) _d_warn "$(L "Google Drive 백엔드는 미검증 — 스트리밍 모드면 파일이 로컬에 없을 수 있음" \
              "The Google Drive backend is untested — in streaming mode files may not be on disk")" ;;
    local)  dim "   $(L "로컬 저장소 — 클라우드 권한 이슈 없음" "Local storage — no cloud permission issues")" ;;
  esac

  _d_section "$(L "자동화" "Automation")"
  _d_launchd "com.devtrail.daily"    "$(L "매일" "daily at") $(cfg '.schedule.daily_hour' '10')$(L "시" ":00")"
  _d_launchd "com.devtrail.repodocs" \
    "$(L "$(cfg '.schedule.repodocs_interval_sec' '600')초 간격" \
         "every $(cfg '.schedule.repodocs_interval_sec' '600')s")"

  _d_section "$(L "AI 스킬" "AI skills")"
  if [ -d "$HOME/.claude/skills" ]; then
    local have want
    want=$(find "$DEVTRAIL_ROOT/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    have=$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d -name 'devtrail-*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${have:-0}" -eq "${want:-0}" ] && [ "${want:-0}" -gt 0 ]; then
      ok "$(L "스킬" "Skills") ${have}/${want}"
    elif [ "${have:-0}" -gt 0 ]; then
      _d_warn "$(L "스킬" "Skills") ${have}/${want} — $(L "일부 누락" "some missing") → 'devtrail skills sync'"
    else
      dim "   $(L "스킬 미설치 (선택)" "Skills not installed (optional)") → 'devtrail skills install'"
    fi
  else
    dim "   $(L "Claude Code 없음 — 스킬은 선택 기능입니다" "No Claude Code — skills are optional")"
  fi

  _d_section "$(L "요약" "Summary")"
  # 요약 줄은 집계 결과를 '보고'만 한다 — _d_fail/_d_warn을 쓰면 자기 자신을
  # 한 번 더 세어 숫자가 틀어진다.
  if [ "$DT_FAILS" -gt 0 ]; then
    fail "$(L "차단 ${DT_FAILS}건 · 경고 ${DT_WARNS}건 — 위 ❌ 항목을 먼저 해결하세요" \
          "${DT_FAILS} blocking · ${DT_WARNS} warnings — fix the ❌ items above first")"
    return 1
  elif [ "$DT_WARNS" -gt 0 ]; then
    warn "$(L "차단 없음 · 경고 ${DT_WARNS}건 — 동작하지만 일부 기능이 빠집니다" \
          "Nothing blocking · ${DT_WARNS} warnings — it works, but some features are missing")"
    return 0
  fi
  ok "$(L "모든 항목 정상" "Everything checks out")"
}

# ── helpers ──────────────────────────────────────────────────────────────────

# 파일명 규칙·헤딩이 볼트의 실제와 맞는가.
#
# ⚠️ 왜 doctor 가 이걸 보나 (2026-08-24 실물 QA)
#
#    기존 볼트를 흡수하면 개발일지 파일명과 헤딩이 DevTrail 기본값과
#    다르다. 그러면 activity·summary 가 할 일을 못 찾는다. 예전에는 그걸
#    **누른 다음에야** 알 수 있었고, 그나마도 "건너뜀" 한 줄이었다.
#
#    여기서 잡으면 누르기 전에 안다. doctor 는 "왜 안 되지" 일 때 사람이
#    실제로 여는 곳이다.
#
# ⚠️ 경고까지만 한다. 사용자의 파일명이 틀린 게 아니라 **우리 설정이**
#    그 볼트를 아직 모르는 것이다 — 고칠지는 사용자가 정한다.
_d_naming() {
  local vp="$1" vr="$2" dir pat glob n
  dir="$vr/$(dt_dir devlog)"
  [ -d "$dir" ] || { dim "   $(L "개발일지 폴더가 아직 없습니다" "No devlog folder yet"): $dir"; return 0; }

  pat=$(cfg '.naming.devlog_file' '{{DATE}} devlog.md')
  glob="${pat//\{\{DATE\}\}/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]}"

  n=$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] || { dim "   $(L "개발일지가 아직 없습니다" "No devlogs yet")"; return 0; }

  # 규칙에 맞는 파일이 하나라도 있는가.
  #
  # ⚠️ 개수를 세지 않고 '하나라도' 를 본다. 규칙을 바꾼 직후에는 옛 이름과
  #    새 이름이 섞여 있는 게 정상이다.
  local f base match=0 newest=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="${f##*/}"
    case "$base" in $glob) match=1; [ -n "$newest" ] || newest="$f" ;; esac
  done <<EOF
$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | sort -r)
EOF

  if [ "$match" = 0 ]; then
    _d_warn "$(L "개발일지 ${n}개가 있는데 파일명 규칙과 하나도 안 맞습니다" \
                 "${n} devlogs exist but none match the filename pattern")"
    dim "   $(L "설정" "Configured"): $pat"
    dim "   $(L "실제" "Actual"):"
    find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | sed 's|.*/|     |' | sort -r | head -3
    dim "   → devtrail config set naming.devlog_file '<$(L "실제 규칙" "actual pattern")>' --apply"
    return 0
  fi

  ok "$(L "개발일지 파일명 규칙" "Devlog filename pattern"): $pat"

  # 규칙에 맞는 가장 최근 일지에 설정된 헤딩이 있는가.
  [ -n "$newest" ] || return 0
  local k h miss=""
  for k in issues_pr worklog; do
    h=$(cfg ".headings.$k" '')
    [ -n "$h" ] || continue
    grep -qF "$h" "$newest" 2>/dev/null || miss="$miss $k"
  done
  if [ -n "$miss" ]; then
    _d_warn "$(L "최근 일지에 없는 헤딩:" "Headings missing from the latest devlog:")$miss"
    dim "   $(L "본 파일" "Checked"): ${newest##*/}"
    dim "   $(L "그 일지에 실제로 있는 헤딩:" "Headings actually in it:")"
    grep -E '^#{1,6} ' "$newest" 2>/dev/null | sed 's/^/     /' | head -5
    for k in $miss; do
      dim "   → devtrail config set headings.$k '<$(L "실제 헤딩" "actual heading")>' --apply"
    done
  else
    ok "$(L "헤딩이 최근 일지와 맞습니다" "Headings match the latest devlog")"
  fi
}

_d_section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }

_d_bin() {
  local bin="$1" mode="$2" why="$3"
  if has "$bin"; then
    ok "$bin"
  elif [ "$mode" = required ]; then
    _d_fail "$bin $(L "없음" "not found") — $why"
    return 1
  else
    _d_warn "$bin $(L "없음 (선택)" "not found (optional)") — $why"
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
# Command Center — 설치·버전·업데이트 가능 여부.
#
# ⚠️ 네트워크를 쓰지 않는다. 저장소의 plugin/ 과 볼트에 깔린 것을 비교할
#    뿐이다. 최신 소스는 `devtrail update` 가 가져온다 — 배포 경로는 하나다.
# ⚠️ 확인 실패를 '고장' 이라고 단정하지 않는다. 설치하지 않은 것은 정상이다.
_d_command_center() {
  local cc="$DEVTRAIL_ROOT/lib/commandcentercmd.sh"
  [ -f "$cc" ] || return 0
  # shellcheck disable=SC1090
  . "$cc"

  local st; st=$(_cc_status --json 2>/dev/null) || return 0
  local installed; installed=$(printf '%s' "$st" | jq -r '.installed')
  if [ "$installed" != "true" ]; then
    dim "   Command Center $(L "미설치 (선택)" "not installed (optional)")"
    dim "     devtrail command-center install --apply"
    return 0
  fi

  local have want upd enabled
  have=$(printf '%s' "$st"    | jq -r '.installed_version')
  want=$(printf '%s' "$st"    | jq -r '.available_version')
  upd=$(printf '%s' "$st"     | jq -r '.update_available | tostring')
  enabled=$(printf '%s' "$st" | jq -r '.enabled | tostring')

  if [ "$upd" = "true" ]; then
    _d_warn "Command Center $(L "업데이트 있음" "update available"): ${have} → ${want}"
    dim "     devtrail command-center update"
  else
    ok "Command Center ${have}"
  fi
  [ "$enabled" = "true" ] || dim "     $(L "꺼져 있습니다" "It is disabled"): devtrail command-center enable --apply"
}

_d_plugins() {
  local vp="$1" pf="$1/.obsidian/community-plugins.json"
  local need=(obsidian-shellcommands templater-obsidian dataview)
  local nice=(auto-note-mover)
  if [ ! -f "$pf" ]; then
    _d_warn "$(L "Obsidian 설정 없음 — 볼트를 한 번 열어야 생성됩니다" \
              "No Obsidian config — it only appears after you open the vault once") (.obsidian/community-plugins.json)"
    return
  fi
  local missing=() p
  for p in "${need[@]}"; do
    jq -e --arg p "$p" 'index($p)' "$pf" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "$(L "필수 플러그인" "Required plugins") ${#need[@]}/${#need[@]}"
  else
    _d_fail "$(L "플러그인 누락" "Plugins missing"): ${missing[*]}"
    case " ${missing[*]} " in
      *" dataview "*) dim "     $(L "dataview 없이도 나머지는 돌지만 주간리뷰가 빈 화면이 됩니다" \
              "Everything else runs without dataview, but weekly reviews come out blank")" ;;
    esac
  fi
  for p in "${nice[@]}"; do
    jq -e --arg p "$p" 'index($p)' "$pf" >/dev/null 2>&1 \
      || dim "   $p $(L "없음 (선택) — DevTrail 은 쓰지 않습니다. 노트 자동 정리용" \
                  "not found (optional) — DevTrail does not use it; it tidies notes")"
  done
}

# iCloud + launchd 조합은 TCC(전체 디스크 접근) 권한이 없으면 조용히 실패한다.
# 대화형 셸에서는 권한이 있어도 launchd 컨텍스트에는 없을 수 있어 직접 검증이 불가능하다.
_d_icloud() {
  local vp="$1"
  case "$vp" in
    *com~apple~CloudDocs*)
      ok "$(L "iCloud 경로 확인" "iCloud path looks right")"
      _d_warn "$(L "launchd 에서의 접근 권한은 이 명령으로 검증할 수 없습니다" \
              "This command cannot verify what launchd is allowed to read")"
      dim "     $(L "확인: 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한" \
                "Check: System Settings → Privacy & Security → Full Disk Access")"
      dim "           $(L "/bin/bash 와 /usr/bin/python3 가 켜져 있어야 합니다" \
                      "/bin/bash and /usr/bin/python3 must be enabled")"
      dim "           $(L "(git 바이너리는 iCloud 직접 접근이 막혀 python 경유로 백업합니다)" \
                      "(the git binary cannot reach iCloud directly, so backups go through python)")"
      ;;
    *) _d_warn "$(L "backend=icloud 인데 경로에 CloudDocs 가 없습니다" \
              "backend=icloud but the path has no CloudDocs in it"): $vp" ;;
  esac
  return 0
}

_d_launchd() {
  local label="$1" desc="$2"
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  if [ ! -f "$plist" ]; then
    _d_warn "$label $(L "미설치" "not installed") ($desc) → 'devtrail install-schedule'"
    return
  fi
  if launchctl list 2>/dev/null | grep -q "$label"; then
    local last_exit
    last_exit=$(launchctl list | awk -v l="$label" '$3==l {print $2}')
    if [ "${last_exit:-0}" = "0" ]; then
      ok "$label $(L "로드됨 · 마지막 종료코드 0" "loaded · last exit 0") ($desc)"
    else
      _d_fail "$label $(L "로드됐으나 마지막 종료코드" "loaded but last exit was") $last_exit — $(L "로그" "log"): $DEVTRAIL_HOME/logs/$label.err.log"
    fi
  else
    _d_fail "$label $(L "plist 는 있으나 미로드" "has a plist but is not loaded") → launchctl load -w '$plist'"
  fi
}
