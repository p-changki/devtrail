#!/usr/bin/env bash
# DevTrail — 변경 저널.
#
# 남의 볼트를 건드리는 도구는 되돌릴 수 있어야 한다.
#
# 지금까지 백업은 파일 옆에 <원본>.bak.<타임스탬프> 로 흩어져 있었다.
# 어느 백업이 어느 작업에 속하는지 알 방법이 없어서, 되돌리려면 사용자가
# 타임스탬프를 눈으로 맞춰봐야 했다.
#
# 저널은 '한 번의 실행'을 하나로 묶는다:
#
#   ~/.devtrail/journal/<작업ID>/
#   ├── meta.json          명령 · 시각 · 볼트
#   ├── entries.tsv        동작<TAB>대상<TAB>백업파일
#   └── files/             백업 실물
#
# ⚠️ 저널을 남기지 못하면 쓰기도 하지 않는다. 되돌릴 수 없는 변경을
#    조용히 진행하는 것보다 멈추는 게 낫다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

DT_JOURNAL_DIR="${DEVTRAIL_JOURNAL:-$DEVTRAIL_HOME/journal}"

# ── 작업 시작 ────────────────────────────────────────────────────────────────
# jr_begin <명령이름>  → 전역 DT_JOB 설정
jr_begin() {
  local cmd="$1"
  DT_JOB="$(date +%Y%m%d-%H%M%S)-$$"
  DT_JOB_DIR="$DT_JOURNAL_DIR/$DT_JOB"

  mkdir -p "$DT_JOB_DIR/files" || {
    die "$(L "저널을 만들 수 없습니다" "Cannot create the journal"): $DT_JOB_DIR
   $(L "되돌릴 수 없는 변경을 하지 않기 위해 중단합니다." \
       "Stopping rather than making a change we cannot undo.")"
  }

  jq -n --arg id "$DT_JOB" --arg cmd "$cmd" \
        --arg at "$(date '+%Y-%m-%d %H:%M:%S')" \
        --arg vault "$(vault_path 2>/dev/null || echo '')" \
        '{id: $id, command: $cmd, at: $at, vault: $vault}' \
    > "$DT_JOB_DIR/meta.json"

  : > "$DT_JOB_DIR/entries.tsv"
  export DT_JOB DT_JOB_DIR
}

# ── 기록 ─────────────────────────────────────────────────────────────────────
# 저널이 없으면 조용히 넘어간다 — jr_begin 을 안 부른 경로(테스트 등)에서도
# 기존 동작이 깨지지 않아야 한다.
_jr_active() { [ -n "${DT_JOB_DIR:-}" ] && [ -d "$DT_JOB_DIR" ]; }

# jr_backup <파일>  — 덮어쓰기 전에 부른다. 백업 경로를 stdout 으로 낸다.
jr_backup() {
  local target="$1"
  [ -f "$target" ] || return 0

  # 저널이 없으면 예전 방식(파일 옆 .bak)으로 남긴다.
  if ! _jr_active; then
    local legacy="$target.bak.$(date +%Y%m%d%H%M%S)"
    cp "$target" "$legacy" || return 1
    printf '%s' "$legacy"
    return 0
  fi

  local n; n=$(( $(wc -l < "$DT_JOB_DIR/entries.tsv" | tr -d ' ') + 1 ))
  local store="$DT_JOB_DIR/files/$(printf '%03d' "$n")-$(basename "$target")"
  cp "$target" "$store" || {
    warn "$(L "백업 실패 — 원본을 건드리지 않습니다" \
            "Backup failed — leaving the original alone"): $target"
    return 1
  }
  printf 'modify\t%s\t%s\n' "$target" "$store" >> "$DT_JOB_DIR/entries.tsv"
  printf '%s' "$store"
}

# jr_created <경로>  — 새로 만든 것. 되돌릴 때 지운다.
jr_created() {
  _jr_active || return 0
  printf 'create\t%s\t\n' "$1" >> "$DT_JOB_DIR/entries.tsv"
}

# jr_mkdir <경로>  — mkdir -p 하되, 새로 생긴 '모든 단계'를 기록한다.
#
# ⚠️ mkdir -p a/b/c 는 a 와 b 도 만든다. jr_created 로 c 만 남기면
#    되돌린 뒤 빈 껍데기가 남는다 — 실제로 그랬다.
# 이미 있던 폴더는 기록하지 않는다. 사용자 것이므로 지우면 안 된다.
jr_mkdir() {
  local target="$1" missing="" d="$1"
  [ -n "$target" ] || return 0

  # 없는 단계를 위에서부터 모으기 위해 아래에서 위로 훑는다.
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ ! -d "$d" ]; do
    missing="$d
$missing"
    d=$(dirname "$d")
  done

  mkdir -p "$target" || return 1

  local line
  printf '%s' "$missing" | while IFS= read -r line; do
    [ -n "$line" ] && jr_created "$line"
  done
  return 0
}

# ── 작업 종료 ────────────────────────────────────────────────────────────────
jr_end() {
  _jr_active || return 0
  local n; n=$(wc -l < "$DT_JOB_DIR/entries.tsv" | tr -d ' ')
  if [ "${n:-0}" -eq 0 ]; then
    # 아무것도 안 바꿨으면 저널을 남길 이유가 없다.
    rm -rf "$DT_JOB_DIR"
    return 0
  fi
  echo
  dim "   $(L "되돌리기" "Undo"): devtrail undo ${DT_JOB}   ($(L "변경 ${n}건" "${n} changes"))"
}

