#!/usr/bin/env bash
# DevTrail — 셋업 계획: "적용하면 무엇이 바뀌는가".
#
# 앱은 이걸 사용자에게 보여준 뒤 동의를 받는다. 그러니 여기서 나오는 값은
# 실제 적용부가 하는 일과 같아야 한다.
#
# ⚠️ 그래서 폴더·템플릿·플러그인 목록을 여기서 새로 계산하지 않는다.
#    적용부가 쓰는 함수(_aug_folders · 프리셋 목록 · pl_installed)를 그대로
#    부른다. 두 번째 계산을 만들면 "계획과 실제가 다르다" 가 되고, 그건
#    사용자 신뢰를 한 번에 잃는 종류다.
#
# ⚠️ plan 은 아무것도 쓰지 않는다. 계산에 설정이 필요하므로 임시 설정을
#    만들어 쓰고 지운다 — 진짜 CONFIG_FILE 은 건드리지 않는다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

# _pl_tmp_config <스펙> <출력경로>
#
# 스펙으로 '적용했다면 생겼을' 설정을 만든다. 실제 적용과 같은 함수를 쓰므로
# 계획이 보는 설정과 적용이 쓰는 설정이 같다.
_pl_tmp_config() {
  local spec="$1" out="$2"
  local backend vault root gh ai
  backend=$(printf '%s' "$spec" | jq -r '.vault.backend')
  vault=$(printf '%s' "$spec"   | jq -r '.vault.path')
  root=$(printf '%s' "$spec"    | jq -r '.vault.root')
  gh=$(printf '%s' "$spec"      | jq -r '.github.user')
  ai=$(printf '%s' "$spec"      | jq -r '.ai.provider')
  (
    sp_export "$spec"
    CONFIG_FILE="$out"
    . "$DEVTRAIL_ROOT/lib/init/prompts.sh"
    . "$DEVTRAIL_ROOT/lib/init/write.sh"
    _init_write_config "$backend" "$vault" "$root" "$gh" "$ai" >/dev/null 2>&1
  )
  [ -f "$out" ]
}

# 만들 폴더 — 이미 있는 것은 뺀다.
_pl_folders() {
  local spec="$1" cfgpath="$2"
  local vault vroot
  vault=$(printf '%s' "$spec" | jq -r '.vault.path')
  vroot=$(printf '%s' "$spec" | jq -r '.vault.root')
  local base="$vault"; [ -n "$vroot" ] && base="$vault/$vroot"

  local mods; mods=$(printf '%s' "$spec" | jq -r '.modules | join("\n")')
  (
    CONFIG_FILE="$cfgpath"
    DEVTRAIL_CONFIG="$cfgpath"; export DEVTRAIL_CONFIG
    . "$DEVTRAIL_ROOT/lib/augmentcmd.sh"
    _aug_folders "$mods" 2>/dev/null
  ) | while IFS=$'\t' read -r key rel hub; do
        [ -n "$rel" ] || continue
        [ -d "$base/$rel" ] && continue
        printf '%s\n' "${vroot:+$vroot/}$rel"
      done | LC_ALL=C sort -u
}

# 깔 템플릿 — 볼트에 없는 것만.
_pl_templates() {
  local spec="$1"
  local lang vault vroot
  lang=$(printf '%s' "$spec"  | jq -r '.lang')
  vault=$(printf '%s' "$spec" | jq -r '.vault.path')
  vroot=$(printf '%s' "$spec" | jq -r '.vault.root')
  local src="$DT_PRESET/templates/$lang"
  [ -d "$src" ] || src="$DT_PRESET/templates/ko"
  local tdir; tdir=$(DEVTRAIL_LANG="$lang" dt_dir templates)
  local base="$vault"; [ -n "$vroot" ] && base="$vault/$vroot"
  local f name
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    case "$name" in _*) continue ;; esac   # 데이터 파일은 템플릿이 아니다
    [ -f "$base/$tdir/$name" ] && continue
    printf '%s\n' "${vroot:+$vroot/}$tdir/$name"
  done | LC_ALL=C sort
}

