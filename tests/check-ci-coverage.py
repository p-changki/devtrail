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

        # ② 태그에서 도는가. if 가 없으면 항상 도니 통과.
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

    if bad:
        print('❌ CI 가 릴리스 경로를 지키지 못합니다')
        for b in bad:
            print('   - %s' % b)
        return 1

    print('✅ 릴리스 경로에 bash 3.2 검사가 붙어 있습니다')
    return 0


if __name__ == '__main__':
    sys.exit(main())
