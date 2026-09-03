#!/usr/bin/env bash
# DevTrail — 프로젝트 키 목록의 단일 출처.
#
# ⚠️ 목록을 여기 한 곳에만 둔다. 화면·템플릿·검증이 각자 갖고 있으면 언젠가
#    한쪽만 늘어나고, 사용자는 "적었는데 안 잡힌다" 를 만난다. 실제로 그랬다 —
#    경로 맵은 설정만 읽고 플러그인 화면은 폴더를 읽어, 같은 볼트에서 선택창
#    1개 · 화면 7개가 나왔다.
#
# ⚠️ 설정(.github.project_groups)은 GitHub 레포 그룹핑이지 프로젝트 목록이
#    아니다. GitHub 을 연결하지 않은 프로젝트도 고를 수 있어야 한다.
#
# 부르는 쪽이 cfg · vault_root · dt_dir · CONFIG_FILE 을 준비한 뒤 불러온다.

# 태그와 폴더 이름이 되므로 파일명에 못 쓰는 문자가 있으면 프로젝트가 아니다.
DT_PROJECT_KEY_FILTER='select(test("[*?\\[\\]/\\\\:<>|\"]") | not)
                       | select(length > 0 and length <= 64)'

# 볼트의 프로젝트 폴더 이름 (JSON 배열)
dt_project_folder_keys() {
  local dir k
  dir="$(vault_root)/$(dt_dir projects)" || { echo '[]'; return 0; }
  [ -d "$dir" ] || { echo '[]'; return 0; }
  {
    for k in "$dir"/*/; do
      k=${k%/}; k=${k##*/}
      # 글로브가 안 맞으면 리터럴 * 가 온다. 숨김 폴더는 프로젝트가 아니다.
      case "$k" in '*'|.*) continue ;; esac
      printf '%s\n' "$k"
    done
  } | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# 설정 ∪ 폴더 (JSON 배열, 정렬·중복 제거)
dt_project_keys() {
  jq -c --argjson folders "$(dt_project_folder_keys)" \
    "[ (((.github.project_groups // {}) | keys) + \$folders)[] | $DT_PROJECT_KEY_FILTER ] | unique" \
    "$CONFIG_FILE" 2>/dev/null || echo '[]'
}

# ⚠️ dt_project_keys 와 키 집합이 같아야 한다 — 한쪽에만 있으면 소비자가 못
#    잇는다. 폴더는 항등 매핑을 주되 설정에 있으면 설정 값이 이긴다. 폴더가
#    그룹핑을 덮으면 acme-fe → acme 매핑이 깨진다.
dt_project_sections() {
  jq -c --argjson folders "$(dt_project_folder_keys)" \
    "(([ \$folders[] | { key: ., value: . } ] | from_entries)
      + (.github.project_groups // {}))
     | with_entries(select(.key | $DT_PROJECT_KEY_FILTER))" \
    "$CONFIG_FILE" 2>/dev/null || echo '{}'
}

# 이 키가 고를 수 있는 프로젝트인가
dt_project_known() {
  [ -n "${1:-}" ] || return 1
  dt_project_keys | jq -e --arg k "$1" 'index($k) != null' >/dev/null 2>&1
}

# 줄바꿈으로 구분된 원문 키 목록을 검증해 유니크 JSON 배열로 돌려준다.
# ⚠️ 모르는 키를 그대로 쓰면 태그와 폴더가 어긋난 노트가 남는다. 무언가를
#    만들기 **전에** 거절한다 — 만든 뒤 고치라고 하면 아무도 안 고친다.
dt_project_validate() {
  local raw="$1" k
  [ -n "$raw" ] || { printf '[]'; return 0; }
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    dt_project_known "$k" || die "$(L "모르는 프로젝트" "Unknown project"): $k
   $(L "쓸 수 있는 값" "Available"): $(dt_project_keys | jq -r 'join(", ")')"
  done <<DTPJEOF
$raw
DTPJEOF
  printf '%s' "$raw" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
}
