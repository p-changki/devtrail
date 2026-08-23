import Foundation

/// `lib/gen/anm.py` 의 Swift 판 — Auto Note Mover 규칙 생성기.
///
/// ⚠️ **순서가 곧 계약이다.** 이 플러그인은 규칙을 위에서부터 훑어 '첫
///    매칭'에서 멈춘다. 2026-08-22 실물 QA 에서 project/* 가 type/devlog
///    보다 앞에 가는 바람에, 프로젝트 태그가 붙은 개발일지가 프로젝트
///    폴더로 끌려갔다 — 사용자 노트가 사라진 것처럼 보이는 사고다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum AutoNoteMover {

    /// 인자: <tree.json> <config.json> <profile.json> [<existing.json>]
    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data(
                "사용법: gen-anm <tree> <config> <profile> [<existing>]\n".utf8))
            return 2
        }
        let foreign = Py.envLines("DT_FOREIGN_FOLDERS")

        guard let treeV = JSONParser.parseFile(args[0]), case .object(let tree) = treeV else {
            FileHandle.standardError.write(Data(
                "트리 정의를 읽을 수 없습니다: \(args[0])\n".utf8))
            return 2
        }
        let cfg = obj(JSONParser.parseFile(args[1]))
        let profile = obj(JSONParser.parseFile(args[2]))
        let existing = args.count > 3 && !args[3].isEmpty
            ? obj(JSONParser.parseFile(args[3])) : JSONObject()

        var oldRules: [JSON] = []
        if case .array(let rs)? = existing["folder_tag_pattern"] { oldRules = rs }

        let (ours, excluded) = collectRules(tree: tree, cfg: cfg)

        // 사용자가 우리 규칙의 folder 를 고쳤다면 그 값을 존중한다.
        var oldByTag: [String: JSON] = [:]
        for r in oldRules {
            guard case .object(let o) = r else { continue }
            let t = Py.str(o["tag"])
            if !t.isEmpty { oldByTag[Py.lstripHash(t)] = r }
        }

        var ordered: [JSON] = []
        var skipped: [String] = []
        var ourTags = Set<String>()
        for rule in ours {
            ourTags.insert(rule.tag)
            if let kept = oldByTag[rule.tag] {
                skipped.append(rule.tag)      // 이미 라우팅 중이면 그들 것을 남긴다
                ordered.append(kept)
                continue
            }
            ordered.append(.object(JSONObject([
                ("folder", .string(rule.folder)),
                ("tag", .string("#\(rule.tag)")),
                ("pattern", .string("")),
            ])))
        }
        // ⚠️ kept 는 stderr 의 개수에만 쓰인다. python 과 같은 식으로 센다.
        let skippedSet = Set(skipped)
        let keptCount = ordered.filter { r in
            guard case .object(let o) = r else { return true }
            return !skippedSet.contains(Py.lstripHash(Py.str(o["tag"])))
        }.count

        // 우리가 모르는 규칙은 사용자 것이다. 순서를 바꾸지 않고 뒤에 붙인다.
        let foreignRules = oldRules.filter { r in
            guard case .object(let o) = r else { return true }
            return !ourTags.contains(Py.lstripHash(Py.str(o["tag"])))
        }

        let auto = obj(profile["automove"])
        var trigger = "Manual"
        if case .string(let t)? = auto["trigger"] { trigger = t }

        var oldExcluded: [String] = []
        if case .array(let es)? = existing["excluded_folder"] {
            for e in es {
                guard case .object(let o) = e else { continue }
                let f = Py.str(o["folder"])
                if !f.isEmpty { oldExcluded.append(f) }
            }
        }
        let ex = Py.dedup(
            oldExcluded + excluded + [".obsidian", ".trash"]
            + (Py.truthy(auto["exclude_foreign_folders"]) ? foreign : []))

        // ⚠️ dict(existing) 뒤 update — 이미 있던 키는 **자리를 지키고**
        //    값만 바뀐다. 새 키는 아래 순서대로 뒤에 붙는다.
        var merged = existing
        merged["trigger_auto_manual"] = .string(trigger)
        merged["use_regex_to_check_for_tags"] =
            .bool(Py.bool(existing["use_regex_to_check_for_tags"], false))
        merged["use_regex_to_check_for_excluded_folder"] =
            .bool(Py.bool(existing["use_regex_to_check_for_excluded_folder"], false))
        merged["statusBar_trigger_indicator"] =
            .bool(Py.bool(existing["statusBar_trigger_indicator"], true))
        merged["excluded_folder"] = .array(ex.map {
            .object(JSONObject([("folder", .string($0))]))
        })
        merged["folder_tag_pattern"] = .array(ordered + foreignRules)

        print(JSON.object(merged).pythonJSON())
        if !skipped.isEmpty {
            let head = skipped.prefix(5).joined(separator: ", ")
            let tail = skipped.count > 5 ? " …" : ""
            FileHandle.standardError.write(Data(
                "이미 라우팅 중이라 건너뛴 태그 \(skipped.count)개: \(head)\(tail)\n".utf8))
        }
        let note = "규칙 \(keptCount)개 추가 · 기존 \(oldRules.count)개 유지 · "
            + "제외 폴더 \(ex.count)개 · 트리거 \(trigger)\n"
        FileHandle.standardError.write(Data(note.utf8))
        return 0
    }

    // ── 규칙 수집 ────────────────────────────────────────────────────────────

    private struct Rule {
        let specificity: Int
        let tag: String
        let folder: String
    }

    /// 태그·폴더 이름이 되므로 파일명에 못 쓰는 문자가 있으면 프로젝트가 아니다.
    /// ADR 0001 D1a · D3.
    private static let badKeyChars = Set("*?[]/\\:<>|\"")

    private static func isProjectKey(_ key: String) -> Bool {
        if key.isEmpty || key.count > 64 { return false }
        return !key.contains(where: { badKeyChars.contains($0) })
    }

    private static func obj(_ v: JSON?) -> JSONObject {
        if case .object(let o)? = v { return o }
        return JSONObject()
    }

    private static func collectRules(tree: JSONObject, cfg: JSONObject)
        -> ([Rule], [String]) {
        var root = ""
        if case .object(let vault)? = cfg["vault"], case .string(let r)? = vault["root"] {
            root = r
        }
        let dirs = obj(cfg["dirs"])

        func resolve(_ key: String, _ defaultPath: String) -> String {
            let v = Py.str(dirs[key])
            return v.isEmpty ? defaultPath : v
        }
        func full(_ rel: String) -> String { root.isEmpty ? rel : "\(root)/\(rel)" }

        var rules: [Rule] = []
        var excluded: [String] = []

        var folders: [JSON] = []
        if case .array(let fs)? = tree["folders"] { folders = fs }

        for fv in folders {
            guard case .object(let f) = fv else { continue }
            let rel = resolve(Py.str(f["key"]), Py.str(f["path"]))
            // 자동 이동을 하지 않는 폴더는 규칙 대신 제외 목록으로 간다.
            if Py.truthy(f["no_automove"]) || Py.truthy(f["no_index"]) {
                excluded.append(full(rel))
            } else if Py.truthy(f["tag"]) {
                let tag = Py.str(f["tag"])
                rules.append(Rule(specificity: slashCount(tag), tag: tag, folder: full(rel)))
            }

            var children: [JSON] = []
            if case .array(let cs)? = f["children"] { children = cs }
            for cv in children {
                guard case .object(let c) = cv else { continue }
                let crel = resolve(Py.str(c["key"]), "\(rel)/\(Py.str(c["path"]))")
                // 부모가 제외면 자식도 제외된다.
                if Py.truthy(f["no_automove"]) { continue }
                if Py.truthy(c["tag"]) {
                    let tag = Py.str(c["tag"])
                    rules.append(Rule(specificity: slashCount(tag), tag: tag,
                                      folder: full(crel)))
                }
            }
        }

        // ⚠️ wildcard 키("acme-*")는 프로젝트가 아니라 PR 요약 섹션 매칭
        //    규칙이다. 거르지 않으면 Obsidian 태그에 쓸 수 없는 * 가 들어간
        //    죽은 규칙이 생기고, 폴더 이름에도 * 가 들어간다.
        let groups = obj(obj(cfg["github"])["project_groups"])
        let projRel = resolve("projects", "개발/프로젝트")
        for repo in Py.stableSorted(Py.dedup(groups.keys), by: Py.less)
        where isProjectKey(repo) {
            rules.append(Rule(specificity: -1, tag: "project/\(repo)",
                              folder: full("\(projRel)/\(repo)")))
        }

        // 구체성 내림차순, 같으면 태그 이름순. project/* 는 -1 이라 맨 뒤.
        let sorted = Py.stableSorted(rules) { a, b in
            if a.specificity != b.specificity { return a.specificity > b.specificity }
            return Py.less(a.tag, b.tag)
        }
        return (sorted, excluded)
    }

    /// python: `tag.count("/")`
    private static func slashCount(_ s: String) -> Int {
        s.reduce(0) { $1 == "/" ? $0 + 1 : $0 }
    }
}
