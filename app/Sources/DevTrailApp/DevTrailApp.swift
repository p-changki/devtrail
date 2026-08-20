import SwiftUI

@main
struct DevTrailApp: App {
    @StateObject private var status = Status()
    @State private var timer: Timer?

    var body: some Scene {
        MenuBarExtra {
            MenuView(status: status)
                .onAppear { start() }
        } label: {
            // 아이콘 하나로 "돌고 있나?" 에 답한다 — 이 앱의 존재 이유다.
            Image(systemName: symbol)
        }
        .menuBarExtraStyle(.window)   // 기본 메뉴가 아닌 커스텀 패널
    }

    private var symbol: String {
        switch status.health {
        case .ok:      return "circle.fill"
        case .warn:    return "circle.dotted"
        case .bad:     return "exclamationmark.circle"
        case .unknown: return "circle"
        }
    }

    private func start() {
        status.refresh()
        guard timer == nil else { return }

        // 앱이 띄운 대시보드 서버는 앱과 함께 정리한다.
        // 남겨두면 포트를 잡은 채 살아 있는데 토큰 주소는 사라져 손댈 수 없다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { status.stopDashboard() }
        }
        // 패널이 열려 있지 않아도 아이콘 색은 최신이어야 한다.
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                if status.busy == nil { status.refresh() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
