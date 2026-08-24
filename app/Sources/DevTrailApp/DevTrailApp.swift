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
        status.refreshSnapshot()
        guard timer == nil else { return }

        // 패널이 열려 있지 않아도 아이콘 색은 최신이어야 한다.
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                // ⚠️ 앱이 앞으로 나올 때만 갱신한다. 렌더마다 부르면
                //    메뉴를 여는 것만으로 CLI 가 수십 번 뜬다.
                if status.busy == nil { status.refresh(); status.refreshSnapshot() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
