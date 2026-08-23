#!/usr/bin/env bash
# .app 번들이 **배포할 수 있는 모양**인가 (ADR 0006 M4).
#
# ⚠️ 왜 필요한가
#
#    최소 macOS 가 14 인데(D1), **macOS 14 는 Intel 맥도 지원한다.**
#    Apple Silicon 에서 빌드하면 기본이 arm64 하나라, 그대로 DMG 를 만들면
#    Intel 맥에서 **아예 열리지 않는다** — "설치는 됐는데 안 열린다" 는
#    종류이고, 만든 사람 기계에서는 영원히 재현되지 않는다.
#
#    그리고 헬퍼가 번들 안에 없으면 `dt_helper` 가 조용히 python3 폴백으로
#    떨어진다. python3 가 없는 기계에서는 그때 아무 말 없이 실패한다.
#
# ⚠️ 소스를 읽는 것으로는 부족하다. **빌드 산출물을 본다.** 플래그를 줬다고
#    universal 이 되는 게 아니다 — 툴체인이 조용히 호스트만 만들 수 있다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"

APP="$ROOT/app/build/DevTrail.app"

t_start "빌드 스크립트가 universal 을 요구한다"
BS=$(cat "$ROOT/app/build.sh")
# ⚠️ 주석이 아니라 **실행되는 줄**을 본다.
LIVE=$(printf '%s' "$BS" | grep -vE '^\s*#')
t_eq "두 아키텍처를 함께 준다" "1" \
  "$(printf '%s' "$LIVE" | grep -cE 'arch arm64 --arch x86_64' | tr -d ' ')"
t_eq "결과를 lipo 로 확인한다" "1" \
  "$(printf '%s' "$LIVE" | grep -c 'lipo -archs' | tr -d ' ')"
# ⚠️ 횟수를 못 박지 않는다. 복사·서명·실행 확인 세 곳에서 쓰이고, 앞으로
#    더 늘 수 있다. 지켜야 할 것은 "쓰인다" 이지 "몇 번" 이 아니다.
t_eq "헬퍼를 번들에 넣는다" "no" \
  "$([ "$(printf '%s' "$LIVE" | grep -c 'Contents/Helpers/devtrail-helper' | tr -d ' ')" = 0 ] \
     && echo yes || echo no)"

t_start "빌드 스크립트가 jq 를 번들에 넣는다"
# ⚠️ **명령 자리**를 본다. 문자열이 어딘가 있다는 것으로는 부족하다 —
#    cp 를 지워도 바로 밑 chmod 줄에 같은 경로가 남아 grep 은 찾아낸다.
#    (2026-08-24 변이에서 실제로 이렇게 뚫렸다.)
t_eq "vendor 의 jq 를 Helpers 로 복사한다" "1" \
  "$(printf '%s\n' "$LIVE" \
     | grep -cE '^[[:space:]]*cp[[:space:]]+.*vendor/jq/build/jq.*Contents/Helpers/jq' \
     | tr -d ' ')"
t_eq "라이선스 원본을 복사한다" "1" \
  "$(printf '%s\n' "$LIVE" \
     | grep -cE '^[[:space:]]*cp[[:space:]]+.*vendor/jq/build/COPYING' | tr -d ' ')"

