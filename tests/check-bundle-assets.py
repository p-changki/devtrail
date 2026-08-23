#!/usr/bin/env python3
"""번들에 실린 CLI 자산이 **코드가 실제로 찾는 것**과 맞는가 (ADR 0006 M4-3).

⚠️ 왜 손으로 적은 목록을 믿지 않나

`app/build.sh` 는 `bin lib plugin preset templates skills VERSION
CHANGELOG.md` 를 복사한다. 그런데 나중에 누군가 `$DEVTRAIL_ROOT/foo` 를
새로 참조하면, 저장소에서는 멀쩡히 돌고 **번들에서만** 죽는다 — 그리고
만든 사람 기계에서는 재현되지 않는다.

이 저장소는 같은 종류(정본이 두 벌)를 `dirs.devlog` 로 네 번 겪었다.
그래서 목록의 정본을 **코드**로 둔다: 소스에서 `$DEVTRAIL_ROOT/<무엇>` 을
훑어, 번들에 없는 것이 있으면 세운다.

⚠️ 빼는 것에는 **이유를 적는다.** 이유 없는 예외는 다음 사람에게 그냥
   구멍으로 보인다.
"""
import io
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app" / "build" / "DevTrail.app"
RES = APP / "Contents" / "Resources"

# 번들에 실려 나가는 코드. 여기 있는 파일이 참조하는 것은 번들에도 있어야 한다.
SCAN_DIRS = ["bin", "lib"]

# ⚠️ 넣지 **않는** 것과 그 이유. 이유가 사라지면 예외도 사라져야 한다.
EXEMPT = {
    "app": "`devtrail app` 은 개발자 명령이고(앱 자신을 빌드한다), "
           "dt_helper 는 번들 Contents/Helpers 를 2순위로 먼저 본다",
    ".git": "설치본이 아니라 저장소의 것이다. updatecmd.sh 가 없을 때를 "
            "이미 가드한다 — 앱 업데이트는 M8",
    "..": "번들 바깥(Contents/Helpers)을 가리키는 상대 경로다",
}

REF = re.compile(r"\$\{?DEVTRAIL_ROOT\}?/([A-Za-z0-9_.-]+)")


def strip_comments(text):
    """⚠️ 주석 안의 경로는 참조가 아니다. '적혀 있다 ≠ 쓴다'."""
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def main():
    bad = []

    if not APP.is_dir():
        print("⚠️ app/build/DevTrail.app 없음 — 건너뜁니다 (./app/build.sh)")
        return 0

    # ── ① 코드가 찾는 것이 번들에 있는가 ────────────────────────────────────
    refs = {}
    for d in SCAN_DIRS:
        for p in sorted((ROOT / d).rglob("*")):
            if not p.is_file():
                continue
            try:
                text = strip_comments(p.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError):
                continue
            for m in REF.finditer(text):
                refs.setdefault(m.group(1), set()).add(
                    str(p.relative_to(ROOT)))

    if not refs:
        # ⚠️ 아무것도 못 찾았으면 이 게이트는 아무것도 지키지 않는다.
        bad.append("$DEVTRAIL_ROOT 참조를 하나도 찾지 못했습니다 — 정규식이 낡았습니까?")

    for name in sorted(refs):
        if name in EXEMPT:
            continue
        if not (RES / name).exists():
            bad.append("번들에 없습니다: Resources/%s  (참조: %s)"
                       % (name, ", ".join(sorted(refs[name])[:3])))

    # ── ② 예외가 아직 쓰이는가 ──────────────────────────────────────────────
    #
    # ⚠️ 아무도 참조하지 않는 예외는 낡은 것이다. 남겨두면 다음 사람이
    #    "왜 뺐지" 를 영원히 못 푼다.
    for name in sorted(EXEMPT):
        if name not in refs:
            bad.append("예외가 더 이상 쓰이지 않습니다: %s — EXEMPT 에서 지우세요" % name)

    # ── ③ 실린 CLI 가 실제로 도는가 ─────────────────────────────────────────
    #
    # ⚠️ 파일이 다 있다는 것과 도는 것은 다르다.
    cli = RES / "bin" / "devtrail"
    if not os.access(cli, os.X_OK):
        bad.append("번들 CLI 에 실행 권한이 없습니다: %s" % cli)

    if bad:
        print("❌ 번들 CLI 자산이 코드와 어긋납니다")
        for b in bad:
            print("   - %s" % b)
        return 1

    print("✅ 번들 CLI 자산 일치 — 참조 %d종 · 예외 %d종 (이유 기록됨)"
          % (len(refs) - len(EXEMPT), len(EXEMPT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
