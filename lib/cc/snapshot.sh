# Obsidian 이 꺼져 있어도 답하는 상태 — 메뉴바 앱이 이것만 소비한다.
#
# ⚠️ 집계 규칙은 plugin/main.js 의 collect() 에도 있다. 두 벌이다.
#    tests/test-snapshot.sh 가 같은 볼트에서 둘을 실제로 돌려 비교한다 —
#    어긋나면 빨간불이다 (ADR 0003).

# ── Snapshot ─────────────────────────────────────────────────────────────────
#
# Obsidian 이 꺼져 있어도 답한다. 메뉴바 앱이 이것만 소비하고, Markdown 이나
# 경로 규칙을 스스로 해석하지 않는다.
#
# ⚠️ 읽기 전용이다. 네트워크도 쓰지 않는다.
# ⚠️ 모르는 것은 unknown 이나 null 이다. 0 이나 false 로 사실을 꾸며내면
#    화면이 "확인해 봤더니 없다" 고 말하게 되는데, 실은 못 본 것이다.
_cc_snapshot() {
  local limit=5
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) : ;;
      --limit) shift; limit="${1:-5}" ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq; require_gen

  local root today devlog_rel devlog_path tpl_rel projects_rel
  root=$(vault_root)
  today=$(date +%F)
  # 경로는 dt_dir 하나에서만 온다.
  tpl_rel=$(dt_dir templates)
  projects_rel=$(dt_dir projects)
  devlog_rel=$(dt_dir devlog)
  devlog_path=""
  # ⚠️ 파일명은 dt_devlog_name 하나에서만 온다.
  [ -n "$devlog_rel" ] && devlog_path="$root/$devlog_rel/$(dt_devlog_name "$today")"

  local vault_state
  vault_state=$(dt_gen gen-snapshot \
    "$(jq -nc --arg r "$root" --arg t "$tpl_rel" --arg p "$projects_rel" --arg d "$devlog_path" \
         --arg today "$today" --argjson lim "$limit" \
         '{root:$r, templates_rel:$t, projects_rel:$p, devlog_path:$d, today:$today, limit:$lim}')" \
    2>/dev/null) || vault_state=""
  [ -n "$vault_state" ] || vault_state='{"available":false}'

  # Command Center 와 Obsidian 상태는 이미 있는 것을 재사용한다.
  local cc; cc=$(_cc_status --json 2>/dev/null) || cc='{}'
  . "$DEVTRAIL_ROOT/lib/obsidian_app.sh"
  local running=false; oa_running && running=true

  jq -n --argjson vault "$vault_state" --argjson cc "$cc" \
        --argjson running "$running" --arg root "$root" '{
    configured: true,
    vault: { available: ($vault.available // false), path: $root },
    today: ($vault.today // null),
    projects: ($vault.projects // null),
    inbox: ($vault.inbox // null),
    notes: ($vault.notes // null),
    recent: ($vault.recent // null),
    command_center: {
      installed: ($cc.installed // "unknown"),
      enabled: ($cc.enabled // "unknown"),
      installed_version: ($cc.installed_version // "unknown"),
      available_version: ($cc.available_version // "unknown"),
      update_state: ($cc.update_state // "unknown"),
      restart_recommended: ($cc.restart_required // false)
    },
    obsidian: { running: $running }
  }'
}