# 받을 플러그인 — 이미 깔린 것은 건드리지 않는다.
_pl_plugins() {
  local spec="$1"
  [ "$(printf '%s' "$spec" | jq -r '.bootstrap_plugins')" = "true" ] || return 0
  local vault dot
  vault=$(printf '%s' "$spec" | jq -r '.vault.path')
  dot="$vault/.obsidian"
  . "$DEVTRAIL_ROOT/lib/plugins.sh"
  local id rest
  while IFS=$'\t' read -r id rest; do
    [ -n "$id" ] || continue
    pl_installed "$dot" "$id" || printf '%s\n' "$id"
  done <<EOF
$(_pl_rows)
EOF
}

# 병합할 Obsidian 설정 — 프로파일이 허용하는 것만.
#
# ⚠️ 프로파일이 유일한 근거다. 여기에 목록을 손으로 적으면 프로파일을
#    고쳤을 때 계획만 옛말을 하게 된다.
_pl_settings() {
  local spec="$1" mode
  mode=$(printf '%s' "$spec" | jq -r '.vault.mode')
  local profile="$DT_PRESET/profiles/${mode}.json"
  [ -f "$profile" ] || return 0
  jq -r '
    (.merge // {}) | to_entries | map(select(.value != false)) | map(.key) | .[]
  ' "$profile" | while IFS= read -r k; do
    case "$k" in
      shellcommands)   printf '.obsidian/plugins/obsidian-shellcommands/data.json\n' ;;
      auto_note_mover) printf '.obsidian/plugins/auto-note-mover/data.json\n' ;;
      templater)       printf '.obsidian/plugins/templater-obsidian/data.json\n' ;;
      linter)          printf '.obsidian/plugins/obsidian-linter/data.json\n' ;;
      daily_notes)     printf '.obsidian/daily-notes.json\n' ;;
      hotkeys)         printf '.obsidian/hotkeys.json\n' ;;
      app)             printf '.obsidian/app.json\n' ;;
      snippets)        printf '.obsidian/appearance.json\n' ;;
      smart_env)       printf '.obsidian/plugins/smart-connections/data.json\n' ;;
    esac
  done | LC_ALL=C sort -u
}

# 무엇이 아플 수 있는가.
#
# ⚠️ 프로파일에서 읽는다. "새로 시작이면 Automatic" 같은 문장을 여기 박아두면
#    프로파일을 바꿨을 때 계획이 거짓말을 한다.
_pl_risks() {
  local spec="$1"
  local mode vault
  mode=$(printf '%s' "$spec"  | jq -r '.vault.mode')
  vault=$(printf '%s' "$spec" | jq -r '.vault.path')
  local profile="$DT_PRESET/profiles/${mode}.json"

  local trigger; trigger=$(jq -r '.automove.trigger // "Manual"' "$profile" 2>/dev/null)
  if [ "$trigger" = "Automatic" ]; then
    printf '%s\n' "$(L "노트를 저장하면 태그에 따라 폴더가 바뀝니다 (자동 이동 Automatic)" \
                       "Saving a note moves it by tag (auto-move is Automatic)")"
  else
    printf '%s\n' "$(L "자동 이동은 Manual 로 시작합니다 — 직접 실행할 때만 옮깁니다" \
                       "Auto-move starts on Manual — notes move only when you run it")"
  fi

  local app; app=$(jq -r '.merge.app' "$profile" 2>/dev/null)
  if [ "$app" = "true" ]; then
    printf '%s\n' "$(L "Obsidian 에디터 설정을 덮어씁니다 (.obsidian/app.json)" \
                       "Obsidian editor settings are overwritten (.obsidian/app.json)")"
  fi
  [ "$(jq -r '.merge.linter' "$profile" 2>/dev/null)" = "true" ] \
    && printf '%s\n' "$(L "Linter 설정을 덮어씁니다" "Linter settings are overwritten")"

  # 기존 노트가 있는 볼트에 '새로 시작' 을 거는 것은 가장 위험한 조합이다.
  if [ "$mode" = new ] && [ -d "$vault" ]; then
    local n; n=$(find "$vault" -type f -name '*.md' -not -path '*/.obsidian/*' 2>/dev/null | wc -l | tr -d ' ')
    [ "${n:-0}" -ge 10 ] && printf '%s\n' \
      "$(L "노트 ${n}개가 있는 볼트에 '새로 시작' 을 적용합니다" \
          "Applying 'start fresh' to a vault that already has ${n} notes")"
  fi

  [ "$(printf '%s' "$spec" | jq -r '.bootstrap_plugins')" = "true" ] \
    && printf '%s\n' "$(L "GitHub 릴리스에서 플러그인을 내려받아 설치합니다" \
                          "Plugins are downloaded from GitHub releases and installed")"

  [ -f "$CONFIG_FILE" ] \
    && printf '%s\n' "$(L "기존 설정을 백업한 뒤 교체합니다" \
                          "Your current config is backed up, then replaced")"
  return 0
}

