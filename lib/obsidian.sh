#!/usr/bin/env bash
# DevTrail — Obsidian 설정 적용 (`devtrail obsidian`)
#
# 설계 원칙: 남의 볼트 설정을 절대 통째로 덮어쓰지 않는다.
#   - 셸 커맨드는 id 기준으로 '병합'한다 (기존 커맨드 보존)
#   - 노트 템플릿은 없을 때만 만든다
#   - 그 외 설정(단축키·Templater 폴더매핑)은 '안내'만 하고 건드리지 않는다
# 덮어쓰기로 남의 세팅을 날리는 것이 이 도구가 줄 수 있는 최악의 피해다.

obsidian_apply() {
  require_config
  require_bins jq

  local vault; vault="$(vault_path)"
  [ -d "$vault" ] || die "볼트 없음: $vault"

  local dot="$vault/.obsidian"
  if [ ! -d "$dot" ]; then
    die "Obsidian 설정 폴더가 없습니다: $dot
   Obsidian에서 이 볼트를 한 번 연 뒤 다시 실행하세요."
  fi

  _ob_shellcommands "$dot"
  _ob_note_templates
  _ob_advice "$dot"
}

# ── 셸 커맨드 병합 ───────────────────────────────────────────────────────────
_ob_shellcommands() {
  local dot="$1"
  local data="$dot/plugins/obsidian-shellcommands/data.json"
  local src="$DEVTRAIL_ROOT/templates/obsidian/shellcommands.json"

  step "Shell commands"

  if [ ! -f "$data" ]; then
    _d_note "Shell commands 플러그인이 설치/활성화되지 않았습니다."
    dim "     설치 후 Obsidian을 재시작하고 다시 실행하세요."
    dim "     경로: $data"
    return 0
  fi
  [ -f "$src" ] || { warn "템플릿 없음: $src"; return 0; }

  # {{DEVTRAIL_HOME}} 치환
  local rendered; rendered=$(mktemp)
  sed "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" "$src" > "$rendered"

  if ! jq -e . "$rendered" >/dev/null 2>&1; then
    rm -f "$rendered"; die "셸 커맨드 템플릿이 유효한 JSON이 아닙니다"
  fi

  # 백업 실패를 확인하지 않으면, 백업 없이 원본을 교체하고도
  # 사용자에게는 "백업했다"고 말하게 된다. README의 안전 계약이 거짓이 된다.
  local backup="$data.bak.$(date +%Y%m%d%H%M%S)"
  cp "$data" "$backup" || { rm -f "$rendered"; die "백업 실패 — 원본을 건드리지 않습니다: $data"; }

  local merged; merged=$(mktemp)
  # 같은 id는 교체, 없는 id는 뒤에 추가. 기존 커맨드의 순서는 그대로 둔다.
  if ! jq --slurpfile new "$rendered" '
      ($new[0] | map({key: .id, value: .}) | from_entries) as $byid
      | (.shell_commands // [])                as $old
      | ($old | map(.id))                      as $oldids
      | .shell_commands =
          ($old | map($byid[.id] // .))
          + ($new[0] | map(select(.id as $i | ($oldids | index($i)) == null)))
    ' "$data" > "$merged" 2>/dev/null; then
    rm -f "$rendered" "$merged"
    die "병합 실패 — 원본은 그대로입니다: $data"
  fi

  if ! jq -e '.shell_commands | length > 0' "$merged" >/dev/null 2>&1; then
    rm -f "$rendered" "$merged"
    die "병합 결과가 비정상입니다 — 원본 유지: $data"
  fi

  mv "$merged" "$data"
  rm -f "$rendered"

  local n; n=$(jq '.shell_commands | length' "$data")
  ok "셸 커맨드 병합 완료 (전체 ${n}개)"
  dim "     백업: $backup"
}

# ── 노트 템플릿 ──────────────────────────────────────────────────────────────
_ob_note_templates() {
  step "노트 템플릿"
  local dest; dest="$(dir_templates)"
  local src="$DEVTRAIL_ROOT/templates/obsidian/notes"
  [ -d "$src" ] || { warn "템플릿 없음: $src"; return 0; }

  # PR 요약이 들어갈 프로젝트 섹션. project_groups 의 '값'이 섹션명이다.
  # 이게 비면 summary 는 넣을 자리를 못 찾아 전부 건너뛴다.
  local sections
  sections=$(jq -r '
      (.github.project_groups // {}) | [.[]] | unique | .[] | "#### " + .
    ' "$CONFIG_FILE" 2>/dev/null) || sections=""

  mkdir -p "$dest"
  local n=0 skipped=0
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    local name; name=$(basename "$f")
    if [ -f "$dest/$name" ]; then
      skipped=$((skipped+1)); continue
    fi
    # sed로는 여러 줄 치환이 안 된다. python3은 이미 필수 의존성이다.
    python3 - "$f" "$dest/$name" \
      "$(cfg '.headings.issues_pr')" "$(cfg '.headings.worklog')" "$sections" <<'PYEOF' \
      || { warn "템플릿 렌더 실패 - 건너뜀: $name"; continue; }
import re, sys
src, dst, h_issues, h_worklog, sections = sys.argv[1:6]
with open(src, encoding="utf-8") as fh:
    text = fh.read()
# 섹션 사이는 빈 줄로 띄운다 — 붙여 놓으면 나중에 손으로 내용을 적기 불편하다.
spaced = "\n\n".join(l for l in sections.split("\n") if l.strip())
text = (text.replace("{{HEADING_ISSUES_PR}}", h_issues)
            .replace("{{HEADING_WORKLOG}}", h_worklog)
            .replace("{{PROJECT_SECTIONS}}", spaced))
# 섹션이 비면 빈 줄만 남는다. 3줄 이상 연속된 개행은 2줄로 줄인다.
text = re.sub(r"\n{3,}", "\n\n", text)
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(text)
PYEOF
    n=$((n+1))
  done
  ok "템플릿 ${n}개 설치 (기존 유지 ${skipped}개) → $dest"
  if [ -n "$sections" ]; then
    dim "     PR 요약 섹션: $(printf '%s' "$sections" | tr '\n' ' ')"
  else
    warn "     project_groups 가 비어 있어 PR 요약 섹션이 없습니다"
    dim "     이대로면 summary 는 넣을 자리를 못 찾아 전부 건너뜁니다."
  fi
}

# ── 나머지는 안내만 ──────────────────────────────────────────────────────────
_ob_advice() {
  local dot="$1"
  step "수동 설정이 필요한 것"
  dim "   아래는 기존 설정을 덮어쓸 위험이 있어 자동으로 건드리지 않습니다."
  echo
  info "  1) Daily notes"
  dim "     폴더: $(cfg '.vault.root')/$(cfg '.dirs.devlog')"
  dim "     템플릿: $(cfg '.vault.root')/$(cfg '.dirs.templates')/devlog.md"
  info "  2) Templater → Folder templates"
  dim "     '$(cfg '.dirs.devlog')' 폴더에 devlog 템플릿 매핑"
  dim "     'Trigger Templater on new file creation' 을 켜야 자동 삽입이 동작합니다"
  info "  3) 단축키 (선택)"
  dim "     설정 → 단축키에서 'DevTrail'로 검색해 원하는 키를 지정"
}

_d_note() { printf '   %s\n' "$*"; }
