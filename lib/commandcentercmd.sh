#!/usr/bin/env bash
# DevTrail — `devtrail command-center <install|enable|disable|status|uninstall>`
#
# 우리가 만든 Obsidian 플러그인을 볼트에 넣고 켠다.
#
# ⚠️ 우리 것이라고 예외를 두지 않는다. 남의 플러그인에 적용하는 안전 계약이
#    우리 것에는 필요 없다고 말할 근거가 없다 — dry-run 기본, 저널·되돌리기,
#    기존 목록 보존. [ADR 0002](../docs/decisions/0002-command-center.md)
#
# ⚠️ 빌드 도구를 쓰지 않으므로(ADR 0002 D3) plugin/ 이 곧 배포물이다.
#    번들을 받아올 릴리스도, 내려받는 경로도 필요 없다. 저장소에서 복사한다.
#
# ⚠️ 설치와 활성화를 나눈다. 기존 볼트에는 opt-in 이어야 한다 —
#    설치했다고 남의 볼트에서 자동으로 켜지면 안 된다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

. "$DEVTRAIL_ROOT/lib/plugins.sh"       # _pl_enable · pl_installed · pl_enabled
. "$DEVTRAIL_ROOT/lib/obsidian_app.sh"  # oa_warn_if_running

DT_CC_ID="devtrail-command-center"
# ⚠️ 테스트가 '깨진 원본' 을 흉내낼 수 있어야 검증 실패 경로를 확인한다.
#    DEVTRAIL_CONFIG·DEVTRAIL_JOURNAL 과 같은 성격의 봉합 지점이다.
DT_CC_SRC="${DT_CC_SRC_OVERRIDE:-$DEVTRAIL_ROOT/plugin}"

_cc_dot() { printf '%s/.obsidian' "$(vault_path)"; }
_cc_dest() { printf '%s/plugins/%s' "$(_cc_dot)" "$DT_CC_ID"; }

# 배포물 목록. manifest 와 main 은 필수, styles 는 있으면 함께 간다.
_cc_files() {
  local f
  for f in ${DT_CC_FILES_OVERRIDE:-manifest.json main.js styles.css}; do
    [ -f "$DT_CC_SRC/$f" ] && printf '%s\n' "$f"
  done
}

_cc_require_src() {
  [ -f "$DT_CC_SRC/manifest.json" ] && [ -f "$DT_CC_SRC/main.js" ] \
    || die "$(L "플러그인 원본이 없습니다" "The plugin source is missing"): $DT_CC_SRC"
  # ⚠️ manifest 의 id 가 우리가 아는 값과 다르면 엉뚱한 폴더에 깔린다.
  local got; got=$(jq -r '.id // ""' "$DT_CC_SRC/manifest.json" 2>/dev/null)
  [ "$got" = "$DT_CC_ID" ] \
    || die "$(L "manifest 의 id 가 다릅니다" "The manifest id does not match"): $got"
}

# ── 설치 ─────────────────────────────────────────────────────────────────────
_cc_install() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done

  require_config
  require_bins jq
  _cc_require_src

  local dot; dot=$(_cc_dot)
  local dest; dest=$(_cc_dest)
  local ver; ver=$(jq -r '.version' "$DT_CC_SRC/manifest.json")

  step "$(L "Command Center 설치" "Install Command Center")"
  info "  $DT_CC_ID  $ver"
  dim "   $(L "설치 위치" "Destination"): $dest"
  local f
  _cc_files | while IFS= read -r f; do dim "     $f"; done

  if [ "$apply" != 1 ]; then
    echo
    dim "   $(L "설치해도 켜지지는 않습니다" "Installing does not enable it")"
    dim "   $(L "적용" "Apply"): devtrail command-center install --apply"
    return 0
  fi

  [ -d "$dot" ] || die "$(L "Obsidian 설정 폴더가 없습니다" "No Obsidian config folder"): $dot
   $(L "먼저" "Run first"): devtrail obsidian"

  jr_begin command-center-install
  jr_mkdir "$dest" || { jr_end; die "$(L "폴더 생성 실패" "Could not create folder"): $dest"; }

  local ok_n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # ⚠️ 있던 파일은 덮어쓰기 전에 백업한다. 사용자가 고쳤을 수 있다.
    if [ -f "$dest/$f" ]; then
      jr_backup "$dest/$f" >/dev/null \
        || { jr_end; die "$(L "백업 실패 — 원본을 건드리지 않습니다" \
                             "Backup failed — leaving the original alone"): $dest/$f"; }
      cp "$DT_CC_SRC/$f" "$dest/$f" || { jr_end; die "$(L "복사 실패" "Copy failed"): $f"; }
    else
      cp "$DT_CC_SRC/$f" "$dest/$f" || { jr_end; die "$(L "복사 실패" "Copy failed"): $f"; }
      jr_created "$dest/$f"
    fi
    ok_n=$((ok_n + 1))
  done <<EOF
