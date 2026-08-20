#!/usr/bin/env bash
# DevTrail — Linter (frontmatter 규약) 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── Linter ───────────────────────────────────────────────────────────────────
_ob_linter() {
  local dot="$1" data="$dot/plugins/obsidian-linter/data.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"
  local src="$DEVTRAIL_ROOT/preset/obsidian/linter.json"

  step "Linter (frontmatter 규약)"
  if [ "$(jq -r '.merge.linter // false' "$profile" 2>/dev/null)" != "true" ]; then
    dim "     기존 서식을 지키려고 건드리지 않습니다"
    dim "     직접 켜려면: 설정 → Linter → Lint on save"
    return 0
  fi
  if [ ! -d "$(dirname "$data")" ]; then
    _d_note "Linter 플러그인이 설치되지 않았습니다 (권장)."
    dim "     없으면 frontmatter 의 updated 가 자동 갱신되지 않습니다."
    return 0
  fi
  [ -f "$src" ] || { warn "프리셋 없음: $src"; return 0; }

  local out; out=$(mktemp)
  jq -s '.[0] * (.[1] | del(._comment))' \
    "$([ -f "$data" ] && printf '%s' "$data" || echo /dev/null)" "$src" > "$out" 2>/dev/null \
    || jq 'del(._comment)' "$src" > "$out"

  [ -f "$data" ] && cp "$data" "$data.bak.$(date +%Y%m%d%H%M%S)"
  mv "$out" "$data"
  ok "저장 시 정리 켬 · updated 자동 갱신"
}

# ── RAG 제외 설정 ────────────────────────────────────────────────────────────
#
# 인덱스는 넓히는 게 아니라 좁히는 것이 품질을 만든다.
# 헤딩 제외는 템플릿에서 생성한다 — 손으로 관리하면 반드시 샌다.
