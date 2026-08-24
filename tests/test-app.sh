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
SUMMARY_TEMPLATE="$(cat "$ROOT/templates/scripts/summary.sh.tmpl")"
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
for bad in "notes/" "\{\{DATE\}\}"; do
  t_eq "경로를 짐작하지 않는다: $bad" "0" "$(printf '%s' "$CODE" | grep -cE "$bad")"
done
# hotkeys.json은 파일 경로·노트 규칙이 아니라 Obsidian이 확정한 키 배정의
# 읽기 전용 출처다. 메뉴가 기본값을 거짓으로 보여주지 않도록 정확히 이 파일만
# 읽는 것은 허용한다.
t_contains "실제 단축키 설정만 읽는다" "/.obsidian/hotkeys.json" "$CODE"
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

t_start "첫 실행은 메뉴바 아이콘을 찾게 하지 않는다"
# MenuBarExtra 의 내용은 사용자가 아이콘을 눌러야 만들어진다. 미설정 사용자는
# 그 전에 중앙 온보딩 창을 한 번 봐야 한다. 이미 설정한 사람에게 매번 창을
# 띄우면 메뉴바 앱의 장점이 사라지므로 needsSetup 조건도 함께 본다.
t_contains "앱 시작을 AppDelegate 가 받는다" "applicationDidFinishLaunching" "$ALL"
t_contains "미설정일 때만 첫 실행 창을 연다" "guard status.needsSetup" "$ALL"
t_contains "첫 실행 창은 독립 NSWindow 다" "NSWindow(" "$ALL"
t_contains "첫 실행 전용 화면을 연다" "NSHostingView(rootView: FirstRunView" "$ALL"
t_contains "첫 실행 창을 앞으로 가져온다" "window.makeKeyAndOrderFront(nil)" "$ALL"
t_contains "첫 실행 화면은 볼트·언어를 역할별 카드로 묶는다" "볼트 선택" "$ALL"
t_contains "첫 실행 화면은 선택 설정을 접어 둔다" "DisclosureGroup(\"선택 설정" "$ALL"
t_contains "첫 실행 화면은 GitHub·동기화·AI를 선택형으로 둔다" "나중에 연결해도 됩니다" "$ALL"
t_contains "앱이 전체 설정을 CLI로 넘긴다" "--github-user" "$ALL"
t_contains "GitHub 입력 형식을 설명한다" "프로필 URL이 아닌 아이디입니다" "$ALL"

t_start "홈은 오늘의 행동을 먼저 보여준다"
t_contains "오늘 카드가 있다" "private var todayCard" "$ALL"
t_contains "오늘 개발일지 생성 행동이 있다" "오늘 개발일지 만들기" "$ALL"
t_contains "개발일지는 CLI로 표준 본문을 만든다" "func createTodayDevlog" "$ALL"
t_contains "없는 일지에서 활동 삽입을 부르지 않는다" "else { status.createTodayDevlog() }" "$ALL"
t_contains "일지 생성은 CLI에 맡긴다" "[\"capture\", \"devlog\", \"--apply\", \"--repair-empty\"]" "$ALL"
t_contains "부가 기능은 더보기에 둔다" "DisclosureGroup(\"더보기\")" "$ALL"

t_start "개발일지 핵심 단축키를 메뉴바에도 보여준다"
t_contains "개발일지 도구 구역이 있다" "private var devlogToolbar" "$ALL"
t_contains "실제 Obsidian 단축키를 읽는다" "func hotkey(for command" "$ALL"
t_contains "활동 키는 실제 배정값을 쓴다" "status.hotkey(for: activityCommand)" "$ALL"
t_contains "PR 키는 실제 배정값을 쓴다" "status.hotkey(for: summaryCommand)" "$ALL"
t_contains "오늘 이슈/PR을 메뉴바에서 바로 넣는다" "func fetchTodayActivity" "$ALL"
t_contains "메뉴바의 오늘 이슈/PR은 이미 만든 오늘 블록도 새로고침한다" '["activity", "--refresh"]' "$ALL"
t_contains "활동 완료·실패를 메뉴바에서 말한다" "activityResult" "$ALL"
t_contains "백필 버튼이 날짜 입력을 바로 연다" "showBackfillComposer = true" "$ALL"
t_contains "백필 완료·실패를 메뉴바에서 말한다" "backfillResult" "$ALL"
t_not_contains "지원하지 않는 Obsidian command URI를 열지 않는다" "obsidian://command?commandname=" "$ALL"

t_start "AI 작업은 메뉴바에서 바로 시작한다"
# 설치된 스킬 이름을 나열하지 않는다. 누르면 결과가 생기는 두 작업만 앞에 둔다.
t_contains "AI 작업 구역이 있다" "private var aiActions" "$ALL"
t_contains "유튜브 정리를 바로 연다" "유튜브 정리" "$ALL"
t_contains "유튜브 정리가 캡처 입력을 연다" "showCaptureComposer.toggle()" \
  "$(sed -n '/private var aiActions/,/^    }/p' "$SRC/MenuView.swift")"