$(_cc_files)
EOF

  ok "$(L "파일 ${ok_n}개 설치" "${ok_n} files installed")"
  oa_warn_if_running || true
  dim "   $(L "켜기" "Enable"): devtrail command-center enable --apply"
  jr_end
}

# ── 켜기·끄기 ────────────────────────────────────────────────────────────────
_cc_enable() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq
  local dot; dot=$(_cc_dot)

  pl_installed "$dot" "$DT_CC_ID" \
    || die "$(L "아직 설치되지 않았습니다" "Not installed yet")
   devtrail command-center install --apply"

  step "$(L "Command Center 켜기" "Enable Command Center")"
  if pl_enabled "$dot" "$DT_CC_ID"; then
    dim "   $(L "이미 켜져 있습니다" "Already enabled")"; return 0
  fi
  if [ "$apply" != 1 ]; then
    dim "   $(L "(dry-run — 실제로 켜려면 --apply)" "(dry run — pass --apply to enable)")"
    dim "   community-plugins.json += $DT_CC_ID"
    return 0
  fi

  jr_begin command-center-enable
  _pl_enable "$dot" "$DT_CC_ID" \
    || { jr_end; die "$(L "켜지 못했습니다" "Could not enable it")"; }
  ok "$(L "켰습니다" "Enabled")"
  oa_warn_if_running \
    || dim "   $(L "Obsidian 을 열면 보입니다" "It shows up when you open Obsidian")"
  jr_end
}

_cc_disable() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq
  local dot; dot=$(_cc_dot)
  local f="$dot/community-plugins.json"

  step "$(L "Command Center 끄기" "Disable Command Center")"
  if ! pl_enabled "$dot" "$DT_CC_ID"; then
    dim "   $(L "이미 꺼져 있습니다" "Already disabled")"; return 0
  fi
  if [ "$apply" != 1 ]; then
    dim "   $(L "(dry-run — 실제로 끄려면 --apply)" "(dry run — pass --apply to disable)")"
    dim "   $(L "파일은 지우지 않습니다" "Files are kept")"
    return 0
  fi

  jr_begin command-center-disable
  jr_backup "$f" >/dev/null \
    || { jr_end; die "$(L "백업 실패 — 원본을 건드리지 않습니다" \
                         "Backup failed — leaving the original alone"): $f"; }
  local tmp; tmp=$(mktemp)
  # ⚠️ 우리 id 만 뺀다. 목록을 다시 쓰면 사용자의 플러그인이 전부 꺼진다.
  jq --arg p "$DT_CC_ID" 'map(select(. != $p))' "$f" > "$tmp" && mv "$tmp" "$f" \
    || { rm -f "$tmp"; jr_end; die "$(L "끄지 못했습니다" "Could not disable it")"; }
  ok "$(L "껐습니다" "Disabled")"
  oa_warn_if_running || true
  dim "   $(L "파일은 남아 있습니다" "The files are still there"): $(_cc_dest)"
  jr_end
}

# ── 업데이트 ─────────────────────────────────────────────────────────────────
#
# 배포 경로는 하나다 — 저장소의 plugin/ 이 곧 배포물이다(ADR 0002 D3).
# `devtrail update`(git pull)가 소스를 갱신하고, 이 명령이 그것을 볼트에
# 반영한다. 별도 다운로드 경로를 만들지 않는다 — 두 경로가 서로 다른 버전을
# 가져오면 사용자가 어느 게 진짜인지 모른다.
#
# ⚠️ 감지는 쉽게, 적용은 승인 후에만. 실행 중인 Obsidian 아래에서 파일을
#    갈아치우면 로딩 상태가 꼬인다.

# 버전을 자릿수로 비교한다.
#
# ⚠️ 문자열 비교로는 1.10.0 이 1.9.0 보다 작다고 나온다. 실제로 다음 릴리스에서
#    바로 틀릴 수 있는 종류의 버그다.
# ⚠️ bash 3.2 다 — 배열 없이 IFS 로 자른다.
#
# -1 (a<b) · 0 (a=b) · 1 (a>b)
_cc_semver_cmp() {
  local a="$1" b="$2" i x y oldifs
  oldifs="$IFS"
  for i in 1 2 3; do
    IFS='.'; set -- $a; eval "x=\${$i:-0}"
    set -- $b; eval "y=\${$i:-0}"
    IFS="$oldifs"
    # 숫자가 아닌 자리(프리릴리스 등)는 0 으로 본다 — 짐작해서 순서를 만들지 않는다.
    case "$x" in ''|*[!0-9]*) x=0 ;; esac
    case "$y" in ''|*[!0-9]*) y=0 ;; esac
    [ "$x" -gt "$y" ] && { IFS="$oldifs"; printf '1\n'; return 0; }
    [ "$x" -lt "$y" ] && { IFS="$oldifs"; printf -- '-1\n'; return 0; }
  done
  IFS="$oldifs"
  printf '0\n'
}

