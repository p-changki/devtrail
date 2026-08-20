#!/usr/bin/env python3
"""macOS 기본 bash 3.2 의 한글 흡수 함정.

    "$n개"     ✗ 3.2 가 '개'의 첫 바이트를 변수명에 흡수 → unbound variable
    "${n}개"   ✓

세 번 사고가 났고, 세 번 다 '문제를 찾았을 때만' 죽었다(요약 분기, 에러 분기).
그래서 평소 테스트로는 안 잡혔다.

⚠️ 이 검사는 원래 셸의 grep 으로 했는데, `[가-힣]` 는 collation 범위라
   C 로케일의 GNU grep 이 "Invalid collation character" 로 거부한다.
   CI(LC_ALL=C.UTF-8)에서 실제로 그랬다. 파이썬 re 는 로케일과 무관하다.

⚠️ 검사 대상에서 이 파일과 규약 문서를 뺀다 — 나쁜 예시를 드는 것은 정상이다.
"""
import glob
import io
import re
import sys

# $var 바로 뒤에 한글이 붙는 경우
BAD = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[가-힣]')

# 나쁜 예시를 일부러 적어두는 파일
SELF = ("tests/check-bash32.py", "tests/lib/harness.sh", "tests/run.sh")


def main():
    # 정규식이 실제로 동작하는지 먼저 확인한다.
    # 못 맞추는 환경에서 '통과'로 보이면 검사 없음보다 나쁘다.
    if not BAD.search('echo "$n개"'):
        print("  ❌ 한글 정규식이 동작하지 않습니다")
        return 1

    files = sorted(glob.glob("lib/**/*.sh", recursive=True))
    files += sorted(glob.glob("tests/**/*.sh", recursive=True))
    files += ["bin/devtrail", "install.sh"]

    hits = []
    for f in files:
        if f in SELF:
            continue
        try:
            lines = io.open(f, encoding="utf-8").read().split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            if line.lstrip().startswith("#"):
                continue
            if BAD.search(line):
                hits.append(f"  {f}:{i}: {line.strip()[:70]}")

    if hits:
        print("\n".join(hits))
        print('  → 한글 앞 변수는 중괄호로: "${n}개"')
        return 1
    print("  bash 3.2 한글 흡수 없음")
    return 0


if __name__ == "__main__":
    sys.exit(main())
