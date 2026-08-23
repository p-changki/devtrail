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
"""
import re
import sys
from pathlib import Path

CI = Path(__file__).resolve().parent.parent / '.github/workflows/ci.yml'


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

    if bad:
        print('❌ CI 가 릴리스 경로를 지키지 못합니다')
        for b in bad:
            print('   - %s' % b)
        return 1

    print('✅ 트리거는 태그·수동뿐 · 릴리스 경로에 bash 3.2 검사가 붙어 있음')
    return 0


if __name__ == '__main__':
    sys.exit(main())
