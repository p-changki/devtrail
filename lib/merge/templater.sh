#!/usr/bin/env bash
# DevTrail — Templater 폴더 매핑 · 데일리노트 병합.
#
# 병합기는 서로를 부르지 않는다. 추가·삭제가 독립적이어야
# 기여자가 파일 하나만 보고 새 병합을 만들 수 있다.
#
# 규약:
#   - 프로파일이 허용할 때만 쓴다 (cfg '.install.mode' → preset/profiles/)
#   - 쓰기 전에 타임스탬프 백업
#   - 플러그인이 없으면 안내만 하고 조용히 넘어간다
#   - ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# ── Templater 폴더매핑 · 데일리노트 ─────────────────────────────────────────
#
# 이 둘이 있어야 "노트를 만들면 양식이 채워진다"가 성립한다.
# trigger_on_file_creation 이 꺼져 있으면 아무 일도 일어나지 않는다.
_ob_templater() {
  local dot="$1"
  local data="$dot/plugins/templater-obsidian/data.json"
  local mode; mode=$(cfg '.install.mode' 'existing')
  local profile="$DEVTRAIL_ROOT/preset/profiles/${mode}.json"
  local paths; paths=$(_ob_paths_json)

  step "$(L "Templater 폴더 매핑" "Templater folder mapping")"
  if [ ! -d "$(dirname "$data")" ]; then
    _d_note "Templater $(L "플러그인이 설치/활성화되지 않았습니다." "plugin is not installed or not enabled.")"
    dim "     $(L "이게 없으면 노트를 만들어도 양식이 채워지지 않습니다." \
                "Without it, new notes come out blank.")"
    return 0
  fi

  local out; out=$(mktemp)
  # ⚠️ DT_TEMPLATER_DIR 로 '설치된 플러그인' 을 가리킨다. 생성기가 거기서
  #    설정 스키마 버전을 읽어 맞는 키를 쓴다 — 짐작하지 않는다.
  if DT_TEMPLATES_DIR="$DEVTRAIL_ROOT/preset/templates/$(dt_lang)" \
     DT_TEMPLATER_DIR="$dot/plugins/templater-obsidian" \
     python3 "$DEVTRAIL_ROOT/lib/gen/hotkeys.py" templater \
      "$DEVTRAIL_ROOT/preset/obsidian/hotkeys.tmpl.json" "$paths" \
      "$([ -f "$data" ] && printf '%s' "$data")" > "$out"; then
    jr_backup "$data" >/dev/null || { rm -f "$out"; die "$(L "백업 실패 — 원본을 건드리지 않습니다" "Backup failed — leaving the original alone"): $data"; }
    mv "$out" "$data"
    local nmap; nmap=$(jq '.folder_templates|length' "$data")
    ok "$(L "매핑 ${nmap}개" "${nmap} mappings") · $(L "새 파일 생성 시 자동 삽입 켬" "auto-insert on new file is on")"
  else
    rm -f "$out"; warn "$(L "매핑 생성 실패 — 건드리지 않습니다" "Could not build the mapping — leaving it alone")"
  fi

  # 데일리노트: 프로파일이 허용할 때만
  local dn="$dot/daily-notes.json"
  local allow; allow=$(jq -r '.merge.daily_notes // false' "$profile" 2>/dev/null)
  if [ "$allow" = "false" ]; then
    dim "     $(L "데일리노트 설정은 이 모드에서 건드리지 않습니다" "This mode leaves daily-note settings alone")"
    return 0
  fi
  if [ "$allow" = "confirm" ] && [ -f "$dn" ]; then
    dim "     $(L "기존 데일리노트 설정이 있습니다 — 유지합니다" "You already have daily-note settings — keeping them")"
    dim "     $(L "바꾸려면 설정 → 데일리 노트 → 폴더" "To change: Settings → Daily notes → Folder"): $(vault_rel "$(dt_dir devlog)")"
    return 0
  fi
  local out2; out2=$(mktemp)
  if python3 "$DEVTRAIL_ROOT/lib/gen/hotkeys.py" daily \
      "$DEVTRAIL_ROOT/preset/obsidian/hotkeys.tmpl.json" "$paths" \
      "$([ -f "$dn" ] && printf '%s' "$dn")" > "$out2"; then
    jr_backup "$dn" >/dev/null || { rm -f "$out2"; die "$(L "백업 실패 — 원본을 건드리지 않습니다" "Backup failed — leaving the original alone"): $dn"; }
    mv "$out2" "$dn"
    ok "$(L "데일리노트" "Daily notes") → $(jq -r '.folder' "$dn")"
  else
    rm -f "$out2"
  fi
}

# ── 단축키 ───────────────────────────────────────────────────────────────────
#
# ⚠️ Templater 커맨드 ID 안에 볼트 경로가 들어간다. 정적 파일을 복사하면
#    루트명이 다른 사용자에게서 단축키가 조용히 죽는다. 조립해서 만든다.