t_start "⚠️ 어긋난 jq 로는 빌드가 서지 않는다"
# ⚠️ 이건 문자열이 아니라 **행동**으로 확인한다. 관문이 진짜 막는지는
#    막아 보는 수밖에 없다.
#
#    실린 jq 를 나중에 상류 해시로 되짚을 수는 없다 — 서명이 바이트를 바꾸고,
#    서명을 지워도 원본으로 돌아오지 않는다(실측). 그래서 이 관문이
#    무결성의 **마지막 기회**다.
#
#    관문은 swift 빌드보다 앞에 있어야 이 시험이 몇 초 만에 끝난다.
if [ -f "$ROOT/vendor/jq/build/jq" ]; then
  BSAV=$(mktemp -d)
  cp "$ROOT/vendor/jq/build/jq" "$BSAV/jq"
  BSTAMP=""
  [ -f "$APP/Contents/Helpers/jq" ] && BSTAMP=$(shasum -a 256 "$APP/Contents/Helpers/jq" | cut -d' ' -f1)

  # 상류와 다른 바이너리로 바꿔치기한다 (같은 이름, 도는 것, 다른 내용)
  cp "$APP/Contents/Helpers/jq" "$ROOT/vendor/jq/build/jq" 2>/dev/null

  t_eq "락과 다른 jq 면 build.sh 가 실패한다" "no" \
    "$( (cd "$ROOT" && ./app/build.sh >/dev/null 2>&1) && echo yes || echo no)"

  # ⚠️ 그리고 **기존 번들을 건드리지 않아야** 한다. 관문에서 막혔는데
  #    번들이 반쯤 지워져 있으면, 다음 사람이 그걸 배포한다.
  if [ -n "$BSTAMP" ]; then
    t_eq "막혔을 때 기존 번들이 그대로다" "$BSTAMP" \
      "$(shasum -a 256 "$APP/Contents/Helpers/jq" 2>/dev/null | cut -d' ' -f1)"
  fi

  cp "$BSAV/jq" "$ROOT/vendor/jq/build/jq"
  rm -rf "$BSAV"
else
  dim "   vendor/jq/build/jq 없음 — 건너뜀 (./scripts/fetch-jq.sh)"
fi

t_start "최소 macOS 의 정본이 하나다"
# ⚠️ Info.plist 에 숫자를 직접 적으면 Package.swift 와 두 벌이 된다.
#    한쪽만 올리는 날 "설치는 됐는데 안 열린다" 가 된다.
t_eq "build.sh 가 숫자를 직접 적지 않는다" "0" \
  "$(printf '%s' "$LIVE" | grep -c 'LSMinimumSystemVersion</key><string>[0-9]' | tr -d ' ')"
t_eq "Package.swift 에서 읽는다" "yes" \
  "$([ "$(printf '%s' "$LIVE" | grep -c 'MIN_MACOS=\$(grep' | tr -d ' ')" != 0 ] \
     && echo yes || echo no)"

t_start "번들 jq 의 출처가 못 박혀 있다"
LOCK="$ROOT/vendor/jq/jq.lock.json"
t_eq "락 파일이 있다" "yes" "$([ -f "$LOCK" ] && echo yes || echo no)"
if [ -f "$LOCK" ]; then
  # ⚠️ 슬라이스가 둘 다 있어야 universal 을 만들 수 있다.
  t_eq "락에 두 아키텍처가 있다" "arm64 x86_64" \
    "$(jq -r '[.slices[].arch] | sort | join(" ")' "$LOCK" 2>/dev/null)"
  t_eq "각 슬라이스에 sha256 이 있다" "0" \
    "$(jq '[.slices[] | select((.sha256 // "") | test("^[0-9a-f]{64}$") | not)] | length' "$LOCK" 2>/dev/null)"
  t_eq "라이선스 해시가 있다" "yes" \
    "$(jq -r 'if (.license.sha256 // "") | test("^[0-9a-f]{64}$") then "yes" else "no" end' "$LOCK" 2>/dev/null)"
  # ⚠️ jq 가 요구하는 macOS 가 앱 최소보다 높으면, 앱은 뜨는데 jq 만 못 돈다.
  JQMIN=$(jq -r '.min_macos' "$LOCK" 2>/dev/null | cut -d. -f1)
  APPMIN=$(grep -oE 'macOS\(\.v([0-9]+)\)' "$ROOT/app/Package.swift" | grep -oE '[0-9]+' | head -1)
  t_eq "jq 의 최소 macOS 가 앱 최소 이하다 (jq $JQMIN · 앱 $APPMIN)" "yes" \
    "$([ -n "$JQMIN" ] && [ -n "$APPMIN" ] && [ "$JQMIN" -le "$APPMIN" ] && echo yes || echo no)"
fi

t_start "vendor 산출물이 상류 해시와 맞는다"
# ⚠️ 우리가 만든 해시를 우리가 확인하는 순환을 만들지 않는다. 합친
#    universal 을 다시 쪼개 **상류가 발표한** 슬라이스 해시와 대조한다.
#    (서명하면 슬라이스가 바뀌므로, 이 대조는 서명 전 vendor 원본에서만 성립한다.)
if [ -f "$ROOT/vendor/jq/build/jq" ]; then
  t_eq "fetch-jq.sh --check" "0" \
    "$("$ROOT/scripts/fetch-jq.sh" --check >/dev/null 2>&1; echo $?)"
