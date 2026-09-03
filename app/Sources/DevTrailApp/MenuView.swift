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
    private enum CaptureMode { case youtube, web }
    private enum DevlogComposerMode { case create, link }

    @ObservedObject var status: Status
    @State private var showSettings = false

    /// 한국어 설명·버튼을 줄이지 않고 읽을 수 있는 메뉴바 패널 폭.
    private let panelWidth: CGFloat = 342

    @State private var captureURL = ""
    @State private var capturePurpose = ""
    @State private var captureWhy = ""
    @State private var captureProjects: Set<String> = []
    @State private var captureMode: CaptureMode = .youtube
    @State private var showCaptureComposer = false
    @State private var showDevlogComposer = false
    @State private var devlogComposerMode: DevlogComposerMode = .create
    @State private var pickedProjects: Set<String> = []
    @State private var showBackfillComposer = false
    @StateObject private var onboard = Onboarding()

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
        .padding(14)
        .frame(width: panelWidth)
        // 성공(중복 포함)만 다음 입력을 위해 비운다. 실패한 URL은 그대로 남겨
        // 사용자가 오타를 고치거나 다시 시도할 수 있게 한다. 자막이 없어 AI가
        // 건너뛴 경우에도 학습 목적을 지우면 "전달되지 않았다"고 보이므로 보존한다.
        .onChange(of: status.captureCompletedID) { _, _ in
            if status.captureWarning == nil {
                captureURL = ""
                capturePurpose = ""
            }
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(healthColor).frame(width: 8, height: 8)
            Text(showSettings ? "설정" : "DevTrail")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if let b = status.busy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(b).font(.system(size: 11.5)).foregroundStyle(.secondary)
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
            todayCard
            Divider().padding(.vertical, 8)
            devlogToolbar
            Divider().padding(.vertical, 8)
            aiActions
            Divider().padding(.vertical, 8)
            if showDevlogComposer {
                devlogComposer
                Divider().padding(.vertical, 8)
            }
            if showCaptureComposer {
                captureRow
                Divider().padding(.vertical, 8)
            }
            moreActions
        }
    }

    /// 홈의 첫 화면은 수치 목록이 아니라 "지금 무엇을 하면 되는가"에 답한다.
    private var todayCard: some View {
        let hasToday = status.snapshot?.today?.devlogExists ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Label(status.headline, systemImage: hasToday ? "checkmark.circle.fill" : "calendar.badge.plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hasToday ? Color.dtSuccess : Color.primary)
            Text(status.detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Button(hasToday ? "오늘 개발일지 열기" : "오늘 개발일지 만들기") {
                if hasToday { status.openInObsidian(path: status.devlogFile) }
                else { openDevlogComposer() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(status.busy != nil)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dtSuccess.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Claude를 실제로 호출하는 두 가지 기능을 이름 그대로 앞에 둔다.
    /// 스킬 설치 목록을 그대로 노출하면 "무엇을 누르면 어떤 결과가 생기는지"
    /// 알 수 없으므로, 사용자가 바로 끝낼 수 있는 작업만 보인다.
    private var aiActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dtSuccess)
                Text("AI 작업")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(status.toggles["ai.summary_enabled"] == true ? "Claude 사용" : "AI 요약 꺼짐")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                tool("play.rectangle", "유튜브 정리") { openCapture(.youtube) }
                tool("link.badge.plus", "웹 링크 저장") { openCapture(.web) }
            }
        }
    }

    private func openCapture(_ mode: CaptureMode) {
        captureMode = mode
        captureURL = ""
        capturePurpose = ""
        captureWhy = ""
        captureProjects = []
        // ⚠️ 링크에도 프로젝트를 붙일 수 있어야 "지금 하는 일에 필요한 링크"를
        //    나중에 꺼낼 수 있다. 목록은 열 때 한 번 읽는다.
        if mode == .web { status.loadProjects() }
        showCaptureComposer = true
    }

    /// 메뉴바에서도 실제 DevTrail 명령을 바로 실행한다. 키를 외우지 못해도
    /// 같은 결과에 도달하고, 키를 쓰는 사람은 버튼의 키캡으로 다시 확인한다.
    ///
    /// Templater 개별 명령은 Obsidian 기본 URI가 실행할 수 없다. 이전에는
    /// 존재하지 않는 `obsidian://command` URI를 열어 오류만 냈으므로, 여기에는
    /// CLI가 끝까지 실행할 수 있는 세 가지 개발일지 작업만 둔다.
    private var devlogToolbar: some View {
        let hasToday = status.snapshot?.today?.devlogExists ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dtSuccess)
                Text("개발일지 도구")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("DevTrail 단축키")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                shortcutTool(hasToday ? "doc.text" : "doc.badge.plus",
                             hasToday ? "일지 열기" : "일지 만들기",
                             nil) {
                    if hasToday { status.openInObsidian(path: status.devlogFile) }
                    else { openDevlogComposer() }
                }
                if hasToday {
                    shortcutTool("folder.badge.plus", "프로젝트 붙이기", nil) {
                        openDevlogComposer(.link)
                    }
                }
                shortcutTool("arrow.down.circle", "오늘 이슈/PR", status.hotkey(for: activityCommand)) {
                    status.fetchTodayActivity()
                }
                shortcutTool("sparkles", "PR 요약", status.hotkey(for: summaryCommand)) {
                    status.summarizePullRequests()
                }
                shortcutTool("calendar.badge.clock", "백필", status.hotkey(for: backfillCommand)) {
                    status.prepareBackfill()
                    showBackfillComposer = true
                }
            }
            activityFeedback
            summaryFeedback
            if showBackfillComposer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("지난 날짜의 이슈·PR과 PR 요약을 채웁니다. 날짜를 확인한 뒤 실행하세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    backfillRow
                    backfillFeedback
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dtWarning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private let activityCommand = "obsidian-shellcommands:shell-command-devtrail-activity"
    private let summaryCommand = "obsidian-shellcommands:shell-command-devtrail-summary"
    private let backfillCommand = "obsidian-shellcommands:shell-command-devtrail-backfill"
    /// PR 요약은 GitHub 인증과 Claude 실행을 거친다. 누른 뒤 조용하면
    /// "안 됐나? 기다리면 되나?"를 알 수 없으므로 결과를 AI 작업 안에 남긴다.
    @ViewBuilder
    private var summaryFeedback: some View {
        if status.summaryBusy {
            Label("PR AI 요약 중… 머지된 PR을 확인하고 Claude가 개발일지에 정리하고 있습니다.",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.dtSuccess)
                .padding(.top, 2)
        } else if let error = status.summaryError {
            VStack(alignment: .leading, spacing: 4) {
                Label("PR AI 요약을 완료하지 못했습니다", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtDanger)
                Text(error)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("GitHub 인증이 필요하면 설정에서 다시 연결한 뒤 재시도하세요.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtDanger.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let result = status.summaryResult {
            VStack(alignment: .leading, spacing: 4) {
                Label("PR AI 요약을 완료했습니다", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtSuccess)
                Text(result).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtSuccess.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var activityFeedback: some View {
        if status.activityBusy {
            Label("오늘 GitHub 이슈/PR을 개발일지에 넣는 중…", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.dtSuccess)
                .padding(.top, 2)
        } else if let error = status.activityError {
            Label("오늘 이슈/PR을 가져오지 못했습니다: \(error)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Color.dtDanger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let result = status.activityResult {
            Label("오늘 이슈/PR을 반영했습니다 · \(result)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(Color.dtSuccess)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var backfillFeedback: some View {
        if status.backfillBusy {
            Label("백필 실행 중…", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.dtSuccess)
        } else if let error = status.backfillError {
            Label("백필을 완료하지 못했습니다: \(error)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Color.dtDanger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let result = status.backfillResult {
            Label("백필 완료 · \(result)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(Color.dtSuccess)
                .lineLimit(2)
        }
    }

    private var moreActions: some View {
        DisclosureGroup("더보기") {
            VStack(alignment: .leading, spacing: 8) {
                compactVaultState
                Divider()
                textRow("활동 가져오기", "arrow.down.circle") {
                    status.fetchTodayActivity()
                }
                textRow("이번 주 리뷰", "calendar") {
                    status.run("주간리뷰", ["weekly"])
                }
                textRow("프로젝트 문서 동기화", "folder.badge.gearshape") {
                    status.run("동기화", ["sync"])
                }
                backfillRow
                openRow
            }
            .padding(.top, 8)
        }
        .font(.system(size: 13))
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let s = status.snapshot {
                if !s.vaultAvailable {
                    Label("볼트를 찾지 못했습니다", systemImage: "folder.badge.questionmark")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text("상태를 읽는 중…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("볼트 상태")
    }

    /// 부가 지표는 홈의 결정을 방해하지 않도록 더보기 안에 둔다.
    private var compactVaultState: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let s = status.snapshot, s.vaultAvailable {
                stateLine("프로젝트", s.activeProjects.map { "활성 \($0)개" } ?? "확인 불가",
                          detail: s.nextActions.first.map { "\($0.project) · \($0.text)" } ?? "")
                stateLine("Inbox", s.inboxCount.map { $0 == 0 ? "비어 있음" : "\($0)개" } ?? "확인 불가",
                          detail: (s.inboxCount ?? 0) > 0 ? (s.inboxPreview.first?.title ?? "") : "")
                stateLine("상태", "Command Center \(s.commandCenterLine)", detail: "")
            } else if let error = status.snapshotError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text("볼트 상태를 읽는 중…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func stateLine(_ label: String, _ value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 102, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 12.5))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). \(detail)")
    }

    // MARK: - 오늘 작업할 프로젝트
    //
    // ⚠️ 고르지 않고도 만들 수 있어야 한다. 프로젝트를 강제하면 급할 때 일지를
    //    아예 안 쓰게 되고, 그러면 기록 자체가 사라진다.
    private func openDevlogComposer(_ mode: DevlogComposerMode = .create) {
        devlogComposerMode = mode
        pickedProjects = []
        status.loadProjects()
        showDevlogComposer = true
    }

    private var devlogComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus").font(.system(size: 11.5))
                Text("오늘 작업할 프로젝트")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pickedProjects.count)개 선택")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            if status.projectsLoading {
                Text("불러오는 중…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let e = status.projectsError {
                // ⚠️ 빈 목록으로 얼버무리지 않는다. 무엇이 깨졌는지 말한다.
                Text(e).font(.system(size: 11)).foregroundStyle(Color.dtDanger)
                    .textSelection(.enabled)
            } else if status.projects.isEmpty {
                Text("프로젝트가 없습니다. 폴더를 만들거나 devtrail project add 로 등록하세요.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(status.projects) { p in
                            Toggle(isOn: Binding(
                                get: { pickedProjects.contains(p.key) },
                                set: { on in
                                    if on { pickedProjects.insert(p.key) }
                                    else { pickedProjects.remove(p.key) }
                                }
                            )) {
                                HStack(spacing: 4) {
                                    Text(p.key).font(.system(size: 12))
                                    if devlogComposerMode == .link && p.linked {
                                        Text("붙음")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            // 이미 붙은 것은 고를 필요가 없다 — 골라도 결과가
                            // 같아서 "안 먹었다" 로 읽힌다.
                            .disabled(devlogComposerMode == .link && p.linked)
                        }
                    }
                }
                // ⚠️ maxHeight 만 주면 안 된다. ScrollView 는 고유 높이가 없어서
                //    내용에 맞춰 크기를 정하는 팝오버 안에서 **0 으로 접힌다** —
                //    목록이 통째로 안 보이고, 사용자는 아무것도 못 고른 채
                //    "0개 선택" 으로 일지를 만들게 된다. 실제로 그랬다.
                .frame(height: min(CGFloat(status.projects.count) * 22 + 6, 150))
            }
            HStack(spacing: 6) {
                Button(devlogComposerMode == .create ? "만들기" : "붙이기") {
                    if devlogComposerMode == .create {
                        status.createTodayDevlog(projects: pickedProjects.sorted())
                    } else {
                        status.linkProjects(pickedProjects.sorted())
                    }
                    showDevlogComposer = false
                }
                .font(.system(size: 12.5, weight: .medium))
                .buttonStyle(.borderedProminent)
                .disabled(status.busy != nil
                          || (devlogComposerMode == .link && pickedProjects.isEmpty))
                // ⚠️ 만들 때는 고르지 않고도 나갈 수 있어야 한다. 강제하면 급할 때
                //    일지를 아예 안 쓰고, 그러면 기록 자체가 사라진다.
                Button(devlogComposerMode == .create ? "건너뛰기" : "닫기") {
                    if devlogComposerMode == .create { status.createTodayDevlog() }
                    showDevlogComposer = false
                }
                .font(.system(size: 12.5))
                .disabled(status.busy != nil)
                Spacer()
            }
            Text(devlogComposerMode == .create
                 ? "고른 프로젝트는 일지의 projects 와 project/<키> 태그로 남습니다."
                 : "이미 붙은 프로젝트는 그대로 두고 고른 것만 더합니다.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
    }

    // MARK: - 유튜브 정리 / 웹 링크 저장
    //
    // ⚠️ Obsidian 이 꺼져 있어도 된다. 노트를 만드는 것은 CLI 이고,
    //    저널에 남아 undo 로 사라진다 (ADR 0003).
    private var captureRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: captureMode == .youtube ? "play.rectangle" : "link.badge.plus")
                    .font(.system(size: 11.5))
                Text(captureMode == .youtube ? "유튜브 정리" : "웹 링크 저장")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("클립보드") {
                    // ⚠️ 자동으로 읽지 않는다. 누를 때만 읽는다.
                    captureURL = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("클립보드의 링크를 붙여넣습니다")
            }
            HStack(spacing: 6) {
                TextField(captureMode == .youtube ? "YouTube 링크 붙여넣기" : "웹 링크 붙여넣기", text: $captureURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .disabled(status.captureBusy)
                    .accessibilityLabel("저장할 링크")
                Button(captureButtonTitle) {
                    if captureMode == .youtube {
                        status.captureYouTube(captureURL, purpose: capturePurpose, apply: true)
                    } else {
                        status.captureWeb(captureURL, why: captureWhy,
                                          projects: captureProjects.sorted(), apply: true)
                    }
                }
                .font(.system(size: 12.5, weight: .medium))
                .controlSize(.regular)
                // ⚠️ 두 번 누르면 노트가 두 개 생긴다.
                .disabled(status.captureBusy || captureURL.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(captureHelp)
            }
            if captureMode == .youtube {
                TextField("이 영상에서 얻고 싶은 것 (선택)", text: $capturePurpose)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(status.captureBusy)
                    .accessibilityLabel("유튜브 영상 학습 목적")
                    .help("예: 피그마 포트폴리오를 검토할 때 쓸 디자인 판단 기준")
            } else {
                captureContextRow
            }
            Text(captureHint)
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            captureFeedback
        }
    }

    /// 링크의 맥락 — 왜 저장했는지와 어떤 프로젝트에 쓸 것인지.
    ///
    /// ⚠️ 저장 이유는 사람만 아는 정보다. 분류는 규칙이 대신 해줄 수 있지만
    ///    "왜 담았나" 는 대신할 수 없고, 없으면 몇 주 뒤 표를 봐도 어떤
    ///    사이트였는지 본인도 모른다. 그래서 저장 순간에 한 줄만 받는다.
    @ViewBuilder
    private var captureContextRow: some View {
        TextField("왜 저장하나요 (선택)", text: $captureWhy)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .disabled(status.captureBusy)
            .accessibilityLabel("링크를 저장하는 이유")
            .help("예: 랜딩 히어로 카피 다시 볼 때")
        if status.projectsLoading {
            Text("프로젝트 불러오는 중…").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if let e = status.projectsError {
            // ⚠️ 빈 목록으로 얼버무리지 않는다. 무엇이 깨졌는지 말한다.
            Text(e).font(.system(size: 11)).foregroundStyle(Color.dtDanger)
                .textSelection(.enabled)
        } else if !status.projects.isEmpty {
            HStack(spacing: 6) {
                Text("프로젝트").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(captureProjects.count)개 선택")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(status.projects) { p in
                        Toggle(isOn: Binding(
                            get: { captureProjects.contains(p.key) },
                            set: { on in
                                if on { captureProjects.insert(p.key) }
                                else { captureProjects.remove(p.key) }
                            }
                        )) {
                            Text(p.key).font(.system(size: 12))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            // ⚠️ maxHeight 만 주면 ScrollView 가 팝오버 안에서 0 으로 접힌다.
            //    개발일지 선택창에서 이미 한 번 겪었다.
            .frame(height: min(CGFloat(status.projects.count) * 22 + 6, 120))
        }
    }

    private var captureButtonTitle: String {
        if status.captureBusy {
            return status.captureKind == .youtube ? "AI 정리 중…" : "저장 중…"
        }
        return captureMode == .youtube ? "저장하고 정리" : "링크 저장"
    }
    private var captureHint: String {
        captureMode == .youtube
            ? "목적을 적으면 그 관점으로 판단 기준을 추출합니다. 비워두면 AI가 영상에서 추정합니다."
            : "저장 이유와 프로젝트는 나중에 링크를 찾을 때 쓰는 단서입니다. AI 없이 저장합니다."
    }
    private var captureHelp: String {
        captureMode == .youtube
            ? "AI 요약이 켜져 있으면 Claude가 자막을 분석해 노트를 정리합니다"
            : "제목과 기본 정보를 읽어 자료실에 저장합니다. AI는 사용하지 않습니다"
    }

    /// 실행 중·완료·실패를 서로 다른 문장과 색으로 고정해 둔다. 이전에는
    /// 실패가 빨간 한 줄로 잘려 "아직 실행 중인가"를 판단할 수 없었다.
    @ViewBuilder
    private var captureFeedback: some View {
        if status.captureBusy {
            VStack(alignment: .leading, spacing: 4) {
                Label(status.captureKind == .youtube ? "유튜브 정리 중…" : "링크 저장 중…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtSuccess)
                Text(status.captureKind == .youtube
                     ? "링크를 저장한 뒤 Claude가 자막을 분석해 노트를 채우고 있습니다."
                     : "제목과 기본 정보를 읽어 자료실 노트를 만들고 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtSuccess.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let error = status.captureError {
            VStack(alignment: .leading, spacing: 4) {
                Label(status.captureKind == .youtube ? "유튜브 정리에 실패했습니다" : "링크를 저장하지 못했습니다", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtDanger)
                Text(error)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("아래 실행 로그에서 전체 내용을 확인할 수 있습니다.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtDanger.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let warning = status.captureWarning {
            VStack(alignment: .leading, spacing: 4) {
                Label("링크는 저장했고, AI 요약만 건너뛰었습니다", systemImage: "checkmark.circle.badge.exclamationmark")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtWarning)
                Text(warning)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let job = status.captureUndoJob {
                    Text("되돌리기: devtrail undo \(job) --apply")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtWarning.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let result = status.captureResult {
            VStack(alignment: .leading, spacing: 4) {
                Label(status.captureKind == .youtube ? "유튜브 정리를 완료했습니다" : "링크를 저장했습니다", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dtSuccess)
                Text(result).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                if let job = status.captureUndoJob {
                    Text("되돌리기: devtrail undo \(job) --apply")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dtSuccess.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            tool("arrow.down.circle", "활동")   { status.fetchTodayActivity() }
            tool("sparkles", "요약")            { status.run("요약", ["summary"]) }
            tool("calendar", "주간")            { status.run("주간리뷰", ["weekly"]) }
            tool("folder", "docs")              { status.run("동기화", ["sync"]) }
        }
    }

    private var backfillRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 15)
            TextField("YYYY-MM-DD", text: $status.backfillDate)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
            Button("채우기") { status.runBackfill() }
                .font(.system(size: 12.5, weight: .medium))
                .controlSize(.regular)
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
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .padding(.top, 8)
                Text("설정은 셋업을 마친 뒤에 쓸 수 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
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

            Divider().padding(.vertical, 10)
            HStack {
                Text(status.needsSetup ? "" : status.vaultLabel)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
                    .buttonStyle(.plain).font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 부품

    private func group<C: View>(_ title: String,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 12).padding(.bottom, 3)
            content()
        }
    }

    private func tool(_ icon: String, _ label: String,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 11.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 7))
        .disabled(status.busy != nil)
    }

    private func shortcutTool(_ icon: String, _ label: String, _ key: String? = nil,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15))
                Text(label).font(.system(size: 11.5, weight: .medium))
                if let key {
                    Text(key).font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 7))
        .disabled(status.busy != nil)
        .help(key.map { "Obsidian에서 \($0): \(label)" } ?? label)
    }

    private func linkButton(_ icon: String, _ label: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(Hover(radius: 6))
    }

    private func textRow(_ title: String, _ icon: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 15)
                Text(title).font(.system(size: 13))
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
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
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
            Text(title).font(.system(size: 13))
                .foregroundStyle(unknown ? Color.secondary : Color.primary)
            Spacer(minLength: 8)
            if unknown {
                Text("값 불명")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dtWarning)
                    .help("설정을 읽지 못했습니다 — devtrail init 또는 doctor 를 확인하세요")
            } else {
                Toggle("", isOn: isOn)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(status.busy != nil)
            }
        }
        .padding(.vertical, 3)
    }

    private var output: some View {
        ScrollView {
            Text(status.lastOutput)
                .font(.system(size: 11, design: .monospaced))
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
            switch onboard.phase {
            case .picking:   onboardPicking
            case .preview(let text): onboardPreview(text)
            case .applying:  onboardApplying
            case .done(let text, let pluginsInstalled):
                onboardDone(text, pluginsInstalled: pluginsInstalled)
            case .failed(let text):  onboardFailed(text)
            }
            terminalLink
        }
        .onAppear { onboard.load() }
    }

    // MARK: - 온보딩 (ADR 0006 M4-4c)
    //
    // ⚠️ 추천값(언어·가장 큰 볼트)만 먼저 채운다. 실제 설치 방식과 기본값은
    //    CLI 가 정한다 — 앱이 기본값을 갖기 시작하면 대화형과 갈린다.

    private var onboardPicking: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("시작할 준비를 합니다")
                .font(.system(size: 12, weight: .medium))
            Text("추천 설정으로 볼트와 노트 템플릿을 준비합니다. 바꾸고 싶을 때만 아래에서 고르세요.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            group("언어") {
                Picker("", selection: $onboard.lang) {
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            group("볼트") {
                if onboard.candidates.isEmpty {
                    // ⚠️ 등록된 Obsidian 볼트가 없어도 터미널로 밀어내지 않는다.
                    Text("Obsidian 볼트를 찾지 못했습니다.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text("Finder 에서 사용할 볼트를 고르거나, Obsidian 에서 볼트를 한 번 연 뒤 새로고침하세요.")
                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    textRow("Finder에서 볼트 선택", "folder") { onboard.chooseVault() }
                } else {
                    Picker("", selection: $onboard.selected) {
                        ForEach(onboard.candidates) { c in
                            Text(c.label).tag(c.path)
                        }
                    }
                    .labelsHidden()
                    Text(onboard.selected)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    textRow("다른 폴더 선택", "folder") { onboard.chooseVault() }
                }
            }

            if !onboard.candidates.isEmpty {
                Button(action: { onboard.preview() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye").font(.system(size: 11))
                        Text("권장 설정 확인").font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Hover(radius: 6))
                // ⚠️ 누르면 바뀌는 것이 아니라는 사실을 먼저 말한다.
                Text("아직 아무것도 바꾸지 않습니다.")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }

            advancedSetup
        }
    }

    private func onboardPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("권장 설정입니다")
                .font(.system(size: 12, weight: .medium))
            if !onboard.modeLabel.isEmpty {
                Text(onboard.modeLabel)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("기존 노트는 옮기지 않습니다. 변경 내용은 아래에서 확인할 수 있습니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)

            Button(action: { onboard.apply(installPlugins: true) }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 11))
                    Text("만들고 권장 플러그인 설치").font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Hover(radius: 6))
            // ⚠️ 되돌릴 수 있다는 사실과 네트워크 동의를 누르기 전에 말한다.
            Text("GitHub에서 고정 버전 플러그인을 받아 볼트에 넣습니다. 되돌릴 수 있습니다.")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            textRow("플러그인 없이 만들기", "arrow.right") {
                onboard.apply(installPlugins: false)
            }
            textRow("다시 고르기", "chevron.backward") { onboard.phase = .picking }
        }
    }

    private var onboardApplying: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("만드는 중…").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    private func onboardDone(_ text: String, pluginsInstalled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(Color.dtSuccess)
                Text(pluginsInstalled ? "준비를 마쳤습니다" : "만들었습니다")
                    .font(.system(size: 12, weight: .medium))
            }
            if pluginsInstalled {
                Text("볼트와 권장 플러그인을 준비했습니다. Obsidian을 열어 시작하세요.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("플러그인은 아직 받지 않았습니다. 필요하면 아래에서 따로 설치할 수 있습니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                textRow("플러그인 설치", "square.and.arrow.down") {
                    status.run("플러그인", ["plugins", "install"])
                }
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            textRow("새로고침", "arrow.clockwise") { status.refresh() }
        }
    }

    private func onboardFailed(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Color.dtDanger)
                Text("만들지 못했습니다").font(.system(size: 12, weight: .medium))
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            textRow("다시 고르기", "chevron.backward") { onboard.phase = .picking }
            advancedSetup
        }
    }

    /// ⚠️ 터미널 대화를 **없애지 않는다.** 앱이 못 하는 것(기존 폴더 채택 ·
    ///    GitHub · 동기화 · AI)을 정하려면 그 길이 필요하다. 다만 기본이
    ///    아니라 **고급**으로 내린다.
    private var advancedSetup: some View {
        VStack(alignment: .leading, spacing: 2) {
            textRow("터미널로 설정 (고급)", "terminal") { status.startSetup() }
            Text("GitHub · 동기화 · AI 까지 한 번에 정합니다.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)

            // ⚠️ **항상 통하는 길을 하나 둔다** (2026-08-24 실물 QA).
            //
            //    Terminal 은 명령을 타이핑해서 넣는다. 그 순간 셸 초기화가
            //    입력을 기다리고 있으면 글자를 먹는다 — oh-my-zsh 의
            //    "Would you like to update? [Y/n]" 가 경로 첫 글자를 삼켜
            //    터미널이 열리기만 하고 아무것도 안 됐다.
            //
            //    사용자의 .zshrc 를 우리가 통제할 수 없다. 근본은 못 고치므로
            //    붙여넣을 명령을 **늘** 함께 보여준다.
            Text("터미널이 열리지 않으면 아래를 복사해 붙여넣으세요.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.top, 3)
                .fixedSize(horizontal: false, vertical: true)
            Text(status.setupCommand)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(status.setupCommand, forType: .string)
                status.lastOutput = "명령을 복사했습니다. 터미널에 붙여넣으세요."
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc").font(.system(size: 9.5))
                    Text("명령 복사").font(.system(size: 10.5))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(Hover(radius: 5))
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
