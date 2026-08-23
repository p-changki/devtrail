import Foundation

/// devtrail CLI 호출 래퍼.
///
/// 앱은 셸을 거치지 않고 실행 파일을 직접 띄운다(`Process` + 인자 배열).
/// 셸을 경유하면 경로에 공백·따옴표가 있을 때 인젝션 위험이 생긴다.
enum CLI {

    struct Result {
        let ok: Bool
        let code: Int32
        let out: String
        let err: String
        var text: String { (out + err).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 앱 번들 안에 함께 실린 CLI (ADR 0006 M4-3).
    ///
    /// ⚠️ `Contents/Resources/bin/devtrail` 이다. CLI 는 자기 위치에서
    ///    `DEVTRAIL_ROOT` 를 계산하므로, 여기서 부르면 `lib`·`plugin`·
    ///    `preset`·`templates`·`skills` 도 전부 번들 것을 쓴다.
    static var bundled: String? {
        let p = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin/devtrail").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// devtrail 실행 파일 위치.
    /// 1) 환경변수 DEVTRAIL_BIN  2) **앱 번들 안**  3) 흔한 설치 경로
    ///
    /// ⚠️ 번들이 설치본보다 **먼저**다. 앱과 CLI 는 한 릴리즈로 함께 나가고,
    ///    섞이면 사용자 볼트가 조용히 어긋난다 — 릴리즈 매니페스트(M6)가
    ///    막으려는 바로 그 어긋남이다. 사용자가 따로 설치한 CLI 는 터미널에서
    ///    그대로 쓰인다(D4 공존); 앱이 그걸 대신 부르지 않을 뿐이다.
    ///
    /// ⚠️ 예전 주석은 "2) 앱 번들 옆" 이라고 적혀 있었는데 코드는 번들을
    ///    보지 않았다. 주석이 거짓말을 하고 있었다.
    static var binary: String {
        if let env = ProcessInfo.processInfo.environment["DEVTRAIL_BIN"],
           FileManager.default.isExecutableFile(atPath: env) { return env }

        if let b = bundled { return b }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/devtrail",
            "\(home)/.devtrail/src/bin/devtrail",
            "/opt/homebrew/bin/devtrail",
            "/usr/local/bin/devtrail",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "\(home)/.local/bin/devtrail"
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binary)
    }

    /// 프로세스 공통 설정. GUI 앱은 PATH가 최소 상태라 gh/jq/git 을 못 찾는다.
    private static func configure(_ p: Process, _ args: [String]) {
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["NO_COLOR"] = "1"          // 메뉴에 ANSI 이스케이프가 섞이지 않게

        // ⚠️ **코드 위치를 바꾸는 환경변수는 물려주지 않는다** (ADR 0006 M4-3).
        //
        //    이 셋은 개발·테스트용 우회로다. 사용자 환경에 남아 있으면
        //    (`launchctl setenv`, 터미널에서 띄운 경우) 번들 앱이 조용히
        //    **저장소 쪽 코드**를 쓴다 — 그리고 그 기계에서만 그런다.
        //
        //    설정 위치(DEVTRAIL_HOME·DEVTRAIL_CONFIG)는 사용자의 정당한
        //    선택이므로 건드리지 않는다. 지우는 건 **코드를 옮기는 것**뿐이다.
        for k in ["DEVTRAIL_ROOT", "DT_CC_SRC_OVERRIDE", "DT_HELPER_OVERRIDE"] {
            env.removeValue(forKey: k)
        }

        p.environment = env
    }

    private static func launchFailure(_ error: Error) -> Result {
        Result(ok: false, code: -1, out: "",
               err: "devtrail 실행 실패: \(error.localizedDescription)\n경로: \(binary)")
    }

    /// 끝나는 명령을 실행하고 결과를 기다린다.
    ///
    /// ⚠️ 상주하는 명령(`dashboard` 등)에는 쓰지 않는다 — `start(_:onLine:)` 를 쓴다.
    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 900) -> Result {
        let p = Process()
        configure(p, args)

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do { try p.run() } catch { return launchFailure(error) }

        // 파이프는 별도 스레드에서 읽는다.
        //
        // 여기서 readDataToEndOfFile()을 직접 부르면 자식이 끝날 때까지 막힌다.
        // 그러면 아래 타임아웃 대기에 영영 도달하지 못해 timeout 인자가 무의미해진다
        // (끝나지 않는 명령을 부르면 앱이 그대로 멈춘다).
        var outData = Data(), errData = Data()
        let lock = NSLock()
        let group = DispatchGroup()
        for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isOut { outData = d } else { errData = d }
                lock.unlock()
                group.leave()
            }
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if group.wait(timeout: .now() + 3) == .timedOut, p.isRunning {
                kill(p.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 2)
            }
            return Result(ok: false, code: -1, out: "",
                          err: "시간 초과(\(Int(timeout))초) — 중단했습니다")
        }

        p.waitUntilExit()
        lock.lock()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        lock.unlock()

        return Result(ok: p.terminationStatus == 0, code: p.terminationStatus,
                      out: out, err: err)
    }

    /// 끝나지 않는 명령(예: `dashboard` 서버)을 띄우고 기다리지 않는다.
    ///
    /// 출력은 줄 단위로 흘려보낸다 — 시작에 성공했는지(주소)와 실패 사유를
    /// UI가 알 수 있어야 하기 때문이다. 반환한 Process는 호출자가 종료시킨다.
    static func start(_ args: [String], onLine: @escaping (String) -> Void) -> Process? {
        let p = Process()
        configure(p, args)

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil    // EOF — 자식이 끝났다
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                DispatchQueue.main.async { onLine(trimmed) }
            }
        }

        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            let message = launchFailure(error).text
            DispatchQueue.main.async { onLine(message) }
            return nil
        }
        return p
    }

    /// `--json` 을 붙여 실행하고 딕셔너리로 돌려준다. 실패하면 nil.
    ///
    /// ⚠️ 앱은 설정 파일을 직접 파싱하지 않는다.
    ///
    ///    예전에는 그렇게 했고, 그래서 앱이 세 번째 경로 해석기가 됐다 —
    ///    `dig("dirs.devlog") ?? "devlog"` 처럼 자기만의 기본값을 갖고 있었다.
    ///    그런데 `dirs` 는 '사용자가 고른 폴더' 만 담아서 새로 설치한 볼트에서는
    ///    비어 있다. 화면은 <루트>/devlog/ 를 가리키며 "개발일지 없음" 이라고
    ///    말하는데 파일은 개발/개발일지 에 멀쩡히 있는 상태가 된다.
    ///    같은 결함을 생성 스크립트와 웹 대시보드에서 이미 두 번 고쳤다
    ///    (2026-08-22 실물 QA).
    ///
    ///    해석은 CLI 한 곳에서만 한다.
    static func json(_ args: [String], timeout: TimeInterval = 30) -> [String: Any]? {
        let r = run(args, timeout: timeout)
        guard r.ok, let data = r.out.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 백그라운드에서 실행하고 메인 스레드로 결과를 넘긴다.
    static func runAsync(_ args: [String], completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = run(args)
            DispatchQueue.main.async { completion(r) }
        }
    }
}
