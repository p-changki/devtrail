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
///   - 이 화면은 값 세 개를 넘기고 결과를 그릴 뿐이다.
///
///   같은 판정을 CLI 와 앱에 두 벌 두면 반드시 어긋나고, 어긋난 쪽이 화면이면
///   사용자가 먼저 본다 — 2026-08-22 실물 QA 의 결함 9건 중 4건이 그 유형이었다.
@MainActor
final class Onboarding: ObservableObject {

    struct Candidate: Identifiable, Hashable {
        let path: String
        let name: String
        var id: String { path }
    }

    enum Phase: Equatable {
        case picking          // 언어·볼트를 고르는 중
        case preview(String)  // 무엇이 될지 미리 보여준 상태
        case applying
        case done(String)
        case failed(String)
    }

    @Published var lang = "ko"
    @Published var candidates: [Candidate] = []
    @Published var selected: String = ""
    @Published var phase: Phase = .picking
    /// CLI 가 제안한 설치 방식 (new | existing | isolated). 화면은 표시만 한다.
    @Published var suggestedMode = ""

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
            return Candidate(path: p, name: (v["name"] as? String) ?? p)
        }
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
        if let spec = CLI.json(["setup", "quick", "--vault", selected,
                                "--lang", lang, "--json"]),
           let v = spec["vault"] as? [String: Any] {
            suggestedMode = (v["mode"] as? String) ?? ""
        }
        let r = CLI.run(["setup", "quick", "--vault", selected, "--lang", lang])
        phase = r.ok ? .preview(r.text) : .failed(r.text)
    }

    /// 실제로 적용한다.
    ///
    /// ⚠️ 되돌릴 수 있는 변경만 여기서 한다 — `setup apply` 가 저널을 열고
    ///    한 번의 셋업을 하나의 되돌림 단위로 만든다.
    func apply() {
        guard !selected.isEmpty else { return }
        phase = .applying
        let r = CLI.run(["setup", "quick", "--vault", selected,
                         "--lang", lang, "--apply"])
        phase = r.ok ? .done(r.text) : .failed(r.text)
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
}