# setup_plan <스펙> <json:0|1>
setup_plan() {
  local spec="$1" json="${2:-0}"
  local tmpcfg; tmpcfg=$(mktemp)
  _pl_tmp_config "$spec" "$tmpcfg" \
    || { rm -f "$tmpcfg"; die "$(L "계획을 세우지 못했습니다" "Could not build the plan")"; }

  local folders templates plugins settings risks
  folders=$(_pl_folders "$spec" "$tmpcfg")
  templates=$(_pl_templates "$spec")
  plugins=$(_pl_plugins "$spec")
  settings=$(_pl_settings "$spec")
  risks=$(_pl_risks "$spec")
  rm -f "$tmpcfg"

  if [ "$json" = 1 ]; then
    jq -n \
      --argjson spec "$spec" \
      --argjson folders "$(_dt_json_array "$folders")" \
      --argjson templates "$(_dt_json_array "$templates")" \
      --argjson plugins "$(_dt_json_array "$plugins")" \
      --argjson settings "$(_dt_json_array "$settings")" \
      --argjson risks "$(_dt_json_array "$risks")" '{
        valid: true,
        spec_version: $spec.spec_version,
        mode: $spec.vault.mode,
        vault: $spec.vault.path,
        root: $spec.vault.root,
        risks: $risks,
        changes: {
          folders_create:   $folders,
          templates_create: $templates,
          plugins_install:  $plugins,
          settings_merge:   $settings,
          notes_move:       []
        },
        undo_available: true
      }'
    return 0
  fi

  step "$(L "적용하면 이렇게 됩니다" "Here is what would change")"
  echo
  info "  $(L "볼트" "Vault"): $(printf '%s' "$spec" | jq -r '.vault.path')"
  info "  $(L "설치 방식" "Mode"): $(printf '%s' "$spec" | jq -r '.vault.mode')"
  echo
  _pl_show "$(L "폴더 생성" "Create folders")" "$folders"
  _pl_show "$(L "템플릿 설치" "Install templates")" "$templates"
  _pl_show "$(L "플러그인 설치" "Install plugins")" "$plugins"
  _pl_show "$(L "설정 병합" "Merge settings")" "$settings"
  if [ -n "$risks" ]; then
    echo
    printf '%s\n' "$risks" | while IFS= read -r r; do
      [ -n "$r" ] && warn "$r"
    done
  fi
  echo
  dim "   $(L "되돌릴 수 있습니다" "This can be undone"): devtrail undo"
}

_pl_show() {
  local title="$1" list="$2"
  local n; n=$(printf '%s' "$list" | grep -c . | tr -d ' ')
  [ "${n:-0}" -gt 0 ] || return 0
  ok "${title} ${n}"
  printf '%s\n' "$list" | head -8 | while IFS= read -r x; do
    [ -n "$x" ] && dim "     $x"
  done
  [ "$n" -gt 8 ] && dim "     $(L "… 외 $((n - 8))개" "… and $((n - 8)) more")"
  return 0
}
