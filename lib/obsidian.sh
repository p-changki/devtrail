#!/usr/bin/env bash
# DevTrail — `devtrail obsidian`
#
# Obsidian 설정을 볼트에 병합한다. 이 파일은 순서만 정하고, 실제 병합은
# lib/merge/*.sh 가 각자 한다.
#
# 설계 원칙: 남의 볼트 설정을 절대 통째로 덮어쓰지 않는다.
#   - 셸 커맨드 · 라우팅 규칙은 id/태그 기준으로 '병합'한다
#   - 노트 템플릿은 없을 때만 만든다
#   - 단축키·Templater 는 이미 쓰이는 자리를 피한다
#   - 그 외(단축키 취향·Templater 세부)는 '안내'만 하고 건드리지 않는다
# 덮어쓰기로 남의 세팅을 날리는 것이 이 도구가 줄 수 있는 최악의 피해다.
#
# 병합기를 추가하려면 lib/merge/<이름>.sh 를 만들고 아래 DT_MERGERS 에 넣는다.
# 병합기끼리는 서로를 부르지 않는다 — 추가·삭제가 독립적이어야 한다.

# 실행 순서. 앞의 것이 뒤의 전제가 되는 경우만 순서에 의미가 있다:
#   shellcommands 가 먼저여야 hotkeys 가 셸커맨드 id 를 찾을 수 있다.
#   templates 가 먼저여야 templater 가 존재하는 템플릿만 매핑한다.
DT_MERGERS="shellcommands automove templates templater hotkeys app snippets linter smartenv"

obsidian_apply() {
  require_config
  require_bins jq python3

  local vault; vault="$(vault_path)"
  [ -d "$vault" ] || die "볼트 없음: $vault"

  local dot="$vault/.obsidian"
  if [ ! -d "$dot" ]; then
    die "Obsidian 설정 폴더가 없습니다: $dot
   Obsidian에서 이 볼트를 한 번 연 뒤 다시 실행하세요."
  fi

  local m
  for m in $DT_MERGERS; do
    local f="$DEVTRAIL_ROOT/lib/merge/$m.sh"
    [ -f "$f" ] || { warn "병합기 없음 — 건너뜀: $m"; continue; }
    # shellcheck disable=SC1090
    . "$f"
    "_ob_$m" "$dot"
  done

  _ob_advice "$dot"
}

# ── 나머지는 안내만 ──────────────────────────────────────────────────────────
_ob_advice() {
  local dot="$1"
  step "수동 설정이 필요한 것"
  dim "   아래는 기존 설정을 덮어쓸 위험이 있어 자동으로 건드리지 않습니다."
  echo
  info "  1) Daily notes"
  dim "     폴더: $(vault_rel "$(dt_dir devlog)")"
  dim "     템플릿: $(vault_rel "$(dt_dir templates)")/개발일지양식.md"
  info "  2) Templater → Folder templates"
  dim "     'Trigger Templater on new file creation' 을 켜야 자동 삽입이 동작합니다"
  info "  3) 단축키 (선택)"
  dim "     설정 → 단축키에서 'DevTrail'로 검색해 원하는 키를 지정"
}

_d_note() { printf '   %s\n' "$*"; }