else
  dim "   vendor/jq/build/jq 없음 — 건너뜀 (./scripts/fetch-jq.sh)"
fi

t_start "번들이 dt_helper 가 찾는 경로와 맞는다"
# ⚠️ lib/common.sh 의 2순위가 .app/Contents/Helpers/devtrail-helper 다.
#    한쪽만 바꾸면 조용히 폴백으로 떨어진다.
t_contains "dt_helper 가 Helpers 를 본다" "Helpers/devtrail-helper" \
  "$(cat "$ROOT/lib/common.sh")"

if [ ! -d "$APP" ]; then
  t_start "빌드 산출물"
  dim "   app/build/DevTrail.app 없음 — 건너뜀 (⚠️ 실제 모양을 못 본다)"
  dim "   빌드: ./app/build.sh"
  t_end
  exit 0
fi

t_start "⚠️ 산출물이 실제로 universal 이다"
for rel in "Contents/MacOS/DevTrail" "Contents/Helpers/devtrail-helper" "Contents/Helpers/jq"; do
  f="$APP/$rel"
  if [ ! -f "$f" ]; then
    _t_bad "$rel" "번들에 없습니다" "$f"
    FAILED=1
    continue
  fi
  archs=$(lipo -archs "$f" 2>/dev/null)
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) _t_ok "$rel — $archs" ;;
    *) _t_bad "$rel" "universal 이 아닙니다" "$archs"; FAILED=1 ;;
  esac
done

t_start "번들 안 헬퍼가 실제로 실행된다"
# ⚠️ 복사만 하고 실행 권한이 빠지거나 서명이 깨지면 여기서 걸린다.
#    "파일이 있다" 와 "돈다" 는 다른 문제다.
t_eq "version 이 답한다" "0" \
  "$("$APP/Contents/Helpers/devtrail-helper" version >/dev/null 2>&1; echo $?)"
t_eq "생성기가 답한다" "0" \
  "$("$APP/Contents/Helpers/devtrail-helper" gen-hotkeys daily \
       "$ROOT/preset/obsidian/hotkeys.tmpl.json" /dev/null "" >/dev/null 2>&1; echo $?)"

t_start "번들 안 jq 가 실제로 실행된다"
# ⚠️ 해시가 맞아도 못 돌 수 있다 — 서명이 깨지거나 실행 권한이 빠지는 경우다.
JQB="$APP/Contents/Helpers/jq"
t_eq "락이 적은 버전으로 답한다" \
  "$(jq -r '.version' "$ROOT/vendor/jq/jq.lock.json" 2>/dev/null)" \
  "$("$JQB" --version 2>/dev/null)"
t_eq "실제로 JSON 을 처리한다" "6" \
  "$(printf '{"a":[1,2,3]}' | "$JQB" -c '.a|add' 2>/dev/null)"

t_start "라이선스가 원본 그대로 실려 있다"
# ⚠️ MIT 하나가 아니다 — jq · Lucent decNumber · ICU · KTH · NetBSD strptime
#    다섯 블록이 한 파일에 있다. 요약해서 넣으면 그 자체로 라이선스 위반이다.
LICF="$APP/Contents/Resources/licenses/jq-COPYING.txt"
t_eq "번들에 있다" "yes" "$([ -f "$LICF" ] && echo yes || echo no)"
t_eq "락에 적힌 해시와 같다" \
  "$(jq -r '.license.sha256' "$ROOT/vendor/jq/jq.lock.json" 2>/dev/null)" \
  "$(shasum -a 256 "$LICF" 2>/dev/null | cut -d' ' -f1)"

