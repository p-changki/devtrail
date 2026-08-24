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

    // ── Obsidian 없이 보는 상태 ────────────────────────────────────────────
    // ⚠️ 앱은 이 하나만 소비한다. Markdown·경로 규칙을 스스로 해석하지 않는다.
    @Published var snapshot: Snapshot? = nil
    @Published var snapshotError: String? = nil
    /// snapshot 이 알려준 오늘 개발일지 경로. 앱이 조립하지 않는다.
    @Published var snapshotDevlogPath: String? = nil

    // ── 링크 받아두기 ──────────────────────────────────────────────────────
    @Published var captureBusy = false
    @Published var captureError: String? = nil
    @Published var captureResult: String? = nil
    @Published var captureUndoJob: String? = nil
    @Published var backfillDate = ""

    // MARK: - 터미널 연결 (ADR 0006 M4-4b)
    //
    // ⚠️ 판정은 **CLI 가 한다.** 앱은 `devtrail link status --json` 을 읽어
    //    그리기만 한다 — 같은 판정을 두 벌 두면 반드시 어긋난다.
    //
    //    absent | linked_here | linked_other | occupied
    @Published var linkState = ""
    @Published var linkPath = ""
    @Published var linkTarget = ""
    @Published var linkOnPath = true

    /// 떼어낼 수 있는 읽기전용 볼륨(마운트된 DMG)에서 실행 중인가.
    ///
    /// ⚠️ 판정은 CLI 가 한다 (`link status --json` 의 `self_readonly`).
    ///    앱이 자기 경로를 보고 스스로 정하지 않는다 — 같은 판정을 두 벌 두면
    ///    반드시 어긋난다.
    @Published var runningFromVolume = false

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

        // ⚠️ DMG 로 받은 사람은 PATH 에 devtrail 이 없다. 앱은 번들 것을
        //    절대경로로 부르니 잘 돌지만, 터미널에서는 없다 — 그 사실을
        //    감추지 않는다.
        if let l = CLI.json(["link", "status", "--json"]) {
            linkState = l["state"] as? String ?? ""
            linkPath = l["path"] as? String ?? ""
            linkTarget = l["target"] as? String ?? ""
            linkOnPath = (l["on_path"] as? Bool) ?? true
            runningFromVolume = (l["self_readonly"] as? Bool) ?? false
        } else {
            // ⚠️ 못 읽었으면 **모른다** 고 둔다. 안다고 꾸미지 않는다.
            linkState = ""
            runningFromVolume = false
        }

        // ⚠️ '셋업했는가' 를 파일 존재로 판정하지 않는다. 설정 파일이 있어도
        //    스키마가 낡았거나 CLI 가 읽지 못할 수 있고, 그러면 앱은 셋업된
        //    줄 알고 빈 화면을 보여준다. 판정은 CLI 가 한다.
        //    CLI 를 못 부르면 파일 존재로 떨어진다 — 그때도 화면은 나와야 한다.
        if let s = CLI.json(["setup", "status", "--json"]) {
            needsSetup = (s["configured"] as? Bool) == false
        } else {
            needsSetup = !FileManager.default.fileExists(atPath: configPath)
        }
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
    /// 사용자가 직접 붙여넣을 수 있는 셋업 명령.
    ///
    /// ⚠️ 왜 필요한가 (2026-08-24 실물 QA)
    ///
    ///    Terminal 은 명령을 **타이핑해서** 넣는다. 그 순간 셸 초기화가
    ///    입력을 기다리고 있으면 글자를 먹는다 — oh-my-zsh 의
    ///    "Would you like to update? [Y/n]" 가 경로의 첫 글자 `/` 를 삼켜
    ///    `var/folders/…: no such file or directory` 로 죽었다.
    ///
    ///    사용자의 `.zshrc` 를 우리가 통제할 수 없으므로 근본은 못 고친다.
    ///    **항상 통하는 길을 하나 둔다** — 복사해서 붙여넣기.
    var setupCommand: String {
        "\(Self.shellQuoted(CLI.binary)) init"
    }

    /// 경로에 공백·따옴표가 있어도 안전하게.
    static func shellQuoted(_ p: String) -> String {
        "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func startSetup() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("devtrail-setup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("setup.command")

        // 경로에 공백·따옴표가 있어도 안전하도록 작은따옴표로 감싸고,
        // 안의 작은따옴표는 이스케이프한다.
        let quoted = Self.shellQuoted(CLI.binary)
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

    /// 터미널에서도 쓸 수 있게 연결한다.
    ///
    /// ⚠️ **덮어쓰지 않는다.** 이미 다른 devtrail 이 있으면 CLI 가 거부하고,
    ///    앱은 그 말을 그대로 전한다. 판정도 거부도 여기서 하지 않는다.
    func linkTerminal() {
        let r = CLI.run(["link", "create"])
        lastOutput = r.text
        refresh()
    }

    // MARK: - 경로

    private var devtrailHome: String {
        ProcessInfo.processInfo.environment["DEVTRAIL_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".devtrail").path
    }

    /// 폴더 경로. CLI 가 유일한 해석기다.
    ///
    /// ⚠️ 여기서 dirs 를 직접 읽고 기본값을 두면 앱이 세 번째 해석기가 된다.
    ///    새로 설치한 볼트는 dirs 가 비어 있어 <루트>/devlog/ 를 가리키게 되고,
    ///    파일이 멀쩡히 있는데도 "개발일지 없음" 이 뜬다. 같은 결함을 생성
    ///    스크립트와 웹 대시보드에서 이미 두 번 고쳤다(2026-08-22 실물 QA).
    private var pathCache: [String: String] = [:]

    private func vaultPath(_ key: String) -> String? {
        guard let vault = dig("vault.path") as? String, !vault.isEmpty else { return nil }
        if let hit = pathCache[key] { return "\(vault)/\(hit)" }
        guard let obj = CLI.json(["path", "--json"]),
              let entry = obj[key] as? [String: Any],
              let rel = entry["rel"] as? String, !rel.isEmpty else { return nil }
        pathCache[key] = rel
        return "\(vault)/\(rel)"
    }

    /// 오늘 개발일지 절대경로. 모르면 nil.
    ///
    /// ⚠️ 파일명 규칙을 여기서 갖지 않는다. snapshot 이 CLI 가 해석한 경로를
    ///    그대로 준다 — 앱이 규칙을 한 벌 더 가지면 어느 한쪽이 바뀔 때
    ///    "파일이 있는데 없다" 고 말하는 화면이 생긴다. 이 저장소는
    ///    dirs.devlog 로 같은 병을 네 번 고쳤다.
    var devlogFile: String? { snapshotDevlogPath }

    /// 주간리뷰 폴더. 특정 파일명은 ISO 주차 계산이 필요해 폴더를 연다.
    var weeklyDir: String? { vaultPath("weekly") }

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

        // ⚠️ 경로를 여기서 다시 조립하지 않는다. devlogFile 이 CLI 로 해석한다.
        guard let path = devlogFile else {
            devlogExists = false; prRows = 0; summaries = 0; return
        }

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

    // ⚠️ 웹 대시보드는 **폐지됐다** (D5, 2026-08-24). 여기 있던 상주
    //    프로세스 관리 코드도 함께 지웠다 — 화면에서만 지우고 모델에
    //    남겨두면, 다음 사람이 "아직 있는 기능" 으로 읽는다.
    //
    //    같은 일은 이 앱이 직접 한다: 같은 4가지 동작 · 같은 3개 토글.

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
    // ── Snapshot ───────────────────────────────────────────────────────────
    //
    // ⚠️ 렌더마다 부르지 않는다. SwiftUI 의 body 는 자주 다시 그려지고,
    //    거기서 프로세스를 띄우면 메뉴를 여는 것만으로 CLI 가 수십 번 뜬다.
    //    앱이 앞으로 나올 때와 사용자가 새로고침을 누를 때만 부른다.
    func refreshSnapshot() {
        CLI.runAsync(["command-center", "snapshot", "--json"]) { [weak self] r in
            guard let self = self else { return }
            guard r.ok, let data = r.out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let dict = obj as? [String: Any], let snap = Snapshot(dict) else {
                // ⚠️ 실패를 '아무것도 없음' 으로 보여주지 않는다. 못 읽은 것과
                //    비어 있는 것은 다른 사실이다.
                self.snapshot = nil
                self.snapshotError = r.ok ? "상태를 읽지 못했습니다" : self.cliFailure(r)
                return
            }
            self.snapshot = snap
            self.snapshotDevlogPath =
                ((dict["today"] as? [String: Any])?["devlog_path"] as? String)
            self.snapshotError = nil
        }
    }

    private func cliFailure(_ r: CLI.Result) -> String {
        if self.cliMissing { return "devtrail 을 찾지 못했습니다" }
        let err = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? "devtrail 실행에 실패했습니다" : err
    }

    // ── 링크 받아두기 ──────────────────────────────────────────────────────
    //
    // ⚠️ URL 을 문자열로 이어 붙이지 않는다. 인자 배열로 넘긴다 —
    //    YouTube URL 에는 & 가 흔하고, 셸을 거치면 거기서 잘린다.
    // ⚠️ 노트를 앱이 만들지 않는다. CLI 가 만들고, 저널에 남고, undo 로 사라진다.
    func captureYouTube(_ url: String, apply: Bool) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            captureError = "링크를 입력하세요"
            return
        }
        // ⚠️ 두 번 누르면 노트가 두 개 생긴다. 버튼 비활성화는 첫 방어선이지만
        //    화면 밖에서 이 함수를 부를 수도 있다. 모델에서도 막는다.
        guard !captureBusy else { return }
        captureBusy = true
        captureError = nil
        captureResult = nil

        var args = ["capture", "youtube", "--url", trimmed]
        if apply { args.append("--apply") }
        CLI.runAsync(args) { [weak self] r in
            guard let self = self else { return }
            self.captureBusy = false
            let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard r.ok else {
                self.captureError = self.cliFailure(r)
                return
            }
            self.captureResult = out.isEmpty ? "완료" : out
            if apply {
                self.captureUndoJob = Status.undoJob(from: out)
                self.refreshSnapshot()
            }
        }
    }

    /// 출력에서 되돌리기 작업 번호를 찾는다. 없으면 nil —
    /// 지어내지 않는다.
    static func undoJob(from output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("undo") {
            for token in line.split(separator: " ") {
                let t = token.trimmingCharacters(in: .whitespaces)
                if t.count == 20, t.contains("-"), t.first?.isNumber == true { return t }
            }
        }
        return nil
    }

}