# 원본이 통째로 멀쩡한가. 하나라도 어긋나면 설치본을 건드리지 않는다.
#
# ⚠️ 값을 돌려주지 않는다. 값을 받으려면 호출부가 $( ) 를 써야 하는데, 그러면
#    안에서 부른 die 가 **서브셸만** 죽이고 호출한 쪽은 계속 실행된다 —
#    "거부했다" 는 메시지를 내면서 종료 코드 0 으로 끝난다.
#    이 저장소는 setup 의 sp_validate 에서 같은 결함을 이미 한 번 고쳤다.
#    버전이 필요하면 검증 뒤에 _cc_src_version 을 따로 부른다.
_cc_validate_src() {
  _cc_require_src
  jq empty "$DT_CC_SRC/manifest.json" >/dev/null 2>&1 \
    || die "$(L "manifest 가 올바른 JSON 이 아닙니다" "The manifest is not valid JSON"): $DT_CC_SRC/manifest.json"
  local v; v=$(jq -r '.version // ""' "$DT_CC_SRC/manifest.json" 2>/dev/null)
  [ -n "$v" ] \
    || die "$(L "manifest 에 version 이 없습니다 — 무엇으로 바꾸는지 알 수 없습니다" \
               "The manifest has no version — there is no way to tell what this would install")"
  # 필수 파일이 다 있고 읽히는가.
  local f
  for f in manifest.json main.js styles.css; do
    [ -r "$DT_CC_SRC/$f" ] \
      || die "$(L "원본에 필수 파일이 없습니다 — 절반만 바꾸지 않습니다" \
                 "The source is missing a required file — refusing a partial update"): $f"
  done
}

_cc_src_version()  { jq -r '.version // ""' "$DT_CC_SRC/manifest.json" 2>/dev/null; }
_cc_inst_version() { jq -r '.version // ""' "$(_cc_dest)/manifest.json" 2>/dev/null; }

_cc_update() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq

  # ⚠️ 원본을 통째로 검증한 뒤에만 진행한다. 절반만 바뀐 플러그인이 최악이다 —
  #    manifest 는 새 버전인데 코드는 옛것이면 Obsidian 이 무엇을 로드했는지
  #    아무도 모른다.
  _cc_validate_src
  local want; want=$(_cc_src_version)

  local dest; dest=$(_cc_dest)
  step "$(L "Command Center 업데이트" "Update Command Center")"

  if [ ! -f "$dest/manifest.json" ]; then
    dim "   $(L "설치되어 있지 않습니다" "Not installed")"
    dim "   devtrail command-center install --apply"
    return 0
  fi

  local have; have=$(_cc_inst_version)
  info "  $(L "설치됨" "Installed"): ${have:-unknown}"
  info "  $(L "저장소" "Repository"): ${want}"

  if [ -z "$have" ]; then
    warn "$(L "설치본의 버전을 읽을 수 없습니다" "Cannot read the installed version")"
    dim "   $(L "다시 설치하세요" "Reinstall"): devtrail command-center install --apply"
    return 0
  fi

  local cmp; cmp=$(_cc_semver_cmp "$want" "$have")
  if [ "$cmp" = "0" ]; then
    echo; ok "$(L "최신입니다" "Already up to date")"
    return 0
  fi
  # ⚠️ 설치본이 더 새로우면 되돌리지 않는다. 사용자가 손으로 넣었을 수도 있고,
  #    말없이 낮추면 그 사람이 쓰던 기능이 사라진다.
  if [ "$cmp" = "-1" ]; then
    echo
    warn "$(L "설치본이 더 새롭습니다 — 낮추지 않습니다" \
             "The installed copy is newer — not downgrading")"
    dim "   ${have} > ${want}"
    return 0
  fi

  echo
  local f
  _cc_files | while IFS= read -r f; do dim "     $f"; done

  if [ "$apply" != 1 ]; then
    echo
    dim "   $(L "(dry-run — 실제로 바꾸려면 --apply)" "(dry run — pass --apply to update)")"
    dim "   $(L "노트·단축키·활성 목록은 건드리지 않습니다" \
               "Your notes, hotkeys and enabled list are untouched")"
    dim "   $(L "적용" "Apply"): devtrail command-center update --apply"
    return 0
  fi

  # ── 스테이징 ──────────────────────────────────────────────────────────────
  # 새 파일 전체를 임시 자리에 먼저 모아 읽히는지 확인한다. 여기서 실패하면
  # 설치 폴더는 손도 대지 않은 상태다.
  local stage; stage=$(mktemp -d "${TMPDIR:-/tmp}/devtrail-cc.XXXXXX") \
    || die "$(L "임시 폴더를 만들지 못했습니다" "Could not create a temporary directory")"
  local staged=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cp "$DT_CC_SRC/$f" "$stage/$f" 2>/dev/null || {
      rm -rf "$stage"
      die "$(L "원본을 읽지 못했습니다 — 설치본을 건드리지 않았습니다" \
               "Could not read the source — the installed copy was left alone"): $f"
    }
    staged=$((staged + 1))
  done <<EOF
