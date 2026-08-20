#!/usr/bin/env bash
# DevTrail — Obsidian 셸 커맨드 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

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
