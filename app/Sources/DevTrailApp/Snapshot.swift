import Foundation

/// `devtrail command-center snapshot --json` 이 낸 것을 그대로 담는다.
///
/// ⚠️ 앱은 Markdown 도 frontmatter 도 경로 규칙도 해석하지 않는다. CLI 가
///    단일 출처다 — 앱이 규칙을 한 벌 더 가지면 화면과 볼트가 갈린다.
///    이 저장소는 dirs.devlog 로 같은 결함을 네 번 고쳤다.
///
/// ⚠️ 모르는 값은 nil 이다. 0 이나 false 로 채우면 화면이 "확인해 봤더니
///    없다" 고 말하는데, 실은 못 본 것이다.
struct Snapshot {
    struct Today {
        var date: String
        var devlogExists: Bool
        var openTasks: Int?      // nil = 모른다
    }
    struct NextAction {
        var project: String
        var text: String
    }
    struct InboxItem {
        var title: String
        var path: String
    }

    var vaultAvailable: Bool
    var today: Today?
    var activeProjects: Int?
    var nextActions: [NextAction]
    var inboxCount: Int?
    var inboxOldest: String?
    var inboxPreview: [InboxItem]
    var ccInstalled: Bool?
    var ccEnabled: Bool?
    var ccVersion: String
    var ccUpdateState: String
    var restartRecommended: Bool
    var obsidianRunning: Bool

    /// CLI.json 이 준 사전에서 읽는다. 없는 키는 nil 로 둔다.
    init?(_ d: [String: Any]) {
        guard let vault = d["vault"] as? [String: Any] else { return nil }
        vaultAvailable = (vault["available"] as? Bool) ?? false

        if let t = d["today"] as? [String: Any] {
            today = Today(
                date: (t["date"] as? String) ?? "",
                devlogExists: (t["devlog_exists"] as? Bool) ?? false,
                // "unknown" 이 올 수 있다 — 숫자가 아니면 모르는 것이다.
                openTasks: t["open_tasks"] as? Int
            )
        } else {
            today = nil
        }

        let p = d["projects"] as? [String: Any]
        activeProjects = p?["active_count"] as? Int
        nextActions = ((p?["next_actions"] as? [[String: Any]]) ?? []).compactMap {
            guard let proj = $0["project"] as? String,
                  let text = $0["next_action"] as? String, !text.isEmpty else { return nil }
            return NextAction(project: proj, text: text)
        }

        let i = d["inbox"] as? [String: Any]
        inboxCount = i?["count"] as? Int
        inboxOldest = i?["oldest_at"] as? String
        inboxPreview = ((i?["preview"] as? [[String: Any]]) ?? []).compactMap {
            guard let t = $0["title"] as? String, let pa = $0["path"] as? String else { return nil }
            return InboxItem(title: t, path: pa)
        }

        let cc = d["command_center"] as? [String: Any]
        ccInstalled = cc?["installed"] as? Bool
        ccEnabled = cc?["enabled"] as? Bool
        ccVersion = (cc?["installed_version"] as? String) ?? "unknown"
        ccUpdateState = (cc?["update_state"] as? String) ?? "unknown"
        restartRecommended = (cc?["restart_recommended"] as? Bool) ?? false

        obsidianRunning = ((d["obsidian"] as? [String: Any])?["running"] as? Bool) ?? false
    }

    /// 사람이 읽는 한 줄. 모르는 것은 모른다고 말한다.
    var commandCenterLine: String {
        guard let installed = ccInstalled else { return "확인할 수 없음" }
        if !installed { return "설치되지 않음" }
        var bits = [ccVersion]
        if ccEnabled == false { bits.append("꺼짐") }
        switch ccUpdateState {
        case "update_available": bits.append("업데이트 있음")
        case "installed_newer":  bits.append("설치본이 더 새로움")
        default: break
        }
        if restartRecommended { bits.append("재시작 필요") }
        return bits.joined(separator: " · ")
    }
}
