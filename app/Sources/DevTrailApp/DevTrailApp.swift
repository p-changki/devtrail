import AppKit
import SwiftUI

@main
struct DevTrailApp: App {
    @NSApplicationDelegateAdaptor(DevTrailAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(status: appDelegate.status)
        } label: {
            // 아이콘 하나로 "돌고 있나?" 에 답한다 — 이 앱의 존재 이유다.
            Image(systemName: appDelegate.symbol)
        }
        .menuBarExtraStyle(.window)   // 기본 메뉴가 아닌 커스텀 패널
    }
}

/// 앱을 눌러야만 MenuBarExtra 내용이 만들어지는 구조라, 첫 실행을 메뉴 안의
/// onAppear 에 두면 사용자는 메뉴바 아이콘을 먼저 찾아야 한다. 시작 시점은
/// AppDelegate 가 잡고, 미설정일 때만 같은 MenuView 를 독립 창으로 한 번 연다.
@MainActor
final class DevTrailAppDelegate: NSObject, NSApplicationDelegate {
    let status = Status()
    private var timer: Timer?
    private var firstRunWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    var symbol: String {
        switch status.health {
        case .ok:      return "circle.fill"
        case .warn:    return "circle.dotted"
        case .bad:     return "exclamationmark.circle"
        case .unknown: return "circle"
        }
    }

    private func start() {
        status.refresh()
        status.refreshSnapshot()
        presentFirstRunWindowIfNeeded()
        guard timer == nil else { return }

        // 패널이 열려 있지 않아도 아이콘 색은 최신이어야 한다.
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                // ⚠️ 앱이 앞으로 나올 때만 갱신한다. 렌더마다 부르면
                //    메뉴를 여는 것만으로 CLI 가 수십 번 뜬다.
                if self.status.busy == nil { self.status.refresh(); self.status.refreshSnapshot() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 첫 실행을 알아차리지 못하면 앱이 고장 난 것처럼 보인다. 반대로 매번
    /// 창을 띄우면 메뉴바 앱의 장점이 사라지므로, 이 실행 중 미설정일 때 한 번만
    /// 띄운다. 창을 닫아도 아무 파일도 바뀌지 않는다.
    private func presentFirstRunWindowIfNeeded() {
        guard status.needsSetup, firstRunWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevTrail 시작하기"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FirstRunView(
            status: status,
            onClose: { window.close() }
        ))
        window.center()
        firstRunWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
