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
  _ob_automove "$dot"
  _ob_note_templates
  _ob_smartenv
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

# ── 태그 → 폴더 라우팅 ───────────────────────────────────────────────────────
#
# ⚠️ 기존 볼트에서 이걸 Automatic 으로 켜면, 사용자가 기존 노트를 열어 저장하는
#    순간 태그에 따라 폴더가 바뀐다. 데이터가 사라지진 않지만 "내 노트가 어디
#    갔지"가 되는, 신뢰를 한 번에 잃는 종류다.
#    프로파일이 기존 모드에서 Manual 을 쓰는 이유이고, 우리가 만들지 않은
#    폴더를 전부 제외 목록에 넣는 이유다.
_ob_automove() {
  local dot="$1"
  local data="$dot/plugins/auto-note-mover/data.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"

  step "노트 라우팅 (Auto Note Mover)"
  [ -f "$profile" ] || { warn "프로파일 없음: $profile"; return 0; }

  if [ ! -d "$(dirname "$data")" ]; then
    _d_note "Auto Note Mover 플러그인이 설치/활성화되지 않았습니다."
    dim "     설치 후 Obsidian을 재시작하고 다시 실행하세요."
    return 0
  fi

  local out; out=$(mktemp)
  DT_FOREIGN_FOLDERS="$(_ob_foreign_folders)" \
  python3 "$DEVTRAIL_ROOT/lib/anm.py" \
    "$DEVTRAIL_ROOT/preset/tree.json" "$CONFIG_FILE" "$profile" \
    "$([ -f "$data" ] && printf '%s' "$data")" > "$out" || {
      rm -f "$out"; warn "규칙 생성 실패 — 건드리지 않습니다"; return 0; }

  jq -e '.folder_tag_pattern | length > 0' "$out" >/dev/null 2>&1 || {
    rm -f "$out"; warn "생성된 규칙이 비어 있습니다 — 원본 유지"; return 0; }

  if [ -f "$data" ]; then
    local backup="$data.bak.$(date +%Y%m%d%H%M%S)"
    cp "$data" "$backup" || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $data"; }
    dim "     백업: $backup"
  fi
  mv "$out" "$data"

  local n trig
  n=$(jq '.folder_tag_pattern | length' "$data")
  trig=$(jq -r '.trigger_auto_manual' "$data")
  ok "규칙 ${n}개 · 트리거 ${trig}"
  [ "$trig" = "Manual" ] && \
    dim "     기존 노트를 지키려고 수동으로 시작합니다. 익숙해지면 플러그인 설정에서 Automatic 으로 바꾸세요."
}

# 볼트 최상위에서 우리가 만들지 않은 폴더들. 기존 모드의 제외 목록이 된다.
_ob_foreign_folders() {
  local vault root ours
  vault="$(vault_path)"; root="$(cfg '.vault.root')"
  ours=$(jq -r '.folders[].path | split("/")[0]' "$DEVTRAIL_ROOT/preset/tree.json" | sort -u)
  find "$vault" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r d; do
    local b; b=$(basename "$d")
    case "$b" in .*) continue ;; esac
    [ -n "$root" ] && [ "$b" = "$root" ] && continue
    printf '%s\n' "$ours" | grep -qxF "$b" && continue
    printf '%s\n' "$b"
  done
}

