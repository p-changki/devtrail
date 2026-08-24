import AppKit
import SwiftUI

/// 앱 안에서 끝내는 간단 셋업 (ADR 0006 M4-4c).
///
/// ⚠️ 왜 있나
///
///   DMG 로 받은 비개발자에게 터미널 대화 **13단계**를 시키는 것이 지금 남은
///   가장 큰 벽이다. 여기서는 **언어와 볼트 두 가지만** 받는다.
///
/// ⚠️ **판정도 적용도 여기서 하지 않는다.**
///
///   - 볼트 후보는 `devtrail setup env --json` 이 준다.
///   - 스펙 조립과 기본값은 `devtrail setup quick` 이 한다.
///   - 이 화면은 사용자가 고른 값만 넘기고 결과를 그릴 뿐이다.
///
///   같은 판정을 CLI 와 앱에 두 벌 두면 반드시 어긋나고, 어긋난 쪽이 화면이면
///   사용자가 먼저 본다 — 2026-08-22 실물 QA 의 결함 9건 중 4건이 그 유형이었다.
@MainActor
final class Onboarding: ObservableObject {

    struct Candidate: Identifiable, Hashable {
        let path: String
        let name: String
        let notes: Int
        var id: String { path }

        var label: String {
            notes == 0 ? name : "\(name) · 노트 \(notes)개"
        }
    }

    enum Phase: Equatable {
        case picking          // 언어·볼트를 고르는 중
        case preview(String)  // 무엇이 될지 미리 보여준 상태
        case applying
        case done(String, pluginsInstalled: Bool)
        case failed(String)
    }

    @Published var lang = "ko"
    @Published var candidates: [Candidate] = []
    @Published var selected: String = ""
    @Published var phase: Phase = .picking
    @Published var installMode = "auto"
    @Published var root = ""
    @Published var modules: Set<String> = ["devlog", "review", "project", "pkm", "learn"]
    @Published var includeGitHub = false
    @Published var includeAI = false
    @Published var includeProjectSync = false
    @Published var includePRSummaries = false
    @Published var githubUser = ""
    @Published var aiProvider = "none"
    @Published var sourceRoot = ""
    @Published var syncRepos = ""
    @Published var projects = ""
    /// CLI 가 제안한 설치 방식 (new | existing | isolated). 화면은 표시만 한다.
    @Published var suggestedMode = ""

