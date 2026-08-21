import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// 앱이 보여주는 상태. 전부 CLI 호출과 설정 파일 읽기로 채운다.
@MainActor
final class Status: ObservableObject {

    enum Health { case ok, warn, bad, unknown }

    @Published var health: Health = .unknown
    @Published var headline = "확인 중…"
    @Published var detail = ""
    @Published var date = ""
    @Published var githubUser = ""
    @Published var aiProvider = ""
    @Published var prRows = 0
    @Published var summaries = 0
    @Published var devlogExists = false
    @Published var hasActivity = false
    @Published var scheduleLoaded = 0
    @Published var toggles: [String: Bool] = [:]
    /// 토글 값을 읽지 못한 상태. '전부 꺼짐'과 구분해야 한다.
    @Published var togglesUnavailable = false
    @Published var dashboardURL = ""
    @Published var busy: String? = nil          // 실행 중인 작업 이름
    @Published var lastOutput = ""
    @Published var cliMissing = false
    /// 설정 파일이 없다 = 아직 셋업하지 않았다.
    ///
    /// ⚠️ 예전에는 이 상태를 구분하지 않아, 셋업조차 안 한 사용자에게
    ///    "오늘 개발일지 없음" 이라고 말했다. 사실이 아닌 데다 다음에
    ///    무엇을 해야 하는지도 알려주지 않는 막다른 길이었다.
    @Published var needsSetup = false
    @Published var lastRun = ""                 // 마지막 자동 실행 시각
    @Published var backfillDate = ""

    var scheduleOn: Bool { scheduleLoaded > 0 }

    private var config: [String: Any] = [:]

    private var configPath: String {
        ProcessInfo.processInfo.environment["DEVTRAIL_CONFIG"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".devtrail/devtrail.config.json").path
    }

    // MARK: - 로드

    func refresh() {
        guard CLI.isInstalled else {
            cliMissing = true
            health = .bad
            headline = "devtrail을 찾을 수 없습니다"
            detail = "설치 후 다시 열어주세요"
            return
        }
        cliMissing = false

        needsSetup = !FileManager.default.fileExists(atPath: configPath)
        if needsSetup {
            health = .warn
            headline = "아직 셋업하지 않았습니다"
            detail = "볼트와 Obsidian 을 한 번에 준비합니다"
            return
        }

        loadConfig()
        loadDevlog()
        loadSchedule()
        loadLastRun()
        computeHealth()
        if backfillDate.isEmpty { backfillDate = yesterday() }
    }

    // MARK: - 셋업

