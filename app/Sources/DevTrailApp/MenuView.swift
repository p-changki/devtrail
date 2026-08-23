import SwiftUI
import AppKit

/// 메뉴바 패널.
///
/// 구조 원칙:
///   - 자주 쓰는 것(실행)과 어쩌다 쓰는 것(설정)을 화면으로 분리한다.
///     한 화면에 다 쌓으면 패널이 길어지고, 매번 눈이 훑어야 할 항목이 늘어난다.
///   - 홈은 "지금 어떤 상태인가 + 지금 뭘 할 것인가"만 답한다.
///   - 실행 액션은 아이콘 툴바로 묶어 4줄을 1줄로 줄인다.
struct MenuView: View {
    @ObservedObject var status: Status
    @State private var showSettings = false

    private let panelWidth: CGFloat = 274

    @State private var captureURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // ⚠️ DMG 에서 그대로 돌면 **설치된 줄 안다** — 잘 돌기 때문이다.
            //    그런데 볼륨을 빼는 순간 앱이 사라진다. 2026-08-24 실물 QA 에서
            //    실제로 이 상태로 셋업까지 진행됐다.
            //
            //    판정은 CLI 가 한다. 여기서는 그리기만.
            if status.runningFromVolume {
                Divider().padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 11)).foregroundStyle(Color.dtWarning)
                        Text("아직 설치되지 않았습니다")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text("디스크 이미지에서 실행 중입니다. DevTrail 을 응용 프로그램 폴더로 끌어다 놓고, 거기서 다시 여세요.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("이대로 두면 이미지를 꺼내는 순간 앱이 사라집니다.")
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ⚠️ **설정이 먼저다.** 예전에는 needsSetup 이 먼저 걸려서,
            //    셋업 전에는 톱니를 눌러도 헤더만 "설정" 으로 바뀌고 몸통은
            //    셋업 화면 그대로였다 — 화면이 거짓말을 했고, **종료 버튼에
            //    도달할 방법이 없었다.** 메뉴바 앱은 ⌘Q 도 안 먹으므로
            //    강제 종료 말고는 끌 수가 없었다 (2026-08-24 실물 QA).
            if showSettings {
                settingsBody
            } else if status.cliMissing {
                Divider().padding(.vertical, 8)
                missing
            } else if status.needsSetup {
                Divider().padding(.vertical, 8)
                setup
            } else {
                homeBody
            }

            if !status.lastOutput.isEmpty {
                Divider().padding(.vertical, 7)
                output
            }
        }
        .padding(11)
        .frame(width: panelWidth)
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(healthColor).frame(width: 8, height: 8)
            Text(showSettings ? "설정" : "DevTrail")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let b = status.busy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(b).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                iconButton(showSettings ? "chevron.backward" : "gearshape",
                           help: showSettings ? "뒤로" : "설정") {
                    showSettings.toggle()
                }
                iconButton("arrow.clockwise", help: "새로고침") {
                    status.refresh()
                    status.refreshSnapshot()
                }
            }
        }
    }

    // MARK: - 홈

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            stats
            Divider().padding(.vertical, 8)
            vaultState
            Divider().padding(.vertical, 8)
            captureRow
            Divider().padding(.vertical, 8)
            toolbar
            Divider().padding(.vertical, 8)
            backfillRow
            Divider().padding(.vertical, 8)
            openRow
        }
    }

    // MARK: - Obsidian 없이 보는 상태
    //
    // ⚠️ 여기 숫자는 전부 CLI 의 snapshot 에서 온다. 앱이 Markdown 을
    //    읽거나 경로를 짐작하지 않는다 — 그러면 화면과 볼트가 갈린다.
    private var vaultState: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let err = status.snapshotError {
                // ⚠️ 못 읽은 것을 '0' 으로 보여주지 않는다.
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if let s = status.snapshot {
                if !s.vaultAvailable {
                    Label("볼트를 찾지 못했습니다", systemImage: "folder.badge.questionmark")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    stateLine("오늘",
                              s.today.map { $0.devlogExists ? "개발일지 있음" : "개발일지 없음" } ?? "확인 불가",
                              detail: s.today?.openTasks.map { $0 > 0 ? "할 일 \($0)개" : "" } ?? "")
                    stateLine("프로젝트",
                              s.activeProjects.map { "활성 \($0)개" } ?? "확인 불가",
                              detail: s.nextActions.first.map { "\($0.project) · \($0.text)" } ?? "")
                    stateLine("Inbox",
                              s.inboxCount.map { $0 == 0 ? "비어 있음" : "\($0)개" } ?? "확인 불가",
                              detail: (s.inboxCount ?? 0) > 0 ? (s.inboxPreview.first?.title ?? "") : "")
                    stateLine("Command Center", s.commandCenterLine, detail: "")
                }
            } else {
                Text("상태를 읽는 중…").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("볼트 상태")
    }

    private func stateLine(_ label: String, _ value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 11))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). \(detail)")
    }

    // MARK: - 링크 받아두기
    //
    // ⚠️ Obsidian 이 꺼져 있어도 된다. 노트를 만드는 것은 CLI 이고,
    //    저널에 남아 undo 로 사라진다 (ADR 0003).
    private var captureRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 10))
                Text("링크 받아두기").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("클립보드") {
                    // ⚠️ 자동으로 읽지 않는다. 누를 때만 읽는다.
                    captureURL = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .help("클립보드의 링크를 붙여넣습니다")
            }
            HStack(spacing: 6) {
                TextField("https://youtu.be/…", text: $captureURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(status.captureBusy)
                    .accessibilityLabel("유튜브 링크")
                Button(status.captureBusy ? "저장 중…" : "저장") {
                    status.captureYouTube(captureURL, apply: true)
                }
                .font(.system(size: 11))
                // ⚠️ 두 번 누르면 노트가 두 개 생긴다.
                .disabled(status.captureBusy || captureURL.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Obsidian 없이 볼트에 저장합니다")
            }
            if let e = status.captureError {
                Text(e).font(.system(size: 9.5)).foregroundStyle(.red).lineLimit(3)
            } else if let r = status.captureResult {
                Text(r).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(4)
                if let job = status.captureUndoJob {
                    Text("되돌리기: devtrail undo \(job) --apply")
                        .font(.system(size: 9)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.headline).font(.system(size: 12, weight: .medium))
            Text(status.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text("\(status.date) · \(status.githubUser.isEmpty ? "계정 미설정" : status.githubUser)")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
        }
        .padding(.top, 7)
    }

    /// 자주 쓰는 4개를 가로 아이콘으로. 세로 4줄 → 1줄.
    private var toolbar: some View {
        HStack(spacing: 4) {
            tool("arrow.down.circle", "활동")   { status.run("활동", ["activity"]) }
            tool("sparkles", "요약")            { status.run("요약", ["summary"]) }
            tool("calendar", "주간")            { status.run("주간리뷰", ["weekly"]) }
            tool("folder", "docs")              { status.run("동기화", ["sync"]) }
        }
    }

    private var backfillRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 13)
            TextField("YYYY-MM-DD", text: $status.backfillDate)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            Button("채우기") { status.runBackfill() }
                .font(.system(size: 11))
                .disabled(status.busy != nil)
        }
    }

    private var openRow: some View {
        HStack(spacing: 4) {
            linkButton("doc.text", "개발일지") {
                status.openInObsidian(path: status.devlogFile)
            }
            linkButton("folder.badge.gearshape", "주간리뷰") {
                status.openPath(status.weeklyDir)
            }
        }
    }

    // MARK: - 설정

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ 셋업 전에는 설정 파일이 없다. 토글을 보여주면 켜고 끌 대상이
            //    없는 스위치를 주는 셈이고, 누르면 조용히 아무 일도 안 난다.
            //    **나가는 길(종료)만 남긴다** — 그게 이 화면에서 필요한 전부다.
            if status.needsSetup {
                Text("아직 셋업하지 않았습니다")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.top, 8)
                Text("설정은 셋업을 마친 뒤에 쓸 수 있습니다.")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            } else {
            group("자동화") {
                // 자동 실행은 설정값이 아니라 launchd 등록 여부다.
                toggleRow("자동 실행", isOn: Binding(
                    get: { status.scheduleOn },
                    set: { status.setSchedule($0) }
                ))
                toggleRow("AI 요약", key: "ai.summary_enabled")
                toggleRow("볼트 백업", key: "backup.enabled")
                toggleRow("Linear 연동", key: "linear.enabled")
            }

            if status.launchAtLoginAvailable {
                group("앱") {
                    toggleRow("로그인 시 시작", isOn: Binding(
                        get: { status.launchAtLogin },
                        set: { status.setLaunchAtLogin($0) }
                    ))
                }
            }

            group("도구") {
                textRow("진단 실행", "stethoscope") { status.run("진단", ["doctor"]) }
            }
            }

            Divider().padding(.vertical, 7)
            HStack {
                Text(status.needsSetup ? "" : status.vaultLabel)
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
                    .buttonStyle(.plain).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 부품

    private func group<C: View>(_ title: String,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 9).padding(.bottom, 1)
            content()
        }
    }

    private func tool(_ icon: String, _ label: String,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 9.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 7))
        .disabled(status.busy != nil)
    }

    private func linkButton(_ icon: String, _ label: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 6))
    }

    private func textRow(_ title: String, _ icon: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 10.5)).frame(width: 13)
                Text(title).font(.system(size: 12))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 5))
        .disabled(status.busy != nil)
    }

    private func iconButton(_ icon: String, help: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 5))
        .help(help)
    }

    private func toggleRow(_ title: String, key: String) -> some View {
        toggleRow(title, isOn: Binding(
            get: { status.toggles[key] ?? false },
            set: { status.setToggle(key, $0) }
        ), unknown: !status.toggleKnown(key))
    }

    /// 레이블 길이가 달라도 스위치가 오른쪽에 정렬되도록 Spacer로 밀어낸다.
    ///
    /// `unknown`은 '값을 모른다'는 뜻이고 '꺼져 있다'가 아니다. 모르는 값을
    /// 꺼진 스위치로 그리면, 실제로는 백업·AI 요약이 돌고 있는데 꺼졌다고 믿게 된다.
    private func toggleRow(_ title: String, isOn: Binding<Bool>,
                           unknown: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(title).font(.system(size: 12))
                .foregroundStyle(unknown ? Color.secondary : Color.primary)
            Spacer(minLength: 8)
            if unknown {
                Text("값 불명")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dtWarning)
                    .help("설정을 읽지 못했습니다 — devtrail init 또는 doctor 를 확인하세요")
            } else {
                Toggle("", isOn: isOn)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .disabled(status.busy != nil)
            }
        }
        .padding(.vertical, 1)
    }

    private var output: some View {
        ScrollView {
            Text(status.lastOutput)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
    }

    /// 아직 셋업하지 않은 사용자.
    ///
    /// ⚠️ 여기가 앱을 먼저 연 사람이 처음 보는 화면이다. 예전에는 이 상태를
    ///    구분하지 않아 "오늘 개발일지 없음" 이라고만 했다 — 무엇을 해야
    ///    하는지 알 수 없는 막다른 길이었다.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("아직 셋업하지 않았습니다")
                .font(.system(size: 12, weight: .medium))
            Text("볼트 · Obsidian 플러그인 · 노트 템플릿을 한 번에 준비합니다.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { status.startSetup() }) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").font(.system(size: 11))
                    Text("셋업 시작").font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Hover(radius: 6))
            Text("터미널이 열리고 질문에 답하면 끝납니다.")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            terminalLink
        }
    }

    /// 터미널에서도 devtrail 을 쓸 수 있게 (ADR 0006 M4-4b).
    ///
    /// ⚠️ DMG 로 받은 사람의 PATH 에는 devtrail 이 없다. 앱은 번들 것을
    ///    절대경로로 부르니 잘 돌지만, 터미널에서는 없다.
    ///
    /// ⚠️ 여기에 **판정이 없다.** CLI 가 낸 상태를 그대로 그린다.
    @ViewBuilder
    private var terminalLink: some View {
        // ⚠️ 떼어낼 수 있는 볼륨에서는 연결을 권하지 않는다. 만들어도
        //    볼륨을 빼는 순간 죽고, 죽은 링크는 고치기 어렵다.
        if status.runningFromVolume {
            EmptyView()
        } else {
        switch status.linkState {
        case "absent":
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { status.linkTerminal() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal").font(.system(size: 10.5))
                        Text("터미널에서도 쓰기").font(.system(size: 11.5))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Hover(radius: 5))
                Text("\(status.linkPath) 에 연결합니다.")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }

        case "linked_here":
            linkNote("checkmark.circle", "터미널에 연결돼 있습니다", status.linkPath, .dtSuccess)

        case "linked_other":
            // ⚠️ 공존 (D4). 덮어쓰지 않았고, 앱은 번들 것을 쓴다.
            linkNote("arrow.triangle.branch", "다른 devtrail 이 연결돼 있습니다",
                     "\(status.linkTarget) — 그대로 두었습니다. 앱은 번들 것을 씁니다.",
                     .dtWarning)

        case "broken":
            // ⚠️ 끊어진 링크는 "남의 것" 이 아니라 고쳐야 할 것이다.
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { status.linkTerminal() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5))
                        Text("터미널 연결 고치기").font(.system(size: 11.5))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Hover(radius: 5))
                Text("\(status.linkPath) 가 끊어져 있습니다.")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }

        case "occupied":
            linkNote("exclamationmark.triangle", "이미 파일이 있습니다",
                     "\(status.linkPath) — 심볼릭 링크가 아니라 손대지 않았습니다.",
                     .dtWarning)

        default:
            EmptyView()   // ⚠️ 모르면 아무 말도 하지 않는다.
        }
        }
    }

    private func linkNote(_ icon: String, _ title: String,
                          _ detail: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
                Text(title).font(.system(size: 11))
            }
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !status.linkOnPath {
                // ⚠️ 연결해도 PATH 에 없으면 소용이 없다. 감추지 않는다.
                Text("PATH 에 없습니다 — ~/.zshrc 에 추가해야 터미널이 찾습니다.")
                    .font(.system(size: 9)).foregroundStyle(Color.dtWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// CLI 자체가 없다. 셋업 버튼을 줘도 실행할 것이 없으므로 설치 방법을 준다.
    private var missing: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("devtrail 명령을 찾을 수 없습니다")
                .font(.system(size: 12, weight: .medium))
            // ⚠️ 앱 안에 CLI 가 실려 나가므로(M4-3), 번들로 실행 중인데
            //    CLI 가 없다면 그건 **번들이 손상된** 것이다. 그때
            //    "curl | bash 로 설치하세요" 는 거짓말이다 — 설치가 아니라
            //    다시 받아야 한다.
            if CLI.bundled == nil {
                Text("터미널에서 아래를 실행한 뒤 이 창을 새로고침하세요.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.installCommand)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10.5))
                        Text("명령 복사").font(.system(size: 11.5))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Hover(radius: 5))
            } else {
                Text("앱 안에 함께 실린 CLI 를 찾지 못했습니다 — 번들이 손상된 것 같습니다. DMG 를 다시 받아 설치하세요.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("찾아본 곳: \(CLI.binary)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    private static let installCommand =
        "curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash"

    private var healthColor: Color {
        switch status.health {
        case .ok: return .dtSuccess
        case .warn: return .dtWarning
        case .bad: return .dtDanger
        case .unknown: return .secondary
        }
    }
}

/// 마우스를 올리면 강조되는 버튼 스타일.
private struct Hover: ButtonStyle {
    var radius: CGFloat = 6
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