# ── 노트 템플릿 ──────────────────────────────────────────────────────────────
#
# 없을 때만 만든다. 사용자가 고친 템플릿을 덮어쓰지 않는다.
#
# 템플릿에는 경로가 한 글자도 없다 — 실행 시점에 _devtrail-paths.md 를
# 파일명으로 찾아 읽는다. 그래서 여기서는 치환 없이 그대로 복사한다.
_ob_note_templates() {
  step "노트 템플릿"
  local dest; dest="$(vault_root)/$(dt_dir templates)"
  local src="$DEVTRAIL_ROOT/preset/templates"
  [ -d "$src" ] || { warn "템플릿 없음: $src"; return 0; }

  mkdir -p "$dest"
  local n=0 skipped=0 f name
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if [ -f "$dest/$name" ]; then
      skipped=$((skipped + 1)); continue
    fi
    cp "$f" "$dest/$name" || { warn "복사 실패: $name"; continue; }
    n=$((n + 1))
  done
  ok "템플릿 ${n}개 설치 (기존 유지 ${skipped}개) → $(dt_dir templates)"

  local sections
  sections=$(jq -r '(.github.project_groups // {}) | [.[]] | unique | .[]' "$CONFIG_FILE" 2>/dev/null)
  if [ -n "$sections" ]; then
    dim "     PR 요약 섹션: $(printf '%s' "$sections" | tr '\n' ' ')"
    dim "     개발일지를 만들 때 선택창에서 고르면 #### 소제목이 생깁니다."
  else
    warn "     project_groups 가 비어 있어 PR 요약이 넣을 자리를 못 찾습니다"
    dim "     devtrail init 을 다시 돌리거나 설정의 github.project_groups 를 채우세요."
  fi
}

# ── RAG 제외 설정 ────────────────────────────────────────────────────────────
#
# 인덱스는 넓히는 게 아니라 좁히는 것이 품질을 만든다.
# 헤딩 제외는 템플릿에서 생성한다 — 손으로 관리하면 반드시 샌다.
_ob_smartenv() {
  local se; se="$(vault_path)/.smart-env"
  local data="$se/smart_env.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"

  step "RAG 제외 설정"
  if [ "$(jq -r '.merge.smart_env // false' "$profile" 2>/dev/null)" != "true" ]; then
    dim "     이 모드에서는 건드리지 않습니다"; return 0
  fi
  if [ ! -d "$se" ]; then
    _d_note "Smart Connections 가 설치/활성화되지 않았습니다 (선택 기능)."
    dim "     설치하면 볼트 전체에 로컬 임베딩 검색이 생깁니다."
    return 0
  fi

  local out; out=$(mktemp)
  DT_FOREIGN_FOLDERS="$(_ob_foreign_folders)" \
  python3 "$DEVTRAIL_ROOT/lib/smartenv.py" \
    "$DEVTRAIL_ROOT/preset/tree.json" "$CONFIG_FILE" \
    "$(vault_root)/$(dt_dir templates)" \
    "$([ -f "$data" ] && printf '%s' "$data")" > "$out" || {
      rm -f "$out"; warn "제외 설정 생성 실패 — 건드리지 않습니다"; return 0; }

  if [ -f "$data" ]; then
    cp "$data" "$data.bak.$(date +%Y%m%d%H%M%S)" \
      || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $data"; }
  fi
  mv "$out" "$data"
  ok "폴더 $(jq -r '.smart_sources.folder_exclusions | split(",") | length' "$data")개 · 헤딩 $(jq -r '.smart_sources.excluded_headings | split(",") | length' "$data")개 제외"
  dim "     헤딩 제외는 템플릿의 Dataview 블록에서 생성됩니다 — 쿼리를 추가하면 따라옵니다."
}

# ── 나머지는 안내만 ──────────────────────────────────────────────────────────
_ob_advice() {
  local dot="$1"
  step "수동 설정이 필요한 것"
  dim "   아래는 기존 설정을 덮어쓸 위험이 있어 자동으로 건드리지 않습니다."
  echo
  info "  1) Daily notes"
  dim "     폴더: $(vault_rel "$(dt_dir devlog)")"
  dim "     템플릿: $(vault_rel "$(dt_dir templates)")/devlog.md"
  info "  2) Templater → Folder templates"
  dim "     '$(dt_dir devlog)' 폴더에 devlog 템플릿 매핑"
  dim "     'Trigger Templater on new file creation' 을 켜야 자동 삽입이 동작합니다"
  info "  3) 단축키 (선택)"
  dim "     설정 → 단축키에서 'DevTrail'로 검색해 원하는 키를 지정"
}

_d_note() { printf '   %s\n' "$*"; }
