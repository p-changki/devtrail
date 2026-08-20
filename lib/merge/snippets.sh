#!/usr/bin/env bash
# DevTrail — CSS 스니펫 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── CSS 스니펫 ───────────────────────────────────────────────────────────────
#
# 파일만 넣으면 아무 일도 안 일어난다. appearance.json 의 enabledCssSnippets 에
# 등록해야 적용된다. 원본 볼트는 등록만 하고 파일이 없는 항목이 있었다.
_ob_snippets() {
  local dot="$1"
  local dir="$dot/snippets"
  local app="$dot/appearance.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"
  local src="$DEVTRAIL_ROOT/preset/obsidian/snippets"

  step "CSS 스니펫"
  [ "$(jq -r '.merge.snippets // false' "$profile" 2>/dev/null)" = "true" ] \
    || { dim "     이 모드에서는 건드리지 않습니다"; return 0; }
  [ -d "$src" ] || { warn "프리셋 없음: $src"; return 0; }

  mkdir -p "$dir"
  local n=0 f name
  for f in "$src"/*.css; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .css)
    cp "$f" "$dir/$name.css" && n=$((n + 1))
  done

  # 활성화 등록 — 이게 없으면 파일만 있고 적용은 안 된다
  local out; out=$(mktemp)
  jq --arg n "devtrail" '
    .enabledCssSnippets = ((.enabledCssSnippets // []) + [$n] | unique)
  ' "$([ -f "$app" ] && printf '%s' "$app" || echo /dev/null)" > "$out" 2>/dev/null \
    || printf '{"enabledCssSnippets":["devtrail"]}' > "$out"

  jr_backup "$app" >/dev/null || { rm -f "$out"; die "백업 실패 — 원본을 건드리지 않습니다: $app"; }
  mv "$out" "$app"
  ok "스니펫 ${n}개 설치 · 활성화 등록"
}

# ── Linter ───────────────────────────────────────────────────────────────────