t_start "⚠️ 번들 배치에서 CLI 가 번들 jq 를 집는다"
# ⚠️ 이게 이 작업의 핵심이다. jq 는 40개 파일 139곳에서 **맨몸으로** 불린다.
#    번들 안에 파일만 있고 PATH 가 안 서면, jq 없는 기계에서 앱은 켜지는데
#    기능이 전부 죽는다 — 그리고 만든 사람 기계에서는 재현되지 않는다.
#
#    그래서 **jq 가 없는 PATH** 를 만들어 놓고, 번들 배치에서 common.sh 를
#    읽었을 때 jq 가 잡히는지 본다.
JQTMP=$(mktemp -d)
mkdir -p "$JQTMP/bin" "$JQTMP/app/Contents/Resources" "$JQTMP/app/Contents/Helpers"
for t in bash sh sed grep cut head tail tr cat dirname basename printf mktemp \
         rm date awk sort uniq wc find ls cp mv chmod mkdir id od stat; do
  tp=$(command -v "$t" 2>/dev/null) && ln -sf "$tp" "$JQTMP/bin/$t"
done
cp -R "$ROOT/lib" "$JQTMP/app/Contents/Resources/" 2>/dev/null
cp "$JQB" "$JQTMP/app/Contents/Helpers/jq" 2>/dev/null

# 전제: 이 PATH 에는 jq 가 없다. (없어야 이 시험이 의미가 있다)
t_eq "전제 — 맨 PATH 에 jq 가 없다" "" \
  "$(env -i PATH="$JQTMP/bin" "$JQTMP/bin/bash" -c 'command -v jq' 2>/dev/null)"

t_eq "번들 배치에서 jq 가 잡힌다" \
  "$JQTMP/app/Contents/Helpers/jq" \
  "$(env -i PATH="$JQTMP/bin" HOME="$JQTMP" \
       DEVTRAIL_ROOT="$JQTMP/app/Contents/Resources" \
       "$JQTMP/bin/bash" -c '. "$DEVTRAIL_ROOT/lib/common.sh" >/dev/null 2>&1; command -v jq' 2>/dev/null)"

t_eq "그 jq 가 실제로 답한다" "6" \
  "$(env -i PATH="$JQTMP/bin" HOME="$JQTMP" DT_IN='{"a":[1,2,3]}' \
       DEVTRAIL_ROOT="$JQTMP/app/Contents/Resources" \
       "$JQTMP/bin/bash" -c '. "$DEVTRAIL_ROOT/lib/common.sh" >/dev/null 2>&1
                             printf %s "$DT_IN" | jq -c ".a|add"' 2>/dev/null)"

# ⚠️ 시스템에 **다른 jq 가 있어도** 번들 것이 이겨야 한다.
#
#    뒤에 붙이면 기계마다 다른 jq 가 잡힌다 — 우리가 해시를 못 박고 실제로
#    돌려 본 그 버전이 아니게 된다. jq 는 판마다 출력이 조금씩 달라서,
#    그때 생기는 어긋남은 "왜 저 사람 기계에서만" 이 된다.
#
#    앞의 시험들은 PATH 에 jq 가 없어서 앞/뒤 어느 쪽이든 통과한다. 여기서
#    미끼를 심어 순서를 실제로 확인한다.
printf '#!/bin/sh\necho jq-0.0.0-decoy\n' > "$JQTMP/bin/jq"
chmod +x "$JQTMP/bin/jq"
t_eq "전제 — 미끼 jq 가 먼저 잡힌다" "jq-0.0.0-decoy" \
  "$(env -i PATH="$JQTMP/bin" "$JQTMP/bin/bash" -c 'jq --version' 2>/dev/null)"
t_eq "번들 jq 가 시스템 jq 를 이긴다" \
  "$(jq -r '.version' "$ROOT/vendor/jq/jq.lock.json" 2>/dev/null)" \
  "$(env -i PATH="$JQTMP/bin" HOME="$JQTMP" \
       DEVTRAIL_ROOT="$JQTMP/app/Contents/Resources" \
       "$JQTMP/bin/bash" -c '. "$DEVTRAIL_ROOT/lib/common.sh" >/dev/null 2>&1
                             jq --version' 2>/dev/null)"
rm -f "$JQTMP/bin/jq"

