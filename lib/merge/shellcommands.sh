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

# data.json 씨앗 만들기.
#
# 플러그인 폴더는 있는데 data.json 이 없는 상태가 있다 — 우리가 플러그인을
# 설치했지만 Obsidian 이 아직 한 번도 로드하지 않았을 때다. 예전에는 여기서
# "설치 후 재시작하고 다시 실행하세요" 로 넘어갔고, 그러면 단축키가 동작하지
# 않는 채로 셋업이 끝났다.
#
# ⚠️ settings_version 이 틀리면 플러그인이 '지원하지 않는 설정 파일' 로 보고
#    스스로를 끈다. 그래서 값을 짐작하지 않고 플러그인 코드에서 읽는다.
#    못 읽으면 만들지 않는다 — 틀린 파일을 쓰느니 안내가 낫다.
#
# 나머지 필드는 비워도 된다. 플러그인이 로드할 때 기본값과 합친다
# (loadSettings → combineObjects(getDefaultSettings(false), loaded)).
_ob_sc_seed() {
  local dir="$1" data="$2"
  [ -f "$dir/main.js" ] || return 1
  local ver
  ver=$(grep -o 'SettingsVersion *= *"[^"]*"' "$dir/main.js" 2>/dev/null \
        | head -1 | sed 's/.*"\(.*\)"/\1/')
  [ -n "$ver" ] || return 1
  jq -n --arg v "$ver" '{settings_version: $v, shell_commands: []}' > "$data" 2>/dev/null || return 1
  jr_created "$data"
  return 0
}

# ── 셸 커맨드 병합 ───────────────────────────────────────────────────────────
_ob_shellcommands() {
  local dot="$1"
  local data="$dot/plugins/obsidian-shellcommands/data.json"
  local src="$DEVTRAIL_ROOT/templates/obsidian/shellcommands.json"

  step "Shell commands"

  if [ ! -f "$data" ]; then
    if _ob_sc_seed "$dot/plugins/obsidian-shellcommands" "$data"; then
      dim "     $(L "설정 파일이 없어 새로 만들었습니다" "No settings file — created one")"
    else
      _d_note "Shell commands $(L "플러그인이 설치/활성화되지 않았습니다." "plugin is not installed or not enabled.")"
      dim "     $(L "설치 후 Obsidian 을 재시작하고 다시 실행하세요." \
                  "Install it, restart Obsidian, then run this again.")"
      dim "     $(L "경로" "Path"): $data"
      return 0
    fi
  fi
  [ -f "$src" ] || { warn "$(L "템플릿 없음" "Template missing"): $src"; return 0; }

  # {{DEVTRAIL_HOME}} 치환
  local rendered; rendered=$(mktemp)
  sed "s|{{DEVTRAIL_HOME}}|$DEVTRAIL_HOME|g" "$src" > "$rendered"

  if ! jq -e . "$rendered" >/dev/null 2>&1; then
    rm -f "$rendered"; die "$(L "셸 커맨드 템플릿이 유효한 JSON 이 아닙니다" "The shell-command template is not valid JSON")"
  fi

  # 백업 실패를 확인하지 않으면, 백업 없이 원본을 교체하고도
  # 사용자에게는 "백업했다"고 말하게 된다. README의 안전 계약이 거짓이 된다.
  local backup
  backup=$(jr_backup "$data") || { rm -f "$rendered"; die "$(L "백업 실패 — 원본을 건드리지 않습니다" "Backup failed — leaving the original alone"): $data"; }

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
    die "$(L "병합 실패 — 원본은 그대로입니다" "Merge failed — the original is untouched"): $data"
  fi

  if ! jq -e '.shell_commands | length > 0' "$merged" >/dev/null 2>&1; then
    rm -f "$rendered" "$merged"
    die "$(L "병합 결과가 비정상입니다 — 원본 유지" "The merge result looks wrong — keeping the original"): $data"
  fi

  mv "$merged" "$data"
  rm -f "$rendered"

  local n; n=$(jq '.shell_commands | length' "$data")
  ok "$(L "셸 커맨드 병합 완료" "Shell commands merged") (${n})"
  dim "     $(L "백업" "Backup"): $backup"
}

# ── 태그 → 폴더 라우팅 ───────────────────────────────────────────────────────
#
# ⚠️ 기존 볼트에서 이걸 Automatic 으로 켜면, 사용자가 기존 노트를 열어 저장하는
#    순간 태그에 따라 폴더가 바뀐다. 데이터가 사라지진 않지만 "내 노트가 어디
#    갔지"가 되는, 신뢰를 한 번에 잃는 종류다.
#    프로파일이 기존 모드에서 Manual 을 쓰는 이유이고, 우리가 만들지 않은
#    폴더를 전부 제외 목록에 넣는 이유다.