$(_cc_files)
EOF
  [ "$staged" -gt 0 ] || { rm -rf "$stage"; die "$(L "옮길 파일이 없습니다" "Nothing to install")"; }

  # ── 교체 ──────────────────────────────────────────────────────────────────
  jr_begin command-center-update
  local failed=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$dest/$f" ]; then
      jr_backup "$dest/$f" >/dev/null || { failed="$f"; break; }
    else
      # ⚠️ 없던 파일은 created 로 남긴다 — 그래야 undo 가 지울 수 있다.
      #    백업만 남기면 undo 가 '되돌릴 내용' 을 못 찾아 새 파일이 살아남는다.
      jr_created "$dest/$f"
    fi
    cp "$stage/$f" "$dest/$f" || { failed="$f"; break; }
  done <<EOF
$(_cc_files)
EOF
  rm -rf "$stage"

  if [ -n "$failed" ]; then
    # 여기까지 바꾼 것을 되돌린다 — 부분 업데이트 상태로 두지 않는다.
    warn "$(L "교체 중 실패했습니다 — 되돌립니다" "The swap failed — rolling back"): $failed"
    # ⚠️ 지금 job 을 그대로 되감는다. 부분 업데이트 상태로 두면 manifest 와
    #    코드가 어긋난 채 남는다.
    local job="$DT_JOB"
    jr_end
    jr_undo "$job" --apply >/dev/null 2>&1 \
      || warn "$(L "되돌리기도 실패했습니다" "The rollback failed too"): devtrail undo $job"
    die "$(L "업데이트하지 못했습니다. 설치본은 그대로입니다" \
             "Could not update. The installed copy is unchanged")"
  fi

  ok "$(L "${have} → ${want}" "${have} → ${want}")"
  oa_warn_if_running || dim "   $(L "다음에 Obsidian 을 열면 적용됩니다" "It applies next time you open Obsidian")"
  dim "   $(L "되돌리기" "Undo"): devtrail undo"
  jr_end
}