# ⚠️ 번들이 아닐 때는 PATH 를 건드리지 않는다. 개발 중에는 각자의 jq 를 쓴다.
t_eq "번들이 아니면 PATH 를 안 건드린다" "" \
  "$(env -i PATH="$JQTMP/bin" HOME="$JQTMP" DEVTRAIL_ROOT="$ROOT" \
       "$JQTMP/bin/bash" -c '. "$DEVTRAIL_ROOT/lib/common.sh" >/dev/null 2>&1; command -v jq' 2>/dev/null)"
rm -rf "$JQTMP"

t_start "⚠️ 실물 번들의 CLI 가 자기 자산만 쓴다"
# ⚠️ 이게 M4-3 의 핵심이다. 앱은 화면일 뿐이고 일은 CLI 가 한다 — CLI 가
#    저장소를 쳐다보면, 개발자 기계에서만 되는 앱이 된다.
#
#    앞선 시험들(PATH 기전)은 **번들 배치를 흉내 낸 하니스**였다. 여기서는
#    빌드된 .app 을 **다른 경로로 옮겨** 실제로 돌린다 — 저장소와의 상대
#    위치가 달라지므로, 저장소에 기대고 있으면 여기서 드러난다.
CLI_B="$APP/Contents/Resources/bin/devtrail"
t_eq "번들에 CLI 가 있다" "yes" "$([ -x "$CLI_B" ] && echo yes || echo no)"

if [ -x "$CLI_B" ]; then
  MOVED=$(mktemp -d)
  cp -R "$APP" "$MOVED/DevTrail.app"
  MCLI="$MOVED/DevTrail.app/Contents/Resources/bin/devtrail"

  # ⚠️ cwd 를 저장소 바깥으로 둔다. 상대경로에 기대면 여기서 죽는다.
  t_eq "옮긴 번들이 무관한 cwd 에서 답한다" "devtrail $(tr -d ' \n' < "$ROOT/VERSION")" \
    "$( (cd / && "$MCLI" version 2>/dev/null | head -1) )"

  # ⚠️ DEVTRAIL_ROOT 가 **자기 번들 안**을 가리켜야 한다.
  #
  #    관측점: doctor 가 찍는 헬퍼 경로는 $DEVTRAIL_ROOT/../Helpers 에서
  #    나온다. `path --dt-root` 같은 건 **없다** — 없는 명령에 `||` 폴백을
  #    달면 폴백이 dirname 을 다시 계산할 뿐이라 단언이 공허해진다.
  #    (첫 판에서 실제로 그렇게 썼다가 잡았다.)
  MEXP="$MOVED/DevTrail.app/Contents/Resources/../Helpers/devtrail-helper"
  t_eq "자기 번들을 루트로 잡는다" "$MEXP" \
    "$( (cd / && "$MCLI" doctor 2>/dev/null) | grep -o "$MOVED[^ ]*devtrail-helper" | head -1)"

  # ⚠️ 출력 어디에도 저장소 경로가 나오면 안 된다. 나오면 기대고 있는 것이다.
  t_eq "출력에 저장소 경로가 안 샌다" "0" \
    "$( (cd / && "$MCLI" doctor 2>/dev/null | grep -c "$ROOT/") )"

  # ── jq 우선순위 — 이번엔 **실물 번들**에서 ────────────────────────────
  JD=$(mktemp -d)
  printf '#!/bin/sh\necho jq-0.0.0-decoy\n' > "$JD/jq"; chmod +x "$JD/jq"
  t_eq "전제 — 미끼 jq 가 PATH 앞에 있다" "jq-0.0.0-decoy" \
    "$(PATH="$JD:/usr/bin:/bin" jq --version 2>/dev/null)"
  t_eq "실물 번들에서 번들 jq 가 이긴다" \
    "$MOVED/DevTrail.app/Contents/Helpers/jq" \
    "$(PATH="$JD:/usr/bin:/bin" bash -c \
        '. "$1/Contents/Resources/lib/common.sh" >/dev/null 2>&1; command -v jq' \
        _ "$MOVED/DevTrail.app" 2>/dev/null)"
  rm -rf "$JD"

  # ── 코드 위치를 바꾸는 환경변수가 앱을 딴 데로 못 돌린다 ──────────────
  #
  # ⚠️ 사용자 환경에 개발용 DEVTRAIL_ROOT 가 남아 있을 수 있다
  #    (launchctl setenv · 터미널에서 띄운 경우). 그때 번들 앱이 조용히
  #    저장소 코드를 쓰면, 그 기계에서만 다르게 동작한다.
  t_eq "DEVTRAIL_ROOT 가 오염돼도 번들을 쓴다" "$MEXP" \
    "$( (cd / && DEVTRAIL_ROOT="$ROOT" "$MCLI" doctor 2>/dev/null) \
        | grep -o "$MOVED[^ ]*devtrail-helper" | head -1)"
  # ⚠️ 그리고 저장소 쪽 헬퍼가 **한 번도** 안 나와야 한다.
  t_eq "저장소 빌드 헬퍼로 안 떨어진다" "0" \
    "$( (cd / && DEVTRAIL_ROOT="$ROOT" "$MCLI" doctor 2>/dev/null) | grep -c "$ROOT/app/.build")"

  # ⚠️ 번들 안 plugin 을 쓰는가 — command-center 설치 원본이다.
  t_eq "command-center 원본이 번들 안이다" "yes" \
    "$([ -f "$MOVED/DevTrail.app/Contents/Resources/plugin/main.js" ] && echo yes || echo no)"

  rm -rf "$MOVED"
