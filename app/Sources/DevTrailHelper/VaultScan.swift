import Foundation

/// `lib/gen/scan.py` 의 Swift 판 — 볼트 진단기.
///
/// ⚠️ **쓰기는 하지 않는다.** 본문도 읽지 않는다 — frontmatter 블록까지만
///    읽는다. 개인 내용을 열지 않기 위해서다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum VaultScan {

    // ⚠️ python 의 SKIP_DIRS · TRACKED_FIELDS 를 **그대로** 옮긴다.
    //    2026-08-24 에 기억으로 적었다가 틀렸다 — TRACKED_FIELDS 에 없는
    //    next_action·stage 를 넣고 있던 category·scope 를 빠뜨렸다.
    //    이관에서는 짐작하지 않는다. 원본을 연다.
    static let skipDirs: Set<String> = [
        ".obsidian", ".trash", ".smart-env", ".claudian", ".copilot-index",
        ".git", ".DS_Store", "node_modules",
    ]
    static let maxRoleDepth = 3
    static let recentDays = 90
    static let trackedFields = ["type", "status", "tags", "created", "updated", "project",
                                "review_at", "category", "scope"]
    static let requiredPlugins = ["obsidian-shellcommands", "templater-obsidian",
                                  "dataview", "auto-note-mover"]
    static let recommendedPlugins = ["calendar", "omnisearch", "obsidian-linter", "homepage"]
    static let requiredCore = ["daily-notes", "templates", "properties"]

    static func run(_ args: [String]) -> Int32 {
        guard let arg = args.first else {
            print(JSON.object(JSONObject([("error", .string("볼트 경로가 필요합니다"))]))
                .pythonJSONCompact())
            return 2
        }
        let vault = (arg as NSString).standardizingPath.hasPrefix("/")
            ? (arg as NSString).standardizingPath
            : FileManager.default.currentDirectoryPath + "/" + arg
        let abs = (vault as NSString).standardizingPath

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: abs, isDirectory: &isDir),
              isDir.boolValue else {
            print(JSON.object(JSONObject([("error", .string("볼트 경로 없음: \(abs)"))]))
                .pythonJSONCompact())
            return 2
        }
        return scan(vault: abs,
                    treePath: args.count > 1 ? args[1] : "",
                    hkPath: args.count > 2 ? args[2] : "")
    }

    // 이하 구현은 ScanCore.swift 로 나눈다 — 한 파일이 400줄을 넘지 않게.
}