# ── 상태 ─────────────────────────────────────────────────────────────────────
_cc_status() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq
  local dot; dot=$(_cc_dot)
  local dest; dest=$(_cc_dest)

  local installed=false enabled=false
  pl_installed "$dot" "$DT_CC_ID" && installed=true
  pl_enabled   "$dot" "$DT_CC_ID" && enabled=true

  # ⚠️ 모르는 것은 지어내지 않는다. 확인할 수 없으면 unknown 이다 —
  #    0 이나 false 로 채우면 화면이 사실이 아닌 것을 말하게 된다.
  local have want minapp
  have=$(_cc_inst_version); [ -n "$have" ] || have=unknown
  want=$(_cc_src_version);  [ -n "$want" ] || want=unknown
  minapp=$(jq -r '.minAppVersion // ""' "$DT_CC_SRC/manifest.json" 2>/dev/null)
  [ -n "$minapp" ] || minapp=unknown

  # ⚠️ '다르다' 와 '더 새롭다' 는 다른 사실이다. 설치본이 앞서 있는데
  #    update_available: true 라고 말하면 화면이 거짓을 말한다.
  local upd=unknown state=unknown
  if [ "$have" != unknown ] && [ "$want" != unknown ]; then
    case "$(_cc_semver_cmp "$want" "$have")" in
      0)  upd=false; state=up_to_date ;;
      1)  upd=true;  state=update_available ;;
      -1) upd=false; state=installed_newer ;;
    esac
  fi

  # 실행 중이면 지금 바꾼 것이 아직 안 보인다.
  . "$DEVTRAIL_ROOT/lib/obsidian_app.sh"
  local restart=false
  oa_running && restart=true

  # 연동 상태 — 있는 것만 사실대로. 명령 id 는 Obsidian 안에서만 알 수 있어
  # 여기서는 '플러그인이 깔려 있고 켜져 있는가' 까지만 답한다.
  local tpl=unknown omni=unknown
  if [ -d "$dot" ]; then
    tpl=false;  pl_installed "$dot" templater-obsidian && pl_enabled "$dot" templater-obsidian && tpl=true
    omni=false; pl_installed "$dot" omnisearch        && pl_enabled "$dot" omnisearch        && omni=true
  fi

  if [ "$json" = 1 ]; then
    jq -n --arg id "$DT_CC_ID" \
      --argjson i "$installed" --argjson e "$enabled" \
      --arg have "$have" --arg want "$want" --arg upd "$upd" \
      --arg state "$state" \
      --arg minapp "$minapp" --argjson restart "$restart" \
      --arg tpl "$tpl" --arg omni "$omni" --arg dest "$dest" '{
        id: $id,
        installed: $i,
        enabled: $e,
        installed_version: $have,
        available_version: $want,
        update_available: (if $upd == "unknown" then "unknown" else ($upd == "true") end),
        update_state: $state,
        min_app_version: $minapp,
        restart_required: $restart,
        install_path: $dest,
        integrations: {
          templater: (if $tpl == "unknown" then "unknown" else ($tpl == "true") end),
          omnisearch: (if $omni == "unknown" then "unknown" else ($omni == "true") end)
        }
      }'
    return 0
  fi

  step "Command Center"
  if [ "$installed" = true ]; then ok "$(L "설치됨" "Installed") ${have}"
  else warn "$(L "설치되지 않음" "Not installed")"; fi
  if [ "$enabled" = true ]; then ok "$(L "켜짐" "Enabled")"
  else dim "   $(L "꺼짐" "Disabled")"; fi
  if [ "$upd" = true ]; then
    warn "$(L "업데이트 있음" "Update available"): ${have} → ${want}"
    dim "   devtrail command-center update"
  elif [ "$state" = installed_newer ]; then
    warn "$(L "설치본이 더 새롭습니다" "The installed copy is newer"): ${have} > ${want}"
    dim "   $(L "낮추지 않습니다" "Not downgrading")"
  elif [ "$upd" = false ]; then
    ok "$(L "최신" "Up to date")"
  fi
  dim "   $(L "Obsidian 최소 버전" "Minimum Obsidian"): ${minapp}"
  [ "$restart" = true ] && dim "   $(L "Obsidian 실행 중 — 바꾼 것은 재시작 뒤 보입니다" \
                                     "Obsidian is running — changes show after a restart")"
  return 0
}

# ── 제거 ─────────────────────────────────────────────────────────────────────
_cc_uninstall() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      *) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
    esac
    shift
  done
  require_config; require_bins jq
  local dest; dest=$(_cc_dest)

  step "$(L "Command Center 제거" "Remove Command Center")"
  [ -d "$dest" ] || { dim "   $(L "설치되어 있지 않습니다" "Not installed")"; return 0; }
  dim "   $dest"
  if [ "$apply" != 1 ]; then
    dim "   $(L "(dry-run — 실제로 지우려면 --apply)" "(dry run — pass --apply to remove)")"
    return 0
  fi

  jr_begin command-center-uninstall
  _cc_disable --apply >/dev/null 2>&1 || true
  # ⚠️ 우리가 깐 폴더만 지운다. 이 안에 사용자가 넣은 것은 없다고 가정하지
  #    않는다 — rm -rf 대신 우리 파일만 지우고 폴더는 비었을 때만 지운다.
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$dest/$f"
  done <<EOF
$(_cc_files)
EOF
  rmdir "$dest" 2>/dev/null || warn "$(L "비어 있지 않아 폴더는 남겨둡니다" \
                                       "Not empty — leaving the folder"): $dest"
  ok "$(L "제거 완료" "Removed")"
  jr_end
}

command_center_cmd() {
  local sub="${1:-status}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    install)   _cc_install "$@" ;;
    update)    _cc_update "$@" ;;
    enable)    _cc_enable "$@" ;;
    disable)   _cc_disable "$@" ;;
    status)    _cc_status "$@" ;;
    uninstall) _cc_uninstall "$@" ;;
    *) die "$(L "알 수 없는 하위 명령" "Unknown subcommand"): $sub  (install|update|enable|disable|status|uninstall)" ;;
  esac
}