fi

t_start "기존 CLI 와 공존한다 (D4)"
# ⚠️ D4 는 "기존 CLI 와 DMG 앱은 공존한다" 로 정했다. 공존의 뜻은 둘이다:
#
#    ① 앱은 **자기 번들 CLI** 를 쓴다. 앱과 CLI 는 한 릴리즈로 함께 나가고,
#       섞이면 사용자 볼트가 조용히 어긋난다 — M6 매니페스트가 막으려는 것.
#    ② 그러면서 사용자가 따로 설치한 CLI 를 **건드리지 않는다.**
if [ -x "$CLI_B" ]; then
  # ① 앱이 번들을 설치본보다 먼저 본다.
  #    ⚠️ 순서가 핵심이다. "번들을 본다" 만으로는 부족하다 — 설치본을 먼저
  #       보면 낡은 CLI 가 새 앱에 붙는다.
  CS=$(grep -vE '^\s*//' "$ROOT/app/Sources/DevTrailApp/CLI.swift")
  t_eq "번들을 후보로 본다" "yes" \
    "$(printf '%s' "$CS" | grep -q 'if let b = bundled' && echo yes || echo no)"
  # ⚠️ 코드 위치를 바꾸는 환경변수를 자식에게 물려주지 않는다.
  #
  #    bin/devtrail 은 자기 위치에서 DEVTRAIL_ROOT 를 다시 정하므로 그건
  #    막힌다. 하지만 DT_CC_SRC_OVERRIDE · DT_HELPER_OVERRIDE 는 **아무도
  #    막지 않는다** — 사용자 환경에 남아 있으면 번들 앱이 조용히 저장소
  #    코드를 쓴다(launchctl setenv · 터미널에서 띄운 경우).
  #
  #    ⚠️ 이 단언은 **소스를 본다.** 메뉴바 GUI 앱을 이 스위트에서 띄워
  #       확인할 방법이 없다. 한계를 알고 쓴다 — 행동으로 막히는 것은
  #       위의 "DEVTRAIL_ROOT 가 오염돼도 번들을 쓴다" 뿐이다.
  STRIP=$(printf '%s\n' "$CS" | sed -n 's/.*for k in \[\(.*\)\] {.*/\1/p' | head -1)
  for _k in DEVTRAIL_ROOT DT_CC_SRC_OVERRIDE DT_HELPER_OVERRIDE; do
    t_eq "자식 환경에서 $_k 를 지운다" "1" \
      "$(printf '%s\n' "$STRIP" | grep -cw "$_k" | tr -d ' ')"
  done
  t_eq "지우는 코드가 실제로 돈다" "1" \
    "$(printf '%s\n' "$CS" | grep -c 'env\.removeValue(forKey: k)' | tr -d ' ')"

  t_eq "번들이 설치 경로보다 먼저다" "yes" \
    "$(printf '%s\n' "$CS" | awk '
        /if let b = bundled/ && !b { b = NR }
        /\.local\/bin\/devtrail/ && !c { c = NR }
        END { print (b && c && b < c) ? "yes" : "no" }')"

  # ② 번들 CLI 를 돌려도 설치본 트리가 **한 바이트도** 안 바뀐다.
  #    ⚠️ 실제 설치본(~/.devtrail/src)은 건드리지 않는다. 흉내 낸 트리를 쓴다.
  FAKE=$(mktemp -d)
  cp -R "$ROOT/bin" "$ROOT/lib" "$ROOT/VERSION" "$FAKE/" 2>/dev/null
  before=$(cd "$FAKE" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256)
  QH=$(mktemp -d)
  for _c in version doctor "config effective"; do
    # shellcheck disable=SC2086
    (cd / && DEVTRAIL_HOME="$QH" "$CLI_B" $_c >/dev/null 2>&1) || true
  done
  after=$(cd "$FAKE" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256)
  t_eq "번들 CLI 가 설치본 트리를 안 건드린다" "$before" "$after"
  rm -rf "$FAKE" "$QH"
