#!/usr/bin/env python3
"""릴리스 경로에서 bash 3.2 검사가 빠지지 않았는지 본다.

⚠️ 왜 이 파일이 생겼나 (2026-08-23)

macOS 러너가 무료 한도의 거의 전부를 쓴다(실행 1회 38분 중 38분). 그래서
`behav` 를 branch push 에서 건너뛰게 했다. 절약은 실측 절반이다.

그런데 이 절약에는 조용히 무너질 수 있는 전제가 있다:

  1. 태그(릴리스)에서는 `behav` 가 **반드시** 돌아야 한다. 안 돌면
     시험되지 않은 코드로 앱을 빌드해 배포하게 된다.
  2. `app` 은 `behav` 에 기대야 한다. 기대지 않으면 behav 가 실패해도
     빌드가 나간다.
  3. `behav` 는 macOS 여야 한다. ubuntu 로 옮기면 bash 5.x 가 되고,
     이 저장소가 세 번 사고를 낸 3.2 함정을 통과시킨다.

세 전제 중 하나만 어긋나도 CI 는 **녹색인 채로** 아무것도 지키지 않는다.
비용을 아끼는 설정이 안전을 대신 깎지 않도록 여기서 못 박는다.

⚠️ 정책 (2026-08-23): **로컬 우선**

이 워크플로는 일상 PR 에서 자동으로 돌지 않는다. 트리거는 태그와 수동
실행뿐이다. DevTrail 의 정식 게이트는 로컬이고, GitHub Actions 는 릴리스
검증만 맡는다 — 이 계정의 다른 프로덕션 저장소 예산을 지키기 위해서다.

그래서 여기서 하나를 더 못 박는다: **pull_request 나 branch push 트리거가
되살아나면 실패한다.** 편의로 한 줄 되돌리기가 너무 쉽고, 되돌아간 것을
아무도 눈치채지 못한 채 예산이 나간다.

⚠️ CI ↔ run.sh ↔ 로컬 게이트의 **대응을 여기서 단언한다** (2026-08-23 추가)

문서에 손으로 적은 대응표는 곧 거짓말이 된다. 이 저장소는 dirs.devlog
기본값을 네 곳에, devlog 파일명을 여섯 곳에, 플러그인 파일 목록을 두 곳에
두고 같은 병을 앓았다. 게이트가 소비하지 않는 문서는 아무도 지키지 않는다.

그래서 대응표를 문서가 아니라 **여기서** 관리한다:

  tests/run.sh              검사의 정본. 그룹 어휘를 여기서 읽는다.
  .github/workflows/ci.yml  그 그룹들을 부른다.
  scripts/verify-local.sh   같은 정본을 부른다 (목록을 다시 적지 않는다).

셋 중 하나가 정본에서 떨어져 나가면 여기서 빨간불이 난다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CI = ROOT / '.github/workflows/ci.yml'
RUNSH = ROOT / 'tests/run.sh'
LOCAL = ROOT / 'scripts/verify-local.sh'
HOOK = ROOT / 'scripts/hooks/pre-push'


def job_block(src, name):
    """`  <name>:` 부터 다음 같은 들여쓰기의 잡까지."""
    m = re.search(r'^  %s:$' % re.escape(name), src, re.M)
    if not m:
        return None
    rest = src[m.end():]
    nxt = re.search(r'^  [a-z_]+:$', rest, re.M)
    return rest[:nxt.start()] if nxt else rest


def check_triggers(src, bad):
    """트리거가 태그·수동뿐인가 — 일상 자동 실행이 되살아나지 않았는가."""
    head = src[:src.index('jobs:')] if 'jobs:' in src else src
    # 주석을 걷어낸다. 주석에 적힌 pull_request 는 되살아난 게 아니다.
    live = re.sub(r'#[^\n]*', '', head)

    if re.search(r'^\s*pull_request:', live, re.M):
        bad.append('pull_request 트리거가 되살아났습니다 — 일상 PR 이 다시 '
                   'macOS 러너를 씁니다 (실행 1회 38분)')

    m = re.search(r'^\s*push:\s*\n((?:\s+\S.*\n)*)', live, re.M)
    if m:
        block = m.group(1)
        if re.search(r'^\s*branches:', block, re.M):
            bad.append('push 에 branches 가 되살아났습니다 — main/dev 푸시마다 '
                       'CI 가 돕니다. 태그만 남기세요')
        if not re.search(r'^\s*tags:', block, re.M):
            bad.append('push 에 tags 가 없습니다 — 릴리스 검증 경로가 사라집니다')

    if not re.search(r'^\s*workflow_dispatch:', live, re.M):
        bad.append('workflow_dispatch 가 없습니다 — 필요할 때 손으로 돌릴 '
                   '길이 없어집니다')

def run_groups(src):
    """run.sh 가 실제로 쓰는 그룹 이름. `run <group> "..."` 에서 읽는다."""
    return sorted(set(re.findall(r'^run\s+([a-z]+)\s', src, re.M)))


def run_vocab(src):
    """run.sh 가 인자로 받아들이는 모드. case 문에서 읽는다."""
    m = re.search(r'^case "\$GROUP" in\s*\n\s*([a-z|]+)\)', src, re.M)
    return sorted(m.group(1).split('|')) if m else []


# ⚠️ 문구가 정책과 어긋나면 사람이 잘못된 기대를 갖는다. "CI 가 최종
#    게이트" 라고 읽은 사람은 로컬을 건너뛰고, 그러면 아무도 안 본 코드가
#    머지된다. 정책이 바뀌었으니 옛 문구가 되살아나면 실패한다.
STALE_WORDING = [
    '최종 게이트',
    '최종 재검증',
    '최종 안전망',
    '독립적인 최종',
    'CI 가 독립적으로',
]
WORDING_FILES = [
    'README.md',
    'scripts/verify-local.sh',
    'scripts/hooks/pre-push',
    '.github/workflows/ci.yml',
]


def check_wording(bad):
    """정책이 바뀌기 전의 문구가 남아 있지 않은가."""
    for rel in WORDING_FILES:
        f = ROOT / rel
        if not f.exists():
            continue
        text = f.read_text(encoding='utf-8')
        for w in STALE_WORDING:
            if w in text:
                bad.append("%s 에 옛 정책 문구가 남아 있습니다: '%s' — "
                           "GitHub Actions 는 더 이상 일상 PR 의 게이트가 "
                           "아닙니다" % (rel, w))


def check_correspondence(bad):
    """CI · run.sh · 로컬 게이트가 같은 정본을 보는가."""
    if not RUNSH.exists():
        bad.append('tests/run.sh 이 없습니다 — 검사의 정본이 사라졌습니다')
        return

    rsrc = RUNSH.read_text(encoding='utf-8')
    ci = CI.read_text(encoding='utf-8') if CI.exists() else ''
    groups = run_groups(rsrc)
    vocab = run_vocab(rsrc)

    # ① run.sh 안에서 쓰는 그룹이 전부 인자 어휘에 있는가.
    #    (`run swift ...` 는 어휘가 아니라 _want 가 거르므로 예외로 둔다)
    for g in groups:
        if g not in vocab and g not in ('behav', 'swift'):
            bad.append("run.sh 이 그룹 '%s' 를 쓰는데 인자 어휘에 없습니다: %s"
                       % (g, vocab))

    # ② CI 가 그 정본을 부르는가. 잡마다 run.sh 를 호출해야 한다.
    called = set(re.findall(r'tests/run\.sh\s+([a-z]+)', ci))
    if not called:
        bad.append('CI 가 tests/run.sh 를 부르지 않습니다 — 정본이 둘로 갈렸습니다')
    else:
        for g in ('lint', 'guard'):
            if g not in called:
                bad.append("CI 가 run.sh %s 를 부르지 않습니다: 호출 %s"
                           % (g, sorted(called)))
        if not called & {'fast', 'all'}:
            bad.append('CI 가 동작 테스트(fast/all)를 부르지 않습니다: 호출 %s'
                       % sorted(called))

    # ③ 로컬 게이트도 **같은 정본**을 부르는가. 목록을 다시 적으면 안 된다.
    if not LOCAL.exists():
        bad.append('scripts/verify-local.sh 이 없습니다 — 로컬 1차 게이트가 없습니다')
    else:
        lsrc = LOCAL.read_text(encoding='utf-8')
        # ⚠️ 이름이 적혀 있다 ≠ 부른다. 주석에도 적힌다. **호출 자리**를 본다:
        #    주석이 아닌 줄에서 /bin/bash 로 run.sh 에 인자를 넘겨 부르는가.
        #    (2026-08-23: 처음엔 문자열 포함만 봐서 변이가 살아남았다)
        if not re.search(r'^[^#\n]*/bin/bash\s+\.?/?tests/run\.sh\s+\S',
                         lsrc, re.M):
            bad.append('verify-local.sh 이 /bin/bash 로 tests/run.sh 를 부르지 '
                       '않습니다 — 검사 목록을 따로 갖거나, PATH 의 bash 5.x 가 '
                       '잡혀 3.2 함정을 통과시킵니다')
        for flag in ('--release',):
            if flag not in lsrc:
                bad.append('verify-local.sh 에 %s 가 없습니다' % flag)

    # ④ hook 은 **빠른 계층만** 돌아야 한다. 전체를 돌리면 사람이
    #    --no-verify 를 습관화하고, 게이트가 있다는 착각만 남는다.
    if HOOK.exists():
        hsrc = HOOK.read_text(encoding='utf-8')
        if re.search(r'run\.sh\s+(fast|all)\b', hsrc):
            bad.append('pre-push 가 전체 스위트를 돌립니다(약 2분 35초) — '
                       '사람이 --no-verify 를 습관화합니다. lint/guard 만 두세요')
        # ⚠️ 이름이 나온다고 부르는 게 아니다. 안내 문구에도 나온다.
        #    **명령 자리**에 있는지만 본다.
        if re.search(r'^\s*(?:\S*bash\s+)?["\']?\.?/?scripts/verify-local\\.sh',
                     hsrc, re.M):
            bad.append('pre-push 가 verify-local.sh 를 통째로 부릅니다 — 위와 같은 이유')
        if 'diff --check' not in hsrc:
            bad.append('pre-push 가 공백 검사를 하지 않습니다')
        # ⚠️ 작업 트리가 아니라 **push 될 범위**를 봐야 한다. 이미 커밋한
        #    변경은 작업 트리에 없어 `git diff --check` 만으로는 안 잡힌다.
        if 'remotesha' not in hsrc:
            bad.append('pre-push 가 push 될 커밋 범위를 보지 않습니다 — '
                       '이미 커밋된 공백 오류를 놓칩니다')


def main():
    if not CI.exists():
        print('❌ .github/workflows/ci.yml 이 없습니다')
        return 1

    src = CI.read_text(encoding='utf-8')
    bad = []

    behav = job_block(src, 'behav')
    app = job_block(src, 'app')
    if behav is None:
        bad.append('behav 잡이 없습니다 — bash 3.2 검사가 사라졌습니다')
    if app is None:
        bad.append('app 잡이 없습니다')

    if behav is not None:
        # ① macOS 여야 한다
        if not re.search(r'runs-on:\s*macos', behav):
            bad.append('behav 가 macOS 러너가 아닙니다 — bash 3.2 함정을 재현하지 못합니다')

        # ② 태그에서 도는가.
        #    ⚠️ 워크플로가 태그·수동에서만 뜨므로 if 가 **없는 것이 정상**이다.
        #       if 를 달았다면 태그를 포함해야 한다 — 아니면 릴리스가 bash 3.2
        #       검사 없이 빌드된다.
        cond = re.search(r'^    if:(.*?)(?=^    [a-z-]+:)', behav, re.M | re.S)
        if cond:
            text = ' '.join(cond.group(1).split())
            if "refs/tags/v" not in text:
                bad.append(
                    'behav 의 if 가 태그를 포함하지 않습니다 — 릴리스가 '
                    'bash 3.2 검사 없이 빌드됩니다: %s' % text)

        # ③ 실제로 스위트를 부르는가
        if 'tests/run.sh' not in behav:
            bad.append('behav 가 tests/run.sh 를 부르지 않습니다')

    if app is not None:
        needs = re.search(r'needs:\s*\[([^\]]*)\]', app)
        if not needs:
            bad.append('app 에 needs 가 없습니다 — 검사 실패해도 빌드가 나갑니다')
        elif 'behav' not in needs.group(1):
            bad.append('app 이 behav 에 기대지 않습니다: [%s]' % needs.group(1))

    check_triggers(src, bad)
    check_wording(bad)

    check_correspondence(bad)

    if bad:
        print('❌ CI 가 릴리스 경로를 지키지 못합니다')
        for b in bad:
            print('   - %s' % b)
        return 1

    print('✅ 트리거는 태그·수동뿐 · 릴리스 경로 · CI↔run.sh↔로컬 대응 확인')
    return 0


if __name__ == '__main__':
    sys.exit(main())
