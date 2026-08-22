#!/usr/bin/env bash
# 메뉴바 앱의 경계 — 앱은 읽고 부를 뿐, 쓰지 않는다 (ADR 0003)
#
# ⚠️ Swift 는 빌드만 통과하면 '동작한다' 고 착각하기 쉽다. 여기서 보는 것은
#    컴파일이 아니라 **경계**다: 앱이 Markdown 을 스스로 해석하지 않는가,
#    셸을 거치지 않는가, 렌더마다 CLI 를 부르지 않는가.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
SRC="$ROOT/app/Sources/DevTrailApp"
ALL="$(cat "$SRC"/*.swift)"
# ⚠️ 주석까지 훑으면 "우리는 frontmatter 를 해석하지 않는다" 는 주석이
#    위반으로 잡힌다. 검사 대상은 코드다.
CODE="$(cat "$SRC"/*.swift | sed 's#//.*##; s#/\*.*\*/##')"

t_start "앱은 볼트에 쓰지 않는다"
# ⚠️ 노트를 만드는 것은 CLI 하나뿐이다. 앱이 직접 쓰면 형식이 두 곳에서
#    만들어지고, 그 순간 저널도 undo 도 우회된다.
# ⚠️ 볼트에 쓰지 않는다. 앱이 만드는 유일한 파일은 사용자가 터미널에서
#    실행할 setup.command 이고, 그건 볼트 밖이다 — 그 하나만 허용한다.
t_eq "볼트 경로에 쓰지 않는다" "0" \
  "$(printf '%s' "$CODE" | grep -cE "write\(to:.*(vault|notes|Vault)")"
t_eq "노트를 만들지 않는다" "0" \
  "$(printf '%s' "$CODE" | grep -cE "createFile|FileHandle.*writ")"
t_eq "파일 쓰기는 setup.command 하나뿐" "1" \
  "$(printf '%s' "$CODE" | grep -cE "\.write\(to:")"
# frontmatter·템플릿을 앱이 해석하지 않는다.
for bad in "frontmatter" "tl_dr_oneline" "status: inbox" "type: project-home"; do
  t_eq "Markdown 을 해석하지 않는다: $bad" "0" "$(printf '%s' "$CODE" | grep -cE "$bad")"
done

t_start "셸을 거치지 않는다"
# ⚠️ URL 을 문자열로 이어 붙여 셸에 넘기면 따옴표·앰퍼샌드 하나에 무너진다.
#    YouTube URL 에는 & 가 흔하다.
# ⚠️ CLI 를 셸로 부르지 않는다. URL 에 & 가 흔해 거기서 잘린다.
#    (setup.command 안의 #!/bin/sh 는 사용자가 터미널에서 여는 launcher 라
#     별개다 — Process 로 셸을 띄우는 것과 다르다.)
t_eq "Process 를 셸로 띄우지 않는다" "0" \
  "$(printf '%s' "$CODE" | grep -cE "executableURL.*(/bin/sh|/bin/bash)|launchPath.*bin/(sh|bash)")"
t_eq "-c 로 명령을 넘기지 않는다" "0" \
  "$(printf '%s' "$CODE" | grep -cE '"-c"')"
t_contains "인자 배열로 넘긴다" "p.arguments = args" "$ALL"

t_start "Snapshot 을 JSON 으로만 소비한다"
t_contains "snapshot 을 부른다" "command-center" "$ALL"
t_contains "snapshot" "snapshot" "$ALL"
t_contains "JSON 으로 읽는다" "CLI.json" "$ALL"
# ⚠️ 경로 규칙을 앱이 다시 만들지 않는다 — CLI 가 단일 출처다.
# ⚠️ 경로·파일명 규칙을 앱이 갖지 않는다. CLI 가 단일 출처다 —
#    이 저장소는 dirs.devlog 로 같은 병을 네 번 고쳤다.
for bad in "notes/" "\.obsidian" "\{\{DATE\}\}"; do
  t_eq "경로를 짐작하지 않는다: $bad" "0" "$(printf '%s' "$CODE" | grep -cE "$bad")"
done
# ⚠️ 변수가 '있다' 와 devlogFile 이 '그걸 쓴다' 는 다르다. 이 세션에서
#    같은 방식으로 세 번 놓쳤다 — 선언이 아니라 사용을 본다.
t_contains "devlogFile 이 snapshot 경로를 그대로 쓴다" \
  "var devlogFile: String? { snapshotDevlogPath }" "$CODE"
# (한 줄짜리라 sed 범위 추출이 맞지 않는다 — 위의 정확 일치가 이미 지킨다.)

t_start "렌더마다 CLI 를 부르지 않는다"
# ⚠️ SwiftUI 의 body 는 자주 다시 그려진다. 거기서 프로세스를 띄우면
#    메뉴를 여는 것만으로 CLI 가 수십 번 뜬다.
BODY="$(printf '%s' "$ALL" | sed -n '/var body: some View/,/^    }/p')"
t_eq "body 안에서 CLI 를 부르지 않는다" "0" \
  "$(printf '%s' "$BODY" | grep -cE "CLI\.(run|json|start)")"
t_contains "명시적으로 새로고침한다" "refreshSnapshot" "$ALL"

t_start "저장은 한 번만 눌린다"
# ⚠️ 두 번 누르면 노트가 두 개 생긴다. CLI 의 중복 검사가 잡아 주지만,
#    그건 마지막 방어선이지 첫 방어선이 아니다.
# ⚠️ 화면의 disabled 만 보면, 모델의 가드를 지워도 통과한다 — 실제로
#    그랬다. 두 곳을 다 본다.
t_contains "화면이 버튼을 잠근다" "disabled(status.captureBusy" "$ALL"
t_contains "모델도 막는다" "guard !captureBusy else { return }" \
  "$(sed -n '/func captureYouTube/,/^    }/p' "$SRC/Status.swift")"

t_start "네트워크는 저장할 때만"
# ⚠️ URL 을 붙여넣는 것만으로 요청하면 사용자가 모르는 사이 통신이 일어난다.
t_eq "앱이 직접 통신하지 않는다" "0" \
  "$(printf '%s' "$ALL" | grep -cE "URLSession|dataTask|NSURLConnection")"

t_start "실패를 구분해 말한다"
for k in captureError; do
  t_contains "$k 가 있다" "$k" "$ALL"
done
# 되돌리는 길을 알려준다.
t_contains "undo 를 안내한다" "undo" "$ALL"

t_end
