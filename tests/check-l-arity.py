#!/usr/bin/env python3
"""L 은 반드시 두 인자를 받는다: L "한국어" "English"

하나만 주면 영어 사용자에게 한국어가 그대로 나간다.
에러가 나지 않으므로 실행해봐도 눈치채기 어렵다 — 그래서 검사한다.

⚠️ 호출만 본다. `[ -L "$x" ]` 같은 테스트 연산자를 잡으면 안 되므로
   `$(` 로 시작하는 형태만 확인한다.

⚠️ 인자 안에 $( ) 를 중첩하면 이 검사가 오탐한다. 따옴표 균형을 세지
   않기 때문이다. 오탐을 없애려고 검사를 복잡하게 만드는 대신, 중첩을
   쓰지 않는 쪽을 택했다 — 값을 변수로 빼면 읽기도 낫고 jq 도 한 번만
   부른다.
"""
import glob
import io
import re
import sys

CALL = re.compile(r'\$\(\s*L\s+"(?:[^"\\]|\\.)*"')

def main():
    bad = []
    files = sorted(glob.glob("lib/**/*.sh", recursive=True))
    files += ["bin/devtrail", "install.sh"]
    for f in files:
        try:
            lines = io.open(f, encoding="utf-8").read().split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            if line.lstrip().startswith("#"):
                continue
            for m in CALL.finditer(line):
                rest = line[m.end():]
                if re.match(r'\s*"', rest):      # 두 번째 인자가 같은 줄에
                    continue
                if rest.rstrip().endswith("\\"):  # 다음 줄로 이어짐
                    continue
                bad.append(f"  ❌ {f}:{i}: {line.strip()[:70]}")
    if bad:
        print("\n".join(bad))
        print('  → L 은 두 인자를 받습니다: L "한국어" "English"')
        return 1
    print("  L 호출 전부 두 인자")
    return 0


if __name__ == "__main__":
    sys.exit(main())