t_not_contains "AI 영역에 PR 요약을 중복하지 않는다" "summarizePullRequests" \
  "$(sed -n '/private var aiActions/,/^    }/p' "$SRC/MenuView.swift")"
t_contains "PR 요약은 개발일지 도구에서 실행한다" "status.summarizePullRequests()" \
  "$(sed -n '/private var devlogToolbar/,/^    }/p' "$SRC/MenuView.swift")"
t_contains "PR 요약은 전용 상태로 실행한다" 'CLI.runAsync(["summary"])' "$ALL"
t_contains "날짜 백필도 개발일지 도구에 있다" "shortcutTool(\"calendar.badge.clock\", \"백필\"" "$ALL"
t_contains "백필은 날짜를 먼저 확인하게 한다" "func prepareBackfill" "$ALL"

t_start "유튜브 정리 상태를 결과별로 보여준다"
t_contains "실행 중 상태가 있다" "유튜브 정리 중…" "$ALL"
t_contains "완료 상태가 있다" "유튜브 정리를 완료했습니다" "$ALL"
t_contains "실패 상태가 있다" "유튜브 정리에 실패했습니다" "$ALL"
t_contains "실패 로그를 보존한다" "self.lastOutput = r.text" "$ALL"
t_contains "실패 원인은 stderr를 먼저 보여준다" "let error = r.err" "$ALL"
t_contains "저장 후 AI 분석 불가를 별도 상태로 둔다" "captureWarning" "$ALL"
t_contains "저장 표식이 있으면 부분 성공으로 처리한다" "Status.capturePath(from: r.text)" "$ALL"
t_contains "중복 링크는 기존 노트로 안내한다" "DEVTRAIL_CAPTURE_DUPLICATE=" "$ALL"
t_contains "분석 불가를 빨간 실패로 보이지 않는다" "링크는 저장했고, AI 요약만 건너뛰었습니다" "$ALL"

t_start "PR AI 요약도 결과를 남긴다"
t_contains "PR 요약 실행 중 상태가 있다" "PR AI 요약 중…" "$ALL"
t_contains "PR 요약 완료 상태가 있다" "PR AI 요약을 완료했습니다" "$ALL"
t_contains "PR 요약 실패 상태가 있다" "PR AI 요약을 완료하지 못했습니다" "$ALL"
t_contains "PR 요약은 실제 삽입 완료를 확인한다" "요약 삽입 완료" "$ALL"
t_contains "PR 요약 섹션 누락을 성공으로 보지 않는다" "섹션 없음 - 건너뜀" "$ALL"
t_contains "PR 요약 중복은 전용 마커로 판단한다" "devtrail:pr-summary" "$SUMMARY_TEMPLATE"
t_contains "PR 요약은 최신 활동 표를 사용한다" "devtrail:activity:end" "$SUMMARY_TEMPLATE"

t_start "저장은 한 번만 눌린다"
# ⚠️ 두 번 누르면 노트가 두 개 생긴다. CLI 의 중복 검사가 잡아 주지만,
#    그건 마지막 방어선이지 첫 방어선이 아니다.
# ⚠️ 화면의 disabled 만 보면, 모델의 가드를 지워도 통과한다 — 실제로
#    그랬다. 두 곳을 다 본다.
t_contains "화면이 버튼을 잠근다" "disabled(status.captureBusy" "$ALL"
t_contains "모델도 막는다" "guard !captureBusy else { return }" \
  "$(sed -n '/func captureYouTube/,/^    }/p' "$SRC/Status.swift")"
t_contains "유튜브 분류 누락을 완료로 오해하지 않는다" "DEVTRAIL_CAPTURE_AI=partial" \
  "$(sed -n '/func captureYouTube/,/^    }/p' "$SRC/Status.swift")"
t_contains "AI 요약이 켜진 경우에만 자동 정리를 요청한다" 'args.append("--ai")' \
  "$(sed -n '/func captureYouTube/,/^    }/p' "$SRC/Status.swift")"

t_start "일반 웹 링크도 메뉴바에서 저장한다"
t_contains "URL 종류를 자동 구분한다" "func captureLink" "$ALL"
t_contains "YouTube가 아닌 링크는 웹 캡처로 보낸다" "captureWeb(url, apply: apply)" "$ALL"
t_contains "일반 웹 링크는 CLI 인자로 안전하게 보낸다" '["capture", "web", "--url", trimmed]' "$ALL"
t_contains "웹 링크는 AI 없이 저장한다고 안내한다" "일반 웹 링크는 AI 없이 자료실에 안전하게 저장합니다" "$ALL"
t_contains "링크 저장 입력을 바로 연다" "tool(\"link.badge.plus\", \"링크 저장\")" "$ALL"
t_contains "성공한 링크 입력은 다음 저장을 위해 비운다" "captureCompletedID" "$ALL"
t_contains "실패한 URL은 화면이 지우지 않는다" ".onChange(of: status.captureCompletedID)" "$ALL"

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