    /// 자동으로 발견한 볼트가 없을 때도 터미널로 밀어내지 않는다. Finder 에서
    /// 사용자가 고른 폴더를 같은 CLI 경로에 넘긴다.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 사용"
        panel.message = "DevTrail 을 설정할 Obsidian 볼트를 고르세요."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        if !candidates.contains(where: { $0.path == path }) {
            candidates.append(Candidate(path: path,
                                        name: url.lastPathComponent,
                                        notes: 0))
        }
        selected = path
    }

    /// 볼트 후보를 CLI 에서 받아 온다.
    ///
    /// ⚠️ 후보 목록을 앱이 직접 뒤지지 않는다. Obsidian 의 볼트 목록을 읽는
    ///    방법이 두 벌이 되면, 앱과 CLI 가 다른 볼트를 가리키게 된다.
    func load() {
        guard let env = CLI.json(["setup", "env", "--json"]) else {
            candidates = []
            return
        }
        let raw = env["vaults"] as? [[String: Any]] ?? []
        candidates = raw.compactMap { v in
            guard let p = v["path"] as? String, !p.isEmpty else { return nil }
            return Candidate(path: p,
                             name: (v["name"] as? String) ?? p,
                             notes: (v["notes"] as? Int) ?? 0)
        }
        // 후보가 여러 개면 노트가 많은 볼트를 추천한다. 사용자는 언제든 Picker 나
        // Finder 로 바꿀 수 있고, 실제 설치 방식 판단은 계속 CLI 가 한다.
        candidates.sort { $0.notes > $1.notes }
        if selected.isEmpty { selected = candidates.first?.path ?? "" }
    }

    /// 무엇이 될지 먼저 보여준다 — 바꾸지 않는다.
    ///
    /// ⚠️ `setup quick` 은 `--apply` 없이는 아무것도 바꾸지 않는다. 그 성질에
    ///    기대어, 사용자가 확인한 다음에만 적용한다.
    func preview() {
        guard !selected.isEmpty else {
            phase = .failed("볼트를 먼저 고르세요.")
            return
        }
        // 제안된 설치 방식을 함께 읽어 화면에 적는다.
        if let spec = CLI.json(setupArguments(json: true)),
           let v = spec["vault"] as? [String: Any] {
            suggestedMode = (v["mode"] as? String) ?? ""
        }
        let r = CLI.run(setupArguments())
        phase = r.ok ? .preview(r.text) : .failed(r.text)
    }

    /// 실제로 적용한다.
    ///
    /// ⚠️ 되돌릴 수 있는 변경만 여기서 한다 — `setup apply` 가 저널을 열고
    ///    한 번의 셋업을 하나의 되돌림 단위로 만든다.
    func apply(installPlugins: Bool) {
        guard !selected.isEmpty else { return }
        phase = .applying
        let r = CLI.run(setupArguments(apply: true))
        guard r.ok else {
            phase = .failed(r.text)
            return
        }

        // 플러그인은 외부 네트워크에서 코드를 받는다. 버튼 문구와 미리보기에서
        // 사용자가 명시적으로 고른 경우에만 --yes 로 진행한다.
        guard installPlugins else {
            // 플러그인을 받지 않더라도 템플릿 경로·앱 설정은 병합한다.
            // 이것이 빠지면 '셋업 완료' 뒤에도 Obsidian에서 수동 명령을 해야 한다.
            let obsidian = CLI.run(["obsidian"])
            let combined = [r.text, obsidian.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
            phase = .done(combined, pluginsInstalled: false)
            return
        }

        // 사용자가 네트워크 플러그인 설치에 명시 동의한 경로다. 설치가 끝난 뒤
        // Obsidian 설정을 병합해야 Templater 명령·템플릿 폴더가 실제로 연결된다.
        let plugins = CLI.run(["plugins", "install", "--yes"])
        guard plugins.ok else {
            phase = .done([r.text, plugins.text].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                          pluginsInstalled: false)
            return
        }
        let obsidian = CLI.run(["obsidian"])
        let commandCenterInstall = CLI.run(["command-center", "install", "--apply"])
        let commandCenterEnable = commandCenterInstall.ok
            ? CLI.run(["command-center", "enable", "--apply"])
            : nil
        let combined = [r.text, plugins.text, obsidian.text,
                        commandCenterInstall.text, commandCenterEnable?.text ?? "Command Center 설치에 실패했습니다."]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        phase = .done(combined, pluginsInstalled: obsidian.ok && commandCenterEnable?.ok == true)
    }

    /// 사람이 읽을 설치 방식.
    var modeLabel: String {
        switch suggestedMode {
        case "new":      return "새로 시작 — 전체 구조를 만듭니다"
        case "existing": return "기존 볼트에 얹기 — 노트를 움직이지 않습니다"
        case "isolated": return "분리 설치 — 새 하위 트리에만 만듭니다"
        default:         return ""
        }
    }

    var selectedModules: [String] {
        modules.sorted()
    }

    private func setupArguments(apply: Bool = false, json: Bool = false) -> [String] {
        var args = ["setup", "quick", "--vault", selected, "--lang", lang,
                    "--mode", installMode, "--root", root,
                    "--modules", selectedModules.joined(separator: ","),
                    "--github-user", includeGitHub ? githubUser : "",
                    "--ai", includeAI ? aiProvider : "none",
                    "--src-root", includeProjectSync ? sourceRoot : "",
                    "--sync-repos", includeProjectSync ? syncRepos : "",
                    "--projects", includePRSummaries ? projects : ""]
        if json { args.append("--json") }
        if apply { args.append("--apply") }
        return args
    }
}
