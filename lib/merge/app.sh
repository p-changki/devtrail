#!/usr/bin/env bash
# DevTrail — 에디터 설정 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── 에디터 설정 ──────────────────────────────────────────────────────────────
#
# ⚠️ alwaysUpdateLinks 가 핵심이다. Auto Note Mover 가 노트를 '이동'시키는데
#    이 옵션이 꺼져 있으면 옮길 때마다 링크가 조용히 끊긴다.
#    자동 이동과 이 옵션은 반드시 세트다.
#
# 기존 모드에서는 프로파일의 app_safe_keys 에 든 것만 넣는다 —
# 나머지는 사용자의 편집 습관이라 건드리면 안 된다.
_ob_app() {
  local dot="$1"
  local app="$dot/app.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"
  local src="$DEVTRAIL_ROOT/preset/obsidian/app.json"

  step "에디터 설정"
  local how; how=$(jq -r '.merge.app // "false"' "$profile" 2>/dev/null)
  [ "$how" = "false" ] && { dim "     이 모드에서는 건드리지 않습니다"; return 0; }
  [ -f "$src" ] || { warn "프리셋 없음: $src"; return 0; }

  local attach; attach=$(vault_rel "$(dt_dir attach)")
  local want; want=$(mktemp)
  jq --arg a "$attach" 'del(._comment) | .attachmentFolderPath = $a' "$src" > "$want"

  # 기존 모드는 안전 키만
  if [ "$how" = "safe_keys_only" ]; then
    local keys; keys=$(jq -c '.app_safe_keys // []' "$profile")
    jq --argjson k "$keys" 'with_entries(select(.key as $x | $k | index($x)))' "$want" > "$want.f" \
      && mv "$want.f" "$want"
  fi

  local out; out=$(mktemp)
  jq -s '.[0] * .[1]' "$([ -f "$app" ] && printf '%s' "$app" || echo /dev/null)" "$want" > "$out" 2>/dev/null \
    || jq '.' "$want" > "$out"

  jr_backup "$app" >/dev/null || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $app"; }
  mv "$out" "$app"; rm -f "$want"

  ok "$(jq -r 'keys | length' "$app")개 키 · alwaysUpdateLinks=$(jq -r '.alwaysUpdateLinks' "$app")"
  [ "$(jq -r '.alwaysUpdateLinks' "$app")" = "true" ] \
    || warn "     alwaysUpdateLinks 가 꺼져 있습니다 — 노트를 옮기면 링크가 끊깁니다"
}

# ── CSS 스니펫 ───────────────────────────────────────────────────────────────
#
# 파일만 넣으면 아무 일도 안 일어난다. appearance.json 의 enabledCssSnippets 에
# 등록해야 적용된다. 원본 볼트는 등록만 하고 파일이 없는 항목이 있었다.
