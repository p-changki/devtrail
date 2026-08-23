import Foundation

/// `lib/gen/smartenv.py` 의 Swift 판 — Smart Connections(RAG) 제외 설정.
///
/// ⚠️ 이것은 **재작성이 아니라 이관**이다. 목표는 "더 나은 출력" 이 아니라
///    **같은 출력**이다. tests/golden/gen/smartenv-*.txt 를 바이트로 통과해야
///    한다. 개선하고 싶은 곳이 보여도 여기서 하지 않는다 — 그건 이관이
///    끝난 뒤 별도로, 골든을 함께 바꾸며 한다 (ADR 0006 M1·M2).
enum SmartEnv {

    /// 인자: <tree.json> <config.json> <templates_dir> [<existing.json>]
    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data(
                "사용법: gen-smartenv <tree> <config> <templates_dir> [<existing>]\n".utf8))
            return 2
        }
        let treePath = args[0]
        let cfgPath = args[1]
        let templatesDir = args[2]
        let existingPath = args.count > 3 ? args[3] : ""

        guard let tree = JSONParser.parseFile(treePath), case .object(let treeObj) = tree else {
            FileHandle.standardError.write(Data(
                "트리 정의를 읽을 수 없습니다: \(treePath)\n".utf8))
            return 2
        }

        var cfgObj = JSONObject()
        if let cfg = JSONParser.parseFile(cfgPath), case .object(let o) = cfg { cfgObj = o }

        var root = ""
        if case .object(let vault)? = cfgObj["vault"], case .string(let r)? = vault["root"] {
            root = r
        }
        var dirs = JSONObject()
        if case .object(let d)? = cfgObj["dirs"] { dirs = d }

        func full(_ key: String, _ defaultPath: String) -> String {
            var rel = defaultPath
            if case .string(let v)? = dirs[key], !v.isEmpty { rel = v }
            return root.isEmpty ? rel : "\(root)/\(rel)"
        }

        // ⚠️ 두 번 도는 순서를 지킨다. python 은 no_index 를 먼저 전부 훑고,
        //    그다음 personal 을 훑는다. 한 번에 합치면 순서가 달라진다.
        var folders: [JSON] = []
        if case .array(let fs)? = treeObj["folders"] { folders = fs }

        var exclFolders: [String] = []
        for f in folders {
            guard case .object(let o) = f else { continue }
            if case .bool(true)? = o["no_index"] {
                exclFolders.append(full(str(o["key"]), str(o["path"])))
            }
        }
        for f in folders {
            guard case .object(let o) = f else { continue }
            if case .string("personal")? = o["module"] {
                exclFolders.append(full(str(o["key"]), str(o["path"])))
            }
        }

        let foreign = (ProcessInfo.processInfo.environment["DT_FOREIGN_FOLDERS"] ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        exclFolders += foreign

        // 헤딩 제외 — 템플릿에서 만든다.
        var exclHeadings: [String] = []
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: templatesDir, isDirectory: &isDir),
           isDir.boolValue,
           let names = try? FileManager.default.contentsOfDirectory(atPath: templatesDir) {
            // ⚠️ python 의 sorted(os.listdir(...)) 와 같아야 한다.
            //    Swift 의 기본 < 는 유니코드 스칼라 순 — python 도 같다.
            for name in names.sorted() where name.hasSuffix(".md") {
                for h in headingsWithDataview((templatesDir as NSString)
                    .appendingPathComponent(name)) where !exclHeadings.contains(h) {
                    exclHeadings.append(h)
                }
            }
        }

        var existing = JSONObject()
        if !existingPath.isEmpty,
           let e = JSONParser.parseFile(existingPath), case .object(let o) = e { existing = o }

        var sources = JSONObject()
        if case .object(let s)? = existing["smart_sources"] { sources = s }

        let oldFolders = splitCSV(str(sources["folder_exclusions"]))
        let oldHeads = splitCSV(str(sources["excluded_headings"]))

        let mergedFolders = dedup(oldFolders.map(trim) + exclFolders)
        let mergedHeads = dedup(oldHeads.map(trim) + exclHeadings)

        sources["folder_exclusions"] = .string(mergedFolders.joined(separator: ","))
        sources["excluded_headings"] = .string(mergedHeads.joined(separator: ","))
        sources.setDefault("min_chars", .int(200))

        var out = existing
        out["smart_sources"] = .object(sources)
        out.setDefault("is_obsidian_vault", .bool(true))

        print(JSON.object(out).pythonJSON())
        let note = "폴더 제외 \(mergedFolders.count)개 · 헤딩 제외 \(mergedHeads.count)개 "
            + "(템플릿에서 \(exclHeadings.count)개 생성)\n"
        FileHandle.standardError.write(Data(note.utf8))
        return 0
    }

    // ── 부품 ────────────────────────────────────────────────────────────────

    private static func str(_ v: JSON?) -> String {
        if case .string(let s)? = v { return s }
        return ""
    }

    /// python: `[x for x in s.split(",") if x.strip()]`
    private static func splitCSV(_ s: String) -> [String] {
        s.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !trim($0).isEmpty }
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// python: `list(dict.fromkeys(xs))` — 순서를 지키며 중복 제거.
    private static func dedup(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in xs where !seen.contains(x) {
            seen.insert(x)
            out.append(x)
        }
        return out
    }

    /// Dataview 블록이 들어 있는 헤딩 제목.
    ///
    /// ⚠️ python 과 같은 규칙: 헤딩을 만나면 현재 헤딩을 바꾸고 **그 줄은
    ///    dataview 검사를 하지 않는다**(continue). 그 뒤 줄에서 dataview 를
    ///    만나면 현재 헤딩을 담는다.
    static func headingsWithDataview(_ path: String) -> [String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var found: [String] = []
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if let h = heading(line) {
                current = h
                continue
            }
            if let c = current, line.range(of: "```dataview", options: .caseInsensitive) != nil {
                if !found.contains(c) { found.append(c) }
            }
        }
        return found
    }

    /// `^(#{1,6})\s+(.*)$` 의 두 번째 그룹을 strip 한 것.
    private static func heading(_ line: String) -> String? {
        var hashes = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", hashes < 7 {
            hashes += 1
            idx = line.index(after: idx)
        }
        guard hashes >= 1, hashes <= 6, idx < line.endIndex else { return nil }
        // \s+ 가 최소 하나 있어야 한다.
        guard line[idx].isWhitespace else { return nil }
        while idx < line.endIndex, line[idx].isWhitespace { idx = line.index(after: idx) }
        return trim(String(line[idx...]))
    }
}
