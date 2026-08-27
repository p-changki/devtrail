#!/usr/bin/env bash
# DevTrail — 유튜브 자막 확보와 AI 정리.
# capturecmd.sh가 cfg·저널·i18n 함수를 준비한 뒤 불러온다.
#
# Claude가 /tmp의 자막을 Read 하게 하면 로컬 보안 훅이 경로를 막을 수 있다.
# 그래서 자막 수집은 DevTrail이 맡고, 필요한 텍스트만 프롬프트에 직접 넣는다.

_cap_youtube_transcript() {
  local url="$1" tmp sub text
  [ -n "${DT_CAPTURE_TRANSCRIPT:-}" ] && { printf '%s' "$DT_CAPTURE_TRANSCRIPT"; return 0; }
  has yt-dlp || return 1
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/devtrail-youtube.XXXXXX") || return 1
  # 와일드카드(ko.*)는 번역 자막 조합을 수십 개까지 요청해 YouTube 429를
  # 부른다. 대표 언어 하나씩만 요청하고, SRT 변환 실패에도 원본 VTT를 읽는다.
  yt-dlp --skip-download --write-subs --write-auto-subs \
    --sub-langs 'ko,ja,en' \
    -o "$tmp/%(id)s.%(ext)s" -- "$url" >/dev/null 2>&1 || true
  sub=$(find "$tmp" -type f \( -name '*.ko*.srt' -o -name '*.ko*.vtt' -o -name '*.ja*.srt' -o -name '*.ja*.vtt' -o -name '*.en*.srt' -o -name '*.en*.vtt' -o -name '*.srt' -o -name '*.vtt' \) \
    -print 2>/dev/null | head -1)
  if [ -n "$sub" ] && [ -s "$sub" ]; then
    text=$(sed -E '/^[0-9]+$/d; /^[0-9]{2}:[0-9]{2}:/d; s/<[^>]*>//g; /^[[:space:]]*$/d' "$sub" | head -c 72000)
  else
    text=""
  fi
  rm -rf "$tmp"
  [ -n "$text" ] || return 1
  printf '%s' "$text"
}

