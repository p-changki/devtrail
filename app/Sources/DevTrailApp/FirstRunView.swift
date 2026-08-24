import AppKit
import SwiftUI

/// 첫 실행 전용 화면.
///
/// 메뉴바 패널은 매일 쓰는 작은 도구를 빠르게 여는 데 맞고, 처음 볼트에
/// 변경을 적용하는 일은 맥락·선택·확인이 한 화면에 보여야 한다. 이 뷰는
/// Onboarding 모델과 CLI 경로는 그대로 재사용하고, 정보 구조만 분리한다.
struct FirstRunView: View {
    @ObservedObject var status: Status
    let onClose: () -> Void

    @StateObject private var onboard = Onboarding()
    var body: some View {
        Group {
            switch onboard.phase {
            case .picking: picking
            case .preview(let text): preview(text)
            case .applying: applying
            case .done(let text, let pluginsInstalled): done(text, pluginsInstalled: pluginsInstalled)
            case .failed(let text): failed(text)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear { onboard.load() }
    }

    private var picking: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            title("시작할 준비를 합니다", detail: "추천 설정을 확인한 뒤에만 볼트에 적용합니다.")

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("1", "볼트 선택", "DevTrail을 적용할 Obsidian 볼트입니다.")
                if onboard.candidates.isEmpty {
                    emptyVault
                } else {
                    Picker("", selection: $onboard.selected) {
                        ForEach(onboard.candidates) { candidate in
                            Text(candidate.label).tag(candidate.path)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(onboard.selected)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("다른 폴더 선택…") { onboard.chooseVault() }
                        .buttonStyle(.link)
                }
            }
            .padding(16)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("2", "언어", "템플릿과 안내에 사용할 언어입니다.")
                Picker("언어", selection: $onboard.lang) {
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(16)
            .background(cardBackground)

            safetySummary

            Button(action: { onboard.preview() }) {
                Label("권장 설정 확인", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(onboard.selected.isEmpty)

            setupOptions
        }
        }
        .frame(maxHeight: 560)
    }

    private var emptyVault: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Obsidian 볼트를 찾지 못했습니다", systemImage: "folder.badge.questionmark")
                .font(.system(size: 13, weight: .medium))
            Text("Finder에서 볼트를 고르거나, Obsidian에서 볼트를 한 번 연 뒤 다시 시도하세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Finder에서 볼트 선택…") { onboard.chooseVault() }
                .buttonStyle(.bordered)
        }
    }

    private func preview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            title("이렇게 준비합니다", detail: onboard.modeLabel.isEmpty ? "적용 전 최종 확인 단계입니다." : onboard.modeLabel)

            VStack(alignment: .leading, spacing: 10) {
                Label("기존 노트는 이동하지 않습니다", systemImage: "checkmark.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dtSuccess)
                Text("아래는 실제 적용 전에 계산한 변경 목록입니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 190)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 7) {
                Button(action: { onboard.apply(installPlugins: true) }) {
                    Label("만들고 Obsidian까지 준비", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("플러그인 설치 후 템플릿·단축키·DevTrail 대시보드까지 연결합니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("플러그인 없이 만들기") { onboard.apply(installPlugins: false) }
                    .buttonStyle(.link)
            }

            HStack {
                Button("뒤로") { onboard.phase = .picking }
                    .buttonStyle(.bordered)
                Spacer()
                Text("적용 뒤에도 되돌릴 수 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var applying: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("볼트를 준비하는 중…").font(.system(size: 16, weight: .medium))
            Text("완료될 때까지 이 창을 열어두세요.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(height: 300)
    }

    private func done(_ text: String, pluginsInstalled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            title(pluginsInstalled ? "준비를 마쳤습니다" : "볼트를 만들었습니다",
                  detail: pluginsInstalled ? "볼트와 권장 플러그인이 준비됐습니다." : "플러그인은 나중에 메뉴바에서 설치할 수 있습니다.")
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .padding(12)
            .background(cardBackground)
            Button("메뉴바에서 계속") {
                status.refresh()
                status.refreshSnapshot()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func failed(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("준비하지 못했습니다", detail: "아직 변경이 끝나지 않았습니다. 내용을 확인하고 다시 시도하세요.")
            ScrollView {
                Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            .frame(height: 180).padding(12).background(cardBackground)
            HStack {
                Button("다시 고르기") { onboard.phase = .picking }.buttonStyle(.bordered)
                Spacer()
                Button("창 닫기", action: onClose).buttonStyle(.bordered)
            }
        }
    }

    private var safetySummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").foregroundStyle(Color.dtSuccess)
            VStack(alignment: .leading, spacing: 3) {
                Text("안전하게 시작합니다").font(.system(size: 13, weight: .medium))
                Text("기존 노트는 이동하지 않으며, 적용한 변경은 되돌릴 수 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Color.dtSuccess.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var setupOptions: some View {
        DisclosureGroup("선택 설정 — 나중에 연결해도 됩니다") {
            VStack(alignment: .leading, spacing: 13) {
                Picker("설치 방식", selection: $onboard.installMode) {
                    Text("자동 추천").tag("auto")
                    Text("기존 볼트에 얹기").tag("existing")
                    Text("새로 시작").tag("new")
                    Text("분리 설치").tag("isolated")
                }
                Text("기존 노트가 많은 볼트는 ‘기존 볼트에 얹기’를 권장합니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                TextField("DevTrail 루트 폴더 (비우면 볼트 최상위)", text: $onboard.root)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("설치할 기능").font(.system(size: 12, weight: .medium))
                    moduleToggle("devlog", "개발일지 + GitHub 활동", required: true)
                    moduleToggle("review", "주간 · 월간 리뷰")
                    moduleToggle("project", "프로젝트 구조 + docs")
                    moduleToggle("pkm", "자료실 · 카드노트 · MOC")
                    moduleToggle("learn", "학습 시스템")
                    moduleToggle("personal", "개인 기록")
                }

                Divider()
                automationToggle("GitHub 활동을 개발일지에 연결", isOn: $onboard.includeGitHub,
                                 detail: "GitHub를 쓰지 않아도 DevTrail의 기본 기능은 모두 사용할 수 있습니다.") {
                    setupTextField("GitHub 사용자명", hint: "프로필 URL이 아닌 아이디입니다. 예: octocat", text: $onboard.githubUser)
                }
                automationToggle("AI로 PR을 쉬운 말로 요약", isOn: $onboard.includeAI,
                                 detail: "AI 명령어가 이 Mac에 설치되어 있을 때만 켜세요.") {
                    Picker("사용할 AI", selection: $onboard.aiProvider) {
                        Text("Claude").tag("claude")
                        Text("Codex").tag("codex")
                        Text("Gemini").tag("gemini")
                    }
                }
                automationToggle("프로젝트 docs를 볼트로 가져오기", isOn: $onboard.includeProjectSync,
                                 detail: "프로젝트 문서를 Obsidian에서 함께 보고 싶을 때만 켜세요.") {
                    setupTextField("레포가 모인 폴더", hint: "절대 경로입니다. 예: ~/Desktop", text: $onboard.sourceRoot)
                    setupTextField("가져올 레포", hint: "URL이 아닌 폴더 이름입니다. 예: my-app,my-api", text: $onboard.syncRepos)
                }
                automationToggle("PR 요약 섹션 만들기", isOn: $onboard.includePRSummaries,
                                 detail: "선택한 레포의 PR 요약을 개발일지에 남깁니다.") {
                    setupTextField("PR 요약 레포", hint: "레포 이름을 쉼표로 구분합니다. 예: my-app", text: $onboard.projects)
                }
            }
            .padding(.top, 10)
        }
        .font(.system(size: 12))
    }

    private func moduleToggle(_ id: String, _ label: String, required: Bool = false) -> some View {
        Toggle(label, isOn: Binding(
            get: { onboard.modules.contains(id) },
            set: { enabled in
                if enabled { onboard.modules.insert(id) }
                else if !required { onboard.modules.remove(id) }
            }
        ))
        .disabled(required)
        .font(.system(size: 11))
    }

    private func setupTextField(_ label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: text).textFieldStyle(.roundedBorder)
            Text(hint).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private func automationToggle<Content: View>(_ title: String, isOn: Binding<Bool>, detail: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: isOn).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            if isOn.wrappedValue { content().padding(.leading, 4) }
        }
    }

    private func title(_ headline: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(Color.dtSuccess)
                Text("DevTrail").font(.system(size: 14, weight: .semibold))
            }
            Text(headline).font(.system(size: 24, weight: .bold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ number: String, _ headline: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dtSuccess)
                .frame(width: 20, height: 20)
                .background(Color.dtSuccess.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor))
    }
}