fi

t_start "온보딩 — UI 에 판정이 없다 (M4-4b)"
# ⚠️ 이 저장소의 규칙이다: **UI 에 로직을 넣지 말 것.** 같은 판정을 CLI 와
#    앱에 두 벌 두면 반드시 어긋나고, 어긋난 쪽이 화면이면 사용자가 먼저 본다.
MV=$(grep -vE '^\s*//' "$ROOT/app/Sources/DevTrailApp/MenuView.swift")
t_eq "화면이 link 상태를 직접 계산하지 않는다" "0" \
  "$(printf '%s\n' "$MV" | grep -cE 'linked_here|linked_other|occupied' \
     | tr -d ' ' | awk '{ print ($1 > 4) ? 1 : 0 }')"
t_eq "화면이 파일 시스템을 직접 보지 않는다" "0" \
  "$(printf '%s\n' "$MV" | grep -cE 'FileManager|readlink|symlink' | tr -d ' ')"
# ⚠️ 판정은 CLI 가 낸 것을 읽기만 한다.
ST=$(grep -vE '^\s*//' "$ROOT/app/Sources/DevTrailApp/Status.swift")
t_eq "Status 가 link status --json 을 읽는다" "1" \
  "$(printf '%s\n' "$ST" | grep -c '"link", "status", "--json"' | tr -d ' ')"
t_eq "연결은 CLI 에 맡긴다" "1" \
  "$(printf '%s\n' "$ST" | grep -c '"link", "create"' | tr -d ' ')"

t_start "온보딩 — 번들에서 거짓 안내를 하지 않는다"
# ⚠️ 앱 안에 CLI 가 실려 나가므로(M4-3), 번들인데 CLI 가 없다면 그건
#    **번들이 손상된** 것이다. 그때 "curl | bash 로 설치하세요" 는 거짓말이다.
t_eq "curl 안내는 번들이 아닐 때만" "1" \
  "$(printf '%s\n' "$MV" | grep -c 'if CLI.bundled == nil' | tr -d ' ')"

t_start "번들 CLI 자산이 코드와 어긋나지 않는다"
# ⚠️ 목록을 손으로 관리하지 않는다. 코드의 $DEVTRAIL_ROOT/<무엇> 참조에서
#    유도한다 — 새 참조가 생기면 여기서 잡힌다.
t_eq "check-bundle-assets.py" "0" \
  "$(python3 "$ROOT/tests/check-bundle-assets.py" >/dev/null 2>&1; echo $?)"

t_start "Info.plist 가 D1 과 맞는다"
MIN=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist" 2>/dev/null)
PKG=$(grep -oE 'macOS\(\.v([0-9]+)\)' "$ROOT/app/Package.swift" | grep -oE '[0-9]+' | head -1)
t_eq "LSMinimumSystemVersion 이 Package.swift 와 같다" "${PKG}.0" "$MIN"
t_eq "메뉴바 전용(LSUIElement)" "true" \
  "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist" 2>/dev/null)"
t_eq "번들 버전이 VERSION 과 같다" "$(tr -d ' \n' < "$ROOT/VERSION")" \
  "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null)"

