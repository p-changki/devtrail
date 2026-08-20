#!/usr/bin/env bash
# DevTrail — 단축키 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── 단축키 ───────────────────────────────────────────────────────────────────
#
# ⚠️ Templater 커맨드 ID 안에 볼트 경로가 들어간다. 정적 파일을 복사하면
#    루트명이 다른 사용자에게서 단축키가 조용히 죽는다. 조립해서 만든다.
_ob_hotkeys() {
  local dot="$1"
  local hk="$dot/hotkeys.json"
  local paths; paths=$(_ob_paths_json)

  step "단축키"
  local ids; ids=$(mktemp)
  jq -r '[.[] | {key: .id, value: .id}] | from_entries' \
    "$DEVTRAIL_ROOT/templates/obsidian/shellcommands.json" > "$ids" 2>/dev/null || echo '{}' > "$ids"

  local out; out=$(mktemp)
  if DT_TEMPLATES_DIR="$DEVTRAIL_ROOT/preset/templates/$(dt_lang)" \
     python3 "$DEVTRAIL_ROOT/lib/gen/hotkeys.py" hotkeys \
      "$DEVTRAIL_ROOT/preset/obsidian/hotkeys.tmpl.json" "$paths" \
      "$([ -f "$hk" ] && printf '%s' "$hk")" "$ids" > "$out"; then
    jr_backup "$hk" >/dev/null || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $hk"; }
    mv "$out" "$hk"
    ok "단축키 $(jq 'length' "$hk")개 등록"
    dim "     Obsidian 을 재시작해야 적용됩니다"
  else
    rm -f "$out"; warn "단축키 생성 실패 — 건드리지 않습니다"
  fi
  rm -f "$ids"
}

# 경로 맵을 임시 JSON 으로 낸다 (파이썬 쪽 입력용)

# 경로 맵을 임시 JSON 으로 낸다 (파이썬 쪽 입력용)
_ob_paths_json() {
  local f; f=$(mktemp)
  . "$DEVTRAIL_ROOT/lib/pathcmd.sh"
  path_cmd --json > "$f" 2>/dev/null \
    && jq -n --slurpfile p "$f" '{paths: ($p[0] | with_entries(.value = .value.rel))}' > "$f.2" \
    && mv "$f.2" "$f"
  printf '%s' "$f"
}

# ── 에디터 설정 ──────────────────────────────────────────────────────────────
#
# ⚠️ alwaysUpdateLinks 가 핵심이다. Auto Note Mover 가 노트를 '이동'시키는데
#    이 옵션이 꺼져 있으면 옮길 때마다 링크가 조용히 끊긴다.
#    자동 이동과 이 옵션은 반드시 세트다.
#
# 기존 모드에서는 프로파일의 app_safe_keys 에 든 것만 넣는다 —
# 나머지는 사용자의 편집 습관이라 건드리면 안 된다.
