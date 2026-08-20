#!/usr/bin/env bash
# DevTrail — `devtrail update`
#
#   devtrail update           무엇이 바뀌는지 보여준다 (기본 dry-run)
#   devtrail update --apply   실제로 올린다
#   devtrail update --check   조용히 확인만 (종료코드 0=최신 1=업데이트 있음)
#
# 설치는 git clone 이다(install.sh). 그래서 갱신도 git 으로 한다.
#
# ⚠️ 작업 트리가 더러우면 올리지 않는다. 기여자의 로컬 수정을 날리는 것보다
#    멈추는 게 낫다.
# ⚠️ 코드를 올린 뒤에는 설정 스키마도 따라와야 한다 — mg_run 을 반드시 부른다.
# ⚠️ 한글 앞 변수는 중괄호로: "${n}개"  (bash 3.2)

update_cmd() {
  require_bins git jq

  local apply=0 check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      --check) check=1 ;;
      --dry-run) apply=0 ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *)  die "인자를 받지 않습니다: $1" ;;
    esac
    shift
  done

  [ -d "$DEVTRAIL_ROOT/.git" ] || {
    [ "$check" = 1 ] && return 0
    die "git 설치가 아닙니다: $DEVTRAIL_ROOT
   설치 스크립트로 다시 받으세요:
   curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash"
  }

  local br; br=$(git -C "$DEVTRAIL_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
  git -C "$DEVTRAIL_ROOT" fetch --quiet origin "$br" 2>/dev/null || {
    [ "$check" = 1 ] && return 0
    die "원격에서 가져오지 못했습니다 (네트워크 또는 원격 설정 확인)"
  }

  local local_sha remote_sha
  local_sha=$(git -C "$DEVTRAIL_ROOT" rev-parse HEAD)
  remote_sha=$(git -C "$DEVTRAIL_ROOT" rev-parse "origin/$br" 2>/dev/null)

  if [ "$local_sha" = "$remote_sha" ]; then
    [ "$check" = 1 ] && return 0
    ok "이미 최신입니다 — v$(cat "$DEVTRAIL_ROOT/VERSION" 2>/dev/null) ($br)"
    _up_schema "$apply"
    return 0
  fi

  # ⚠️ 다르다고 해서 뒤쳐진 것이 아니다.
  #    로컬이 앞서 있을 수도 있다(기여자의 미푸시 커밋). 그때 reset --hard 를
  #    하면 그 커밋이 사라진다. 조상 관계를 반드시 확인한다.
  if ! git -C "$DEVTRAIL_ROOT" merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
    [ "$check" = 1 ] && return 0
    local ahead
    ahead=$(git -C "$DEVTRAIL_ROOT" rev-list --count "origin/$br..HEAD" 2>/dev/null)
    warn "로컬이 원격보다 앞서 있습니다 — 커밋 ${ahead}개 (${br})"
    dim "   개발용 체크아웃으로 보입니다. 갱신하지 않습니다."
    dim "   원격 것으로 맞추려면 직접: git -C '$DEVTRAIL_ROOT' reset --hard origin/$br"
    # 코드를 안 올려도 설정 스키마는 뒤쳐질 수 있다. 여기서 빠뜨리면
    # 개발 체크아웃 사용자만 조용히 낡은 설정을 쓰게 된다.
    _up_schema "$apply"
    return 0
  fi

  [ "$check" = 1 ] && return 1

  _up_preview "$br" "$local_sha" "$remote_sha"
  [ "$apply" = 1 ] || {
    echo
    dim "   적용: devtrail update --apply"
    return 0
  }

  _up_apply "$br"
}

# 무엇이 바뀌는지 먼저 보여준다. 사용자가 모르는 채로 코드가 바뀌면 안 된다.
_up_preview() {
  local br="$1" from="$2" to="$3"
  local cur new n
  cur=$(cat "$DEVTRAIL_ROOT/VERSION" 2>/dev/null)
  new=$(git -C "$DEVTRAIL_ROOT" show "origin/$br:VERSION" 2>/dev/null | tr -d ' \n')
  n=$(git -C "$DEVTRAIL_ROOT" rev-list --count "$from..$to" 2>/dev/null)

  step "업데이트 있음 — v${cur} → v${new:-?}  (커밋 ${n}개 · $br)"
  echo
  git -C "$DEVTRAIL_ROOT" log --no-merges --format='   %s' "$from..$to" 2>/dev/null | head -12
  [ "${n:-0}" -gt 12 ] && dim "   … 그 밖에 $((n - 12))개"

  # 사용자 볼트에 손이 가는 변경인지 알린다. 이게 이 도구에서 가장 중요한 정보다.
  if [ "${new%%.*}" != "${cur%%.*}" ]; then
    echo
    warn "메이저 버전이 올라갑니다 — 기존 볼트에 수동 조치가 필요할 수 있습니다"
    dim "   CHANGELOG 를 먼저 읽으세요: $DEVTRAIL_ROOT/CHANGELOG.md"
  fi
}

_up_apply() {
  local br="$1"

  # 더러운 작업 트리는 건드리지 않는다.
  if [ -n "$(git -C "$DEVTRAIL_ROOT" status --porcelain 2>/dev/null)" ]; then
    die "로컬에 수정된 파일이 있습니다: $DEVTRAIL_ROOT
   커밋하거나 되돌린 뒤 다시 실행하세요 (git -C '$DEVTRAIL_ROOT' status)"
  fi

  echo
  step "갱신 중…"
  git -C "$DEVTRAIL_ROOT" reset --quiet --hard "origin/$br" || die "갱신 실패"
  chmod +x "$DEVTRAIL_ROOT/bin/devtrail" 2>/dev/null || true
  ok "코드 v$(cat "$DEVTRAIL_ROOT/VERSION" 2>/dev/null)"

  _up_schema 1
  _up_next
}

# 코드가 올라갔으면 설정 스키마도 맞춰야 한다.
_up_schema() {
  local apply="$1"
  config_exists || return 0
  . "$DEVTRAIL_ROOT/lib/migrate.sh"
  mg_status && return 0
  echo
  mg_run $([ "$apply" = 1 ] && echo --apply)
}

_up_next() {
  echo
  dim "   설정과 노트는 그대로입니다. 새 폴더·템플릿을 받으려면:"
  dim "     devtrail augment            없는 것만 생성 (dry-run)"
  dim "     devtrail obsidian           플러그인 설정 재병합"
  dim "     devtrail skills sync        AI 스킬 갱신"
}
