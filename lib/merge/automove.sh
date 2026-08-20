#!/usr/bin/env bash
# DevTrail — 노트 라우팅 (Auto Note Mover) 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

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
  python3 "$DEVTRAIL_ROOT/lib/gen/anm.py" \
    "$DEVTRAIL_ROOT/preset/tree.json" "$CONFIG_FILE" "$profile" \
    "$([ -f "$data" ] && printf '%s' "$data")" > "$out" || {
      rm -f "$out"; warn "규칙 생성 실패 — 건드리지 않습니다"; return 0; }

  jq -e '.folder_tag_pattern | length > 0' "$out" >/dev/null 2>&1 || {
    rm -f "$out"; warn "생성된 규칙이 비어 있습니다 — 원본 유지"; return 0; }

  if [ -f "$data" ]; then
    local backup
    backup=$(jr_backup "$data") || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $data"; }
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

# 볼트 최상위에서 우리가 만들지 않은 폴더들. 기존 모드의 제외 목록이 된다.
_ob_foreign_folders() {
  local vault root ours
  vault="$(vault_path)"; root="$(cfg '.vault.root')"
  # ⚠️ 언어를 봐야 한다. 영어 볼트에서 한국어 최상위 이름을 '우리 것'으로
  #    보면, 정작 사용자의 Dev/ 를 남의 폴더로 취급해 규칙에서 빼버린다.
  ours=$(jq -r --argjson en "$([ "$(dt_lang)" = en ] && echo true || echo false)" '
    .folders[] | (if $en then (.path_en // .path) else .path end) | split("/")[0]
  ' "$DEVTRAIL_ROOT/preset/tree.json" | sort -u)
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