# ── 목록 ─────────────────────────────────────────────────────────────────────
jr_list() {
  step "$(L "변경 이력" "Change history")"
  [ -d "$DT_JOURNAL_DIR" ] || { dim "   $(L "기록이 없습니다" "Nothing recorded")"; return 0; }

  local found=0 d
  for d in $(ls -1r "$DT_JOURNAL_DIR" 2>/dev/null); do
    local job="$DT_JOURNAL_DIR/$d"
    [ -f "$job/meta.json" ] || continue
    found=1
    local n; n=$(wc -l < "$job/entries.tsv" 2>/dev/null | tr -d ' ')
    printf '  %-24s %-14s %s  %s\n' \
      "$d" \
      "$(jq -r '.command' "$job/meta.json")" \
      "$(jq -r '.at' "$job/meta.json")" \
      "$(L "변경 ${n:-0}건" "${n:-0} changes")"
  done
  [ "$found" = 0 ] && dim "   기록이 없습니다"
  echo
  dim "   $(L "자세히" "Details"): devtrail undo <ID> --dry-run"
  return 0
}

# 우리가 만든 폴더를 지운 뒤, 그 때문에 비게 된 부모도 정리한다.
#
# 왜 필요한가: mkdir -p "개발/개발일지" 는 '개발' 도 만든다. 그런데 저널에는
# '개발일지' 만 남는다(폴더 목록에 없는 중간 경로다). 그래서 되돌린 뒤에도
# 빈 껍데기가 남았다.
#
# ⚠️ rmdir 는 비어 있을 때만 성공한다. 사용자 노트가 하나라도 있으면 실패하고
#    거기서 멈춘다 — 이 함수는 데이터를 지울 수 없다.
# ⚠️ 볼트 경로 밖으로는 절대 올라가지 않는다.
_jr_prune_empty() {
  local vault="$1" d="$2"
  [ -n "$vault" ] || return 0
  d=$(dirname "$d")
  while [ "$d" != "$vault" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    case "$d" in "$vault"/*) ;; *) return 0 ;; esac
    rmdir "$d" 2>/dev/null || return 0
    d=$(dirname "$d")
  done
}

# ── 되돌리기 ─────────────────────────────────────────────────────────────────
jr_undo() {
  local id="" apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      -*) die "$(L "알 수 없는 옵션" "Unknown option"): $1" ;;
      *) id="$1" ;;
    esac
    shift
  done

  [ -n "$id" ] || { jr_list; return 0; }

  local job="$DT_JOURNAL_DIR/$id"
  [ -d "$job" ] || die "$(L "그런 작업이 없습니다" "No such job"): $id
   $(L "목록" "List"): devtrail undo"
  [ -f "$job/entries.tsv" ] || die "$(L "저널이 손상됐습니다" "The journal is damaged"): $job"

  step "$(L "되돌리기" "Undo") — $(jq -r '.command' "$job/meta.json") ($(jq -r '.at' "$job/meta.json"))"
  [ "$apply" = 1 ] || dim "   $(L "(dry-run — 실제로 되돌리려면 --apply)" "(dry run — pass --apply to really undo)")"
  echo

  local vault; vault=$(jq -r '.vault // ""' "$job/meta.json" 2>/dev/null)
  # '이미 없음'과 '못 했음'은 다르다. 섞어 세면 정상 동작이 실패처럼 보인다.
  local kind target store n=0 skipped=0 gone=0
  # 역순으로 되돌린다. 나중 변경이 앞 변경 위에 얹혀 있을 수 있다.
  while IFS=$'\t' read -r kind target store; do
    [ -n "$kind" ] || continue
    case "$kind" in
      modify)
        if [ ! -f "$store" ]; then
          warn "$(L "백업이 없습니다 — 건너뜀" "No backup — skipping"): $target"; skipped=$((skipped + 1)); continue
        fi
        ok "$(L "복원" "restore")  $target"
        [ "$apply" = 1 ] && cp "$store" "$target"
        n=$((n + 1)) ;;
      create)
        if [ ! -e "$target" ]; then
          gone=$((gone + 1)); continue
        fi
        # ⚠️ 디렉터리는 '비었을 때만' 지운다. 사용자가 그 안에 노트를 넣었을 수
        #    있고, 그건 우리 것이 아니다. 지우지 못했으면 반드시 말한다 —
        #    "삭제"라고 해놓고 남겨두면 사용자는 지워진 줄 안다.
        if [ "$apply" = 1 ] && [ -d "$target" ] && ! rmdir "$target" 2>/dev/null; then
          warn "$(L "비어 있지 않아 남겨둡니다" "Not empty — leaving it"): $target"
          skipped=$((skipped + 1)); continue
        fi
        ok "$(L "삭제" "remove ")  $target"
        [ "$apply" = 1 ] && [ -f "$target" ] && rm -f "$target"
        [ "$apply" = 1 ] && _jr_prune_empty "$vault" "$target"
        n=$((n + 1)) ;;
    esac
  done <<EOF
$(sed '1!G;h;$!d' "$job/entries.tsv")
EOF

  echo
  local tail=""
  [ "$gone" -gt 0 ] && tail=" · $(L "${gone}건은 이미 없음" "${gone} already gone")"
  [ "$skipped" -gt 0 ] && tail="${tail} · $(L "${skipped}건 남겨둠" "${skipped} left in place")"

  if [ "$apply" = 1 ]; then
    ok "$(L "${n}건 되돌림" "${n} undone")${tail}"
    dim "   $(L "저널은 남겨둡니다" "The journal is kept"): $job"
  else
    info "$(L "되돌릴 것 ${n}건" "${n} to undo")${tail}"
    dim "   $(L "적용" "Apply"): devtrail undo ${id} --apply"
  fi
}