t_start "서명이 번들 안쪽까지 닿는다"
# ⚠️ 번들만 서명하면 Contents/Helpers 안의 실행 파일이 서명되지 않은 채
#    남고, 공증(M7)에서 거부된다. ad-hoc 이라도 지금 확인해 둔다.
t_eq "번들 서명 확인" "0" "$(codesign --verify "$APP" >/dev/null 2>&1; echo $?)"
t_eq "헬퍼 서명 확인" "0" \
  "$(codesign --verify "$APP/Contents/Helpers/devtrail-helper" >/dev/null 2>&1; echo $?)"
t_eq "번들 jq 서명 확인" "0" \
  "$(codesign --verify "$APP/Contents/Helpers/jq" >/dev/null 2>&1; echo $?)"

# ══ 파괴적 시험은 **맨 뒤**에 둔다 ══════════════════════════════════════════
#
# ⚠️ 여기서부터는 build.sh 를 실제로 돌려 번들을 다시 만든다. 위쪽에 두면
#    앞선 단언들이 보던 산출물이 중간에 갈아엎어져서, 산출물을 손으로
#    바꿔 넣는 변이가 전부 무효가 된다 — 2026-08-24 에 실제로 그랬다.
#    (산출물 변이 4건이 "생존" 으로 보였는데, 게이트가 약한 게 아니라
#     시험이 스스로 변이를 지우고 있었다.)

t_start "⚠️ 서명이 실패하면 빌드가 선다"
# ⚠️ 문서와 아래 단언은 "안쪽부터 서명한다" 를 **배포 계약**으로 말한다.
#    그렇다면 실패 정책도 같아야 한다 — 예전에는 `|| true` 로 넘겨서,
#    서명이 통째로 실패해도 빌드가 초록불로 끝났다. 그 차이는 M7 공증에서야
#    드러나고, 그때는 원인이 멀어져 있다.
#
#    문자열로는 확인할 수 없다(`|| true` 를 지워도 다른 줄이 grep 을 속인다).
#    **실제로 실패시켜 본다** — 우리 번들에만 실패하는 codesign 을 심는다.
if [ -d "$APP" ]; then
  CSD=$(mktemp -d)
  cat > "$CSD/codesign" <<'FAKE'
#!/bin/sh
# 우리 번들을 건드릴 때만 실패한다. swift 빌드가 쓰는 서명은 그대로 둔다.
case "$*" in
  *DevTrail.app*) echo "fake codesign: refusing" >&2; exit 1 ;;
esac
exec /usr/bin/codesign "$@"
FAKE
  chmod +x "$CSD/codesign"
  t_eq "서명이 실패하면 build.sh 가 실패한다" "no" \
    "$( (cd "$ROOT" && PATH="$CSD:$PATH" ./app/build.sh >/dev/null 2>&1) && echo yes || echo no)"

  # ⚠️ **서명은 됐는데 유효하지 않은** 경우도 있다 — 바깥 번들을 서명한 뒤
  #    안쪽이 바뀌면 조용히 깨진다. 붙였다는 것과 유효하다는 것은 다르므로,
  #    검증 루프만 따로 실패시켜 그 루프가 실제로 지키는지 본다.
  cat > "$CSD/codesign" <<'FAKE2'
#!/bin/sh
# --verify 일 때만, 그리고 우리 번들일 때만 실패한다.
case "$*" in
  *--verify*DevTrail.app*) echo "fake codesign: verify refused" >&2; exit 1 ;;
esac
exec /usr/bin/codesign "$@"
FAKE2
  chmod +x "$CSD/codesign"
  t_eq "서명 검증이 실패해도 build.sh 가 실패한다" "no" \
    "$( (cd "$ROOT" && PATH="$CSD:$PATH" ./app/build.sh >/dev/null 2>&1) && echo yes || echo no)"

  rm -rf "$CSD"
  # ⚠️ 앞선 시험이 번들을 반쯤 만들어 두었을 수 있다. 되돌려 놓는다 —
  #    뒤따르는 단언들이 실물을 보기 때문이다.
  (cd "$ROOT" && ./app/build.sh >/dev/null 2>&1) \
    || dim "   ⚠️ 번들 재빌드 실패 — 뒤 단언이 헛돌 수 있습니다"
fi

t_end