_cap_youtube_ai() {
  # AI 실패는 링크 저장 실패가 아니다. 사용자는 URL을 잃지 않고 나중에 다시
  # 정리할 수 있어야 한다.
  local url="$1" file="$2" root="$3" purpose="${4:-}" provider prompt out transcript note_dir purpose_prompt claude_rc=0
  [ "$(cfg '.ai.summary_enabled' 'true')" = "true" ] || {
    dim "   $(L "AI 요약이 꺼져 있어 링크만 저장했습니다." "AI summaries are off; saved the link only.")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=skipped'
    return 0
  }
  provider=$(cfg '.ai.provider' 'claude')
  if [ "$provider" != "claude" ] || ! has claude; then
    warn "$(L "Claude를 찾지 못해 링크만 저장했습니다" "Claude was not found; saved the link only")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=unavailable'
    return 0
  fi
  if [ ! -d "$HOME/.claude/skills/devtrail-youtube" ]; then
    warn "$(L "유튜브 스킬이 없어 링크만 저장했습니다 — devtrail skills sync" "The YouTube skill is missing; saved the link only — run devtrail skills sync")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=unavailable'
    return 0
  fi

  transcript=$(_cap_youtube_transcript "$url") || {
    warn "$(L "자막을 읽지 못해 링크만 저장했습니다" "Could not read captions; saved the link only")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=unavailable'
    return 0
  }
  # 자막은 이미 DevTrail이 확보했다. Claude에는 노트가 있는 폴더만 열어
  # 읽기·쓰기 범위를 그 파일 하나로 실질적으로 제한한다.
  note_dir=$(dirname "$file")
  if [ -n "$purpose" ]; then
    purpose_prompt="사용자 학습 목적: $purpose
이 목적을 기준으로 필요한 판단·근거·실행 항목을 우선 추출하세요."
  else
    purpose_prompt="사용자 학습 목적은 제공되지 않았습니다. 제목과 자막으로 구체적인 학습 목적을 한 문장으로 추정하고, 노트에 '추정한 학습 목적'이라고 표시하세요."
  fi
  prompt="아래 자막을 근거로 **지정한 노트 한 파일만** 완성하세요.
URL: $url
노트: $file

$purpose_prompt

frontmatter의 tl_dr_oneline·key_for_me·channel·duration·title과 본문의 메타, TL;DR, 인사이트를 채우세요. 자막에 없는 내용은 만들지 마세요. 다른 파일·설정·프로젝트는 수정하지 마세요. 작업을 끝낸 뒤에는 이 노트를 실제로 저장해야 합니다.

영상 장르를 `design-critique` / `tutorial` / `tool-review` / `career-interview` / `news-trend` / `strategy` / `general` 중 하나로 정하고 노트 메타의 `장르` 줄에 남기세요. 노트에는 이미 TL;DR 뒤에 `## 바로 쓰는 판단 기준` 자리가 있습니다. 같은 제목을 새로 만들지 말고 그 자리를 3~7개의 짧은 판단 카드로 채우세요. 각 카드에는 판단/주장, 적용 맥락, 근거 또는 문제 신호, 내 적용, 분류(원칙·조건부 조언·개인 취향·사실 주장), 가능한 경우 짧은 인용을 포함하세요. 특정 화면의 숫자 처방은 보편 규칙으로 일반화하지 말고 원칙과 분리하세요. 화자의 의견·자막으로 확인된 사실·AI 해석을 섞지 말고 AI 해석에는 `해석`을 붙이세요.

장르별로 필요한 섹션만 추가하세요: 디자인 피드백은 문제 신호·수정 방향·예외/브랜드 맥락·재사용 체크리스트, 튜토리얼은 전제조건·단계·실패 포인트·적용 순서, 도구 리뷰는 적합한 사용자·장점/제약·대체재·도입 판단, 커리어/인터뷰는 화자의 경험·일반화 가능한 조언·개인 사례, 뉴스/트렌드는 확인된 사실·화자의 해석·영향 대상·대응 필요성, 전략은 주장·시장 전제·성공 조건·리스크·검증 실험을 추출하세요. 상세 내용·타임라인·전체 자막은 위 판단 기준 뒤의 보조 자료로 두세요.

분류는 반드시 채우세요. `category`와 `area`에는 같은 값 하나를 넣습니다:
frontend | backend | infra | data-ai | design | common

`topic`은 영상 내용에 가장 가까운 하나만 넣습니다:
official-docs | ui-components | css-animation | accessibility | api | database |
auth-payments | deploy-operations | monitoring | models-tools | prompts-examples |
icons | images-illustrations | landing-references | design-tools | developer-tools |
github-open-source | productivity-career | security | documentation | articles | uncategorized

자막에 근거가 있으면 `uncategorized`를 쓰지 마세요. 예: React 컴포넌트 영상은
frontend / ui-components, Figma 플러그인은 design / design-tools, 배포 자동화는
infra / deploy-operations입니다. `tags`에는 기존 type/youtube를 유지하며
area/<area>와 topic/<topic>도 추가하세요.

--- 자막 시작 ---
$transcript
--- 자막 끝 ---"
  info "  $(L "Claude로 자막을 분석하는 중…" "Analyzing transcript with Claude…")"
  # Claude가 노트를 저장한 뒤 후처리/연결 단계에서 비정상 종료할 수 있다.
  # 종료 코드만으로 실패 처리하면 실제로 완성된 노트가 "AI 건너뜀"으로 보인다.
  # 따라서 아래에서 노트 내용을 정본으로 확인한다.
  out=$(claude -p "$prompt" --add-dir "$note_dir" --allowedTools 'Read,Edit,Write' \
    --permission-mode acceptEdits --max-budget-usd 1 2>&1) || claude_rc=$?
  if ! grep -qE '^tl_dr_oneline: *[^[:space:]]' "$file"; then
    warn "$(L "AI가 노트를 채우지 못했습니다 — 링크 노트는 저장됐습니다" "AI did not populate the note — the link note was saved")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=unavailable'
    return 0
  fi
  local category area topic
  category=$(sed -n 's/^category:[[:space:]]*//p' "$file" | head -1)
  area=$(sed -n 's/^area:[[:space:]]*//p' "$file" | head -1)
  topic=$(sed -n 's/^topic:[[:space:]]*//p' "$file" | head -1)
  case "$area" in frontend|backend|infra|data-ai|design|common) ;; *) area="" ;; esac
  if [ -z "$area" ] || [ "$category" != "$area" ] || [ -z "$topic" ] || [ "$topic" = "uncategorized" ]; then
    warn "$(L "AI 요약은 저장됐지만 자료 분류를 채우지 못했습니다 — 같은 링크를 다시 정리해 보세요" "The AI summary was saved but its library category is missing — retry this link")"
    printf '%s\n' 'DEVTRAIL_CAPTURE_AI=partial'
    return 0
  fi
  [ "$claude_rc" -eq 0 ] || warn "$(L "Claude가 완료 뒤 상태 코드를 반환했지만 노트는 정상 저장됐습니다" "Claude returned a status code after completion, but the note was saved")"
  ok "$(L "AI 정리 완료" "AI analysis complete")"
  printf '%s\n' 'DEVTRAIL_CAPTURE_AI=complete'
  [ -n "$out" ] && dim "   $(printf '%s' "$out" | tail -1)"
}
