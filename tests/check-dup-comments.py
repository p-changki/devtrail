#!/usr/bin/env python3
"""연속된 주석 블록이 그대로 반복되는지 검사한다.

리팩터로 함수를 옮길 때 설명 블록만 남고 복사되는 일이 실제로 두 번 있었다.
동작에는 영향이 없지만, 읽는 사람이 "왜 두 번 적혀 있지"에서 멈춘다.
"""
import glob
import io
import sys


def main():
    bad = []
    files = sorted(glob.glob("lib/**/*.sh", recursive=True))
    files += ["bin/devtrail", "install.sh"]
    for f in files:
        try:
            lines = io.open(f, encoding="utf-8").read().split("\n")
        except OSError:
            continue
        for i in range(len(lines) - 6):
            a = lines[i:i + 3]
            if not all(l.strip().startswith("#") and len(l.strip()) > 5 for l in a):
                continue
            for gap in (0, 1):
                if a == lines[i + 3 + gap:i + 6 + gap]:
                    bad.append(f"  ❌ {f}:{i + 1}: 주석 블록이 그대로 반복됩니다")
    if bad:
        print("\n".join(sorted(set(bad))))
        return 1
    print("  주석 중복 없음")
    return 0


if __name__ == "__main__":
    sys.exit(main())
