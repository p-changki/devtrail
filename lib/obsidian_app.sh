#!/usr/bin/env bash
# DevTrail — Obsidian 앱 자체를 다룬다 (볼트 '안'이 아니라 '밖').
#
# lib/obsidian.sh 는 볼트 안의 .obsidian/* 를 병합한다.
# 이 파일은 그 바깥 — 앱이 깔려 있나, 사용자가 어떤 볼트를 갖고 있나,
# 새 볼트를 Obsidian 에 어떻게 알리나 를 담당한다.
#
# 왜 나눴나: 볼트 안의 병합은 Obsidian 이 없어도 의미가 있다(CI·테스트).
# 앱 레지스트리는 macOS 의 Obsidian 설치에만 의미가 있다.
#
# ⚠️ 레지스트리는 Obsidian 이 '종료할 때' 자기 상태로 덮어쓴다.
#    실행 중에 우리가 쓰면 조용히 사라진다 — 반드시 oa_running 을 먼저 본다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── 앱 ───────────────────────────────────────────────────────────────────────
oa_app_path() {
  local p
  for p in "/Applications/Obsidian.app" "$HOME/Applications/Obsidian.app"; do
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

oa_installed() { oa_app_path >/dev/null 2>&1; }

# 실행 중인가.
#
# pgrep 만으로는 부족했다 — Obsidian 의 프로세스 이름은 헬퍼 프로세스와 섞여
# 있어서 잔여 헬퍼에 걸리면 멀쩡한 셋업이 "실행 중"으로 막힌다.
# osascript 는 앱 등록 여부를 보므로 이 판정에 더 맞다.
oa_running() {
  if has osascript; then
    [ "$(osascript -e 'application "Obsidian" is running' 2>/dev/null)" = "true" ]
    return $?
  fi
  pgrep -x Obsidian >/dev/null 2>&1
}

# ── 레지스트리 ───────────────────────────────────────────────────────────────
# ⚠️ 환경변수로 갈아끼울 수 있어야 한다. 이게 없으면 테스트가 실행하는
#    머신의 진짜 볼트 목록을 읽는다 — 실제로 test-i18n 이 사용자의 볼트를
#    골라 들어가 거기에 폴더를 만들었다. DEVTRAIL_CONFIG·DEVTRAIL_JOURNAL 과
#    같은 성격의 봉합 지점이다.
oa_registry_file() {
  printf '%s' "${DEVTRAIL_OBSIDIAN_REGISTRY:-$HOME/Library/Application Support/obsidian/obsidian.json}"
}

# 볼트 ID. Obsidian 은 16자리 hex 를 쓴다.
#
# 무작위가 아니라 경로의 해시를 쓴다. 같은 볼트를 두 번 등록해도 항목이
# 하나만 남아야 한다 — 무작위면 재실행할 때마다 목록이 불어난다.
oa_vault_id() {
  local h=""
  if has md5; then h=$(printf '%s' "$1" | md5)
  elif has md5sum; then h=$(printf '%s' "$1" | md5sum | cut -d' ' -f1)
  elif has python3; then
    h=$(python3 -c 'import sys,hashlib; print(hashlib.md5(sys.argv[1].encode()).hexdigest())' "$1")
  else
    # 최후의 수단. hex 는 아니지만 키로만 쓰이므로 길이만 맞추면 된다.
    h=$(printf '%s' "$1" | cksum | tr -d ' ')
    h="${h}0000000000000000"
  fi
  printf '%s' "$h" | head -c 16
}

# 등록된 볼트를 한 줄에 하나씩: <경로>
# 존재하지 않는 폴더는 뺀다 — 사용자가 지운 볼트를 목록에 보여주면 안 된다.
oa_vaults() {
  local f; f=$(oa_registry_file)
  [ -f "$f" ] || return 0
  local p
  jq -r '(.vaults // {}) | to_entries | sort_by(.value.ts // 0) | reverse
         | .[] | .value.path // empty' "$f" 2>/dev/null | while IFS= read -r p; do
    [ -n "$p" ] && [ -d "$p" ] && printf '%s\n' "$p"
  done
}

# 볼트를 Obsidian 에 등록한다. 이미 있으면 아무것도 하지 않는다.
#
# 실패해도 치명적이지 않다 — 사용자가 Obsidian 에서 직접 열면 된다.
# 그래서 die 하지 않고 반환값으로 알린다.
oa_register() {
  local vault="$1"
  local f; f=$(oa_registry_file)
  local id; id=$(oa_vault_id "$vault")

  mkdir -p "$(dirname "$f")" || return 1

  if [ ! -f "$f" ]; then
    printf '%s\n' '{"vaults":{}}' > "$f" || return 1
    jr_created "$f"
  else
    jq -e --arg p "$vault" '(.vaults // {}) | to_entries | map(select(.value.path == $p)) | length > 0' \
       "$f" >/dev/null 2>&1 && return 0
    jr_backup "$f" >/dev/null || return 1
  fi

  local tmp; tmp=$(mktemp)
  jq --arg id "$id" --arg p "$vault" --argjson ts "$(date +%s)000" \
     '.vaults = ((.vaults // {}) + {($id): {path: $p, ts: $ts}})' "$f" > "$tmp" \
    && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  return 0
}

# 볼트를 연다. 등록돼 있어야 Obsidian 이 경로를 안다.
oa_open() {
  local vault="$1"
  oa_installed || return 1
  if has python3; then
    local enc
    enc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$vault" 2>/dev/null)
    [ -n "$enc" ] && { open "obsidian://open?path=$enc" >/dev/null 2>&1 && return 0; }
  fi
  open -a "$(oa_app_path)" >/dev/null 2>&1
}

# 볼트의 노트 수. 목록에서 "어느 게 내 진짜 볼트인지" 를 가르는 유일한 단서다.
#
# 전체 scan 을 돌리지 않는다 — 볼트가 여러 개면 목록 하나 띄우는 데 몇 초씩
# 걸린다. 여기서 필요한 건 정확한 수가 아니라 규모다.
oa_note_count() {
  local n
  n=$(find "$1" -type f -name '*.md' -not -path '*/.obsidian/*' 2>/dev/null | wc -l | tr -d ' ')
  printf '%s' "${n:-0}"
}

# ── 볼트 안 ──────────────────────────────────────────────────────────────────
# .obsidian/ 을 만든다.
#
# 예전에는 "Obsidian 에서 한 번 열고 다시 실행하세요" 라고 막았다.
# 그런데 .obsidian 은 그냥 폴더다 — 우리가 만들면 Obsidian 이 그대로 읽는다.
# 그 한 줄의 die 때문에 사용자가 터미널과 GUI 를 왕복해야 했다.
#
# 내용은 비워둔다. 실제 설정은 lib/merge/* 가 얹는다 — 여기서 값을 정하면
# 기본값의 출처가 둘로 갈린다.
oa_ensure_dot() {
  local vault="$1"
  local dot="$vault/.obsidian"
  [ -d "$dot" ] && return 0
  jr_mkdir "$dot" || return 1
  return 0
}
