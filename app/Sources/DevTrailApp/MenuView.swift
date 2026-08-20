import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if status.cliMissing {
                Divider().padding(.vertical, 8)
                missing
            } else if showSettings {
                settingsBody
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
                iconButton("arrow.clockwise", help: "새로고침") { status.refresh() }
            }
        }
    }

    // MARK: - 홈

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            stats
            Divider().padding(.vertical, 8)
            toolbar
            Divider().padding(.vertical, 8)
            backfillRow
            Divider().padding(.vertical, 8)
            openRow
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
                // 서버는 끝나지 않는다. run()으로 부르면 busy에 갇혀 패널이 잠긴다.
                textRow(status.dashboardRunning ? "웹 대시보드 다시 열기" : "웹 대시보드 열기",
                        "safari") { status.openDashboard() }
                if status.dashboardRunning {
                    textRow("웹 대시보드 종료", "stop.circle") { status.stopDashboard() }
                }
            }

            Divider().padding(.vertical, 7)
            HStack {
                Text(status.vaultLabel)
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                Button("종료") {
                    status.stopDashboard()
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
                    .foregroundStyle(.orange)
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

    private var missing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("devtrail 명령을 찾을 수 없습니다")
                .font(.system(size: 12, weight: .medium))
            Text("설치 후 다시 열어주세요.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(CLI.binary)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    private var healthColor: Color {
        switch status.health {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
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
