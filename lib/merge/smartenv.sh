#!/usr/bin/env bash
# DevTrail — RAG 제외 설정 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── RAG 제외 설정 ────────────────────────────────────────────────────────────
#
# 인덱스는 넓히는 게 아니라 좁히는 것이 품질을 만든다.
# 헤딩 제외는 템플릿에서 생성한다 — 손으로 관리하면 반드시 샌다.
_ob_smartenv() {
  local se; se="$(vault_path)/.smart-env"
  local data="$se/smart_env.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"

  step "$(L "RAG 제외 설정" "RAG exclusions")"
  if [ "$(jq -r '.merge.smart_env // false' "$profile" 2>/dev/null)" != "true" ]; then
    dim "     $(L "이 모드에서는 건드리지 않습니다" "This mode leaves it alone")"; return 0
  fi
  if [ ! -d "$se" ]; then
    _d_note "Smart Connections $(L "가 설치/활성화되지 않았습니다 (선택 기능)." "is not installed or not enabled (optional).")"
    dim "     $(L "설치하면 볼트 전체에 로컬 임베딩 검색이 생깁니다." \
                "Install it for local embedding search across the vault.")"
    return 0
  fi

  local out; out=$(mktemp)
  DT_FOREIGN_FOLDERS="$(_ob_foreign_folders)" \
  python3 "$DEVTRAIL_ROOT/lib/gen/smartenv.py" \
    "$DEVTRAIL_ROOT/preset/tree.json" "$CONFIG_FILE" \
    "$(vault_root)/$(dt_dir templates)" \
    "$([ -f "$data" ] && printf '%s' "$data")" > "$out" || {
      rm -f "$out"; warn "$(L "제외 설정 생성 실패 — 건드리지 않습니다" "Could not build exclusions — leaving them alone")"; return 0; }

  if [ -f "$data" ]; then
    jr_backup "$data" >/dev/null \
      || { rm -f "$out"; die "$(L "백업 실패 — 원본을 건드리지 않습니다" "Backup failed — leaving the original alone"): $data"; }
  fi
  mv "$out" "$data"
  ok "$(L "제외" "Excluded") — $(L "폴더" "folders") $(jq -r '.smart_sources.folder_exclusions | split(",") | length' "$data") · $(L "헤딩" "headings") $(jq -r '.smart_sources.excluded_headings | split(",") | length' "$data")"
  dim "     $(L "헤딩 제외는 템플릿의 Dataview 블록에서 생성됩니다 — 쿼리를 추가하면 따라옵니다." \
                "Heading exclusions come from the Dataview blocks in your templates — add a query and it follows.")"
}

# ── 나머지는 안내만 ──────────────────────────────────────────────────────────