    /// `devtrail init` 을 Terminal 에서 연다.
    ///
    /// 왜 앱 안에서 안 하나: init 은 대화형이다. 답을 받아야 하고, 그 답이
    /// 사용자의 볼트를 바꾼다. 그 대화를 앱 안에 다시 만드는 것은 같은 것을
    /// 두 벌 관리하는 일이고, 둘이 어긋나는 순간 사용자가 다친다.
    /// 앱이 할 일은 사용자를 그 대화 앞에 데려다 놓는 것까지다.
    ///
    /// AppleScript 대신 실행 파일을 Terminal 로 여는 방식을 쓴다 —
    /// 자동화 권한 대화상자를 띄우지 않는다.
    func startSetup() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("devtrail-setup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("setup.command")

        // 경로에 공백·따옴표가 있어도 안전하도록 작은따옴표로 감싸고,
        // 안의 작은따옴표는 이스케이프한다.
        let quoted = "'" + CLI.binary.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let body = """
        #!/bin/sh
        clear
        exec \(quoted) init
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else {
            lastOutput = "셋업 스크립트를 만들지 못했습니다."
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: script.path)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", script.path]
        do { try open.run() } catch { lastOutput = "Terminal 을 열지 못했습니다." }
    }

    // MARK: - 경로

    private var devtrailHome: String {
        ProcessInfo.processInfo.environment["DEVTRAIL_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".devtrail").path
    }

    /// 오늘 개발일지 절대경로. 없으면 nil.
    var devlogFile: String? {
        guard let vault = dig("vault.path") as? String, !vault.isEmpty else { return nil }
        let root = dig("vault.root") as? String ?? ""
        let dir = dig("dirs.devlog") as? String ?? "devlog"
        let pattern = dig("naming.devlog_file") as? String ?? "{{DATE}} devlog.md"
        return "\(vault)/\(root)/\(dir)/\(pattern.replacingOccurrences(of: "{{DATE}}", with: date))"
    }

    /// 주간리뷰 폴더. 특정 파일명은 ISO 주차 계산이 필요해 폴더를 연다.
    var weeklyDir: String? {
        guard let vault = dig("vault.path") as? String, !vault.isEmpty else { return nil }
        let root = dig("vault.root") as? String ?? ""
        return "\(vault)/\(root)/\(dig("dirs.weekly") as? String ?? "weekly")"
    }

    /// 설정 화면 하단에 표시할 볼트 위치(짧게).
    var vaultLabel: String {
        guard let vault = dig("vault.path") as? String, !vault.isEmpty else {
            return "볼트 미설정 — devtrail init"
        }
        return (vault as NSString).abbreviatingWithTildeInPath
    }

    func yesterday() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }

    private func loadConfig() {
        if let data = FileManager.default.contents(atPath: configPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = obj
        } else {
            config = [:]
        }
        githubUser = dig("github.user") as? String ?? ""
        aiProvider = dig("ai.provider") as? String ?? ""
        // 설정을 못 읽었어도 건너뛰지 않는다 — 건너뛰면 토글이 조용히 '꺼짐'이 된다.
        loadEffectiveToggles()
    }

    static let toggleKeys = ["ai.summary_enabled", "backup.enabled", "linear.enabled"]

    /// 토글 값은 설정 파일에서 직접 읽지 않는다.
    ///
    /// 키가 없을 때의 기본값이 셸과 달라지면, 화면에는 "꺼짐"이라고 나오는데
    /// 실제로는 켜져서 도는 상태가 된다(백업·AI 과금). 기본값의 단일 출처인
    /// `devtrail config effective` 를 통해서만 읽는다.
    private func loadEffectiveToggles() {
        let r = CLI.run(["config", "effective"], timeout: 15)
        guard r.ok,
              let data = r.out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // 실패 시 이전 값을 유지하되 '모름'으로 표시한다.
            // 스위치를 꺼진 것처럼 보여주면, 실제로는 백업·AI 요약이 돌고 있는데
            // 꺼져 있다고 믿게 된다.
            togglesUnavailable = true
            return
        }
        var next: [String: Bool] = [:]
        for key in Self.toggleKeys {
            if let v = obj[key] as? Bool { next[key] = v }
        }
        toggles = next
        togglesUnavailable = next.count != Self.toggleKeys.count
    }

    /// 이 키의 값을 신뢰할 수 있는가.
    func toggleKnown(_ key: String) -> Bool {
        !togglesUnavailable && toggles[key] != nil
    }

    private func dig(_ path: String) -> Any? {
        var cur: Any? = config
        for part in path.split(separator: ".") {
            guard let d = cur as? [String: Any] else { return nil }
            cur = d[String(part)]
        }
        return cur
    }

    private func loadDevlog() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        date = f.string(from: Date())

        guard let vault = dig("vault.path") as? String, !vault.isEmpty else {
            devlogExists = false; prRows = 0; summaries = 0; return
        }
        let root = dig("vault.root") as? String ?? ""
        let dir = dig("dirs.devlog") as? String ?? "devlog"
        let pattern = dig("naming.devlog_file") as? String ?? "{{DATE}} devlog.md"
        let name = pattern.replacingOccurrences(of: "{{DATE}}", with: date)
        let path = "\(vault)/\(root)/\(dir)/\(name)"

        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            devlogExists = false; prRows = 0; summaries = 0; hasActivity = false; return
        }
        devlogExists = true
        hasActivity = text.contains("devtrail:activity:start")
        prRows = count(in: text, pattern: #"(?m)^\| \[[^\]]*#\d+\]"#)
        summaries = count(in: text, pattern: #"(?m)^> \[!abstract\]"#)
    }

    private func count(in text: String, pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private func loadSchedule() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { scheduleLoaded = 0; return }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        p.waitUntilExit()
        scheduleLoaded = out.split(separator: "\n")
            .filter { $0.contains("com.devtrail.") }.count
    }

    /// 마지막 자동 실행 시각. launchd 로그 파일의 수정 시각으로 판단한다.
    /// "돌고 있나?" 에 답하려면 '언제' 돌았는지가 핵심이다.
    private func loadLastRun() {
        let log = "\(devtrailHome)/logs/com.devtrail.daily.log"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: log),
              let modified = attrs[.modificationDate] as? Date else {
            lastRun = ""
            return
        }
        let mins = Int(Date().timeIntervalSince(modified) / 60)
        switch mins {
        case ..<1:   lastRun = "방금"
        case ..<60:  lastRun = "\(mins)분 전"
        case ..<1440: lastRun = "\(mins / 60)시간 전"
        default:     lastRun = "\(mins / 1440)일 전"
        }
    }

    private func computeHealth() {
        if !devlogExists {
            health = .warn
            headline = "오늘 개발일지 없음"
            detail = "노트를 만들면 활동이 자동으로 들어갑니다"
        } else if !hasActivity {
            health = .warn
            headline = "아직 삽입 전"
            detail = "‘활동 가져오기’를 눌러보세요"
        } else if scheduleLoaded == 0 {
            health = .warn
            headline = "\(prRows)개 항목 · 요약 \(summaries)건"
            detail = "자동 실행이 꺼져 있습니다 — 아래에서 켤 수 있습니다"
        } else {
            health = .ok
            headline = "\(prRows)개 항목 · 요약 \(summaries)건"
            detail = lastRun.isEmpty
                ? "자동 실행 \(scheduleLoaded)개 등록됨"
                : "마지막 실행 \(lastRun)"
        }
    }

    // MARK: - 동작

    func run(_ label: String, _ args: [String]) {
        guard busy == nil else { return }
        busy = label
        CLI.runAsync(args) { [weak self] r in
            guard let self else { return }
            self.lastOutput = r.text
            self.busy = nil
            self.refresh()
        }
    }

    // MARK: - 로그인 시 자동 시작
    //
    // 메뉴바 앱이 재부팅으로 사라지면 "항상 거기 있는 것"이라는 전제가 깨진다.
    // SMAppService(macOS 13+)는 시스템 설정 > 로그인 항목에 그대로 노출된다.

    var launchAtLoginAvailable: Bool {
        // 번들 경로가 앱 번들이 아니면(예: 개발 중 직접 실행) 등록이 실패한다.
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard launchAtLoginAvailable else {
            lastOutput = "로그인 시 시작은 .app 으로 실행할 때만 설정할 수 있습니다."
            return
        }
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch {
            lastOutput = "로그인 항목 설정 실패: \(error.localizedDescription)"
        }
    }

    /// 자동 실행(launchd) 등록/해제.
    /// 앱이 "등록하세요"라고 안내만 하고 수단을 주지 않으면 터미널로 내몰게 된다.
    func setSchedule(_ on: Bool) {
        guard busy == nil else { return }
        busy = on ? "자동 실행 등록" : "자동 실행 해제"
        CLI.runAsync([on ? "install-schedule" : "uninstall"]) { [weak self] r in
            guard let self else { return }
            self.lastOutput = r.text
            self.busy = nil
            self.refresh()
        }
    }

    /// 지난 날짜 채워 넣기. 잘못된 형식은 CLI까지 보내지 않는다.
    func runBackfill() {
        let d = backfillDate.trimmingCharacters(in: .whitespaces)
        guard d.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            lastOutput = "날짜 형식이 올바르지 않습니다: \(d)  (예: 2026-08-19)"
            return
        }
        run("백필", ["backfill", d])
    }

    // MARK: - 웹 대시보드
    //
    // 대시보드 서버는 스스로 끝나지 않는다. `run` 으로 부르면 완료를 기다리다
    // busy 상태에 갇혀 패널의 모든 버튼이 잠긴다. 반드시 상주 프로세스로 다룬다.

    private var dashboardProcess: Process?

    var dashboardRunning: Bool { dashboardProcess?.isRunning == true }

    func openDashboard() {
        // 이미 떠 있으면 새로 띄우지 않는다 — 포트가 하나뿐이라 두 번째는 실패한다.
        if dashboardRunning {
            if let url = URL(string: dashboardURL) {
                NSWorkspace.shared.open(url)
            } else {
                lastOutput = "대시보드가 이미 실행 중입니다."
            }
            return
        }

        dashboardURL = ""
        lastOutput = "대시보드를 시작합니다…"
        // 서버가 스스로 브라우저를 연다. 여기서는 주소(토큰 포함)만 받아 둔다.
        dashboardProcess = CLI.start(["dashboard"]) { [weak self] line in
            guard let self else { return }
            if self.dashboardURL.isEmpty,
               let r = line.range(of: "https?://[^ ]+", options: .regularExpression) {
                self.dashboardURL = String(line[r])
            }
            self.lastOutput = line
        }
        if dashboardProcess == nil { lastOutput = "대시보드를 시작하지 못했습니다." }
    }

    /// 앱이 띄운 서버는 앱이 정리한다 — 남겨두면 포트를 잡은 채 주소만 사라진다.
    func stopDashboard() {
        guard let p = dashboardProcess else { return }
        if p.isRunning { p.terminate() }
        dashboardProcess = nil
        dashboardURL = ""
    }

    /// 노트를 Obsidian으로 연다.
    /// obsidian:// 스킴이 실패할 수 있으므로 파일 열기로 폴백한다.
    func openInObsidian(path: String?) {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            lastOutput = "파일이 아직 없습니다" + (path.map { ":\n\($0)" } ?? "")
            return
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        if let enc = path.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "obsidian://open?path=\(enc)") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openPath(_ path: String?) {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            lastOutput = "경로가 없습니다" + (path.map { ":\n\($0)" } ?? "")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func setToggle(_ key: String, _ value: Bool) {
        guard busy == nil else { return }
        busy = "설정 변경"
        CLI.runAsync(["config", "set", key, value ? "true" : "false"]) { [weak self] r in
            guard let self else { return }
            if r.ok { self.toggles[key] = value } else { self.lastOutput = r.text }
            self.busy = nil
            self.refresh()
        }
    }
}
