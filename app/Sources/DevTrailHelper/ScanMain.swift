import Foundation

extension VaultScan {

    /// 플러그인 준비도 · 충돌 · RAG 상태. `.obsidian` 이 없으면 신규 볼트다.
    static func analyseObsidian(vault: String, wantedKeys: [String],
                                wantedFolders: [String]) -> JSONObject {
        let fm = FileManager.default
        let dot = (vault as NSString).appendingPathComponent(".obsidian")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dot, isDirectory: &isDir), isDir.boolValue else {
            return JSONObject([
                ("present", .bool(false)),
                ("_note", .string("볼트를 Obsidian 에서 한 번도 열지 않았다")),
            ])
        }

        func j(_ rel: String) -> JSON? { JSONParser.parseFile((dot as NSString).appendingPathComponent(rel)) }
        var community: [String] = []
        if case .array(let a)? = j("community-plugins.json") {
            community = a.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }
        let core = obj(j("core-plugins.json"))
        let hotkeys = obj(j("hotkeys.json"))
        let app = obj(j("app.json"))
        let anm = obj(j("plugins/auto-note-mover/data.json"))
        let tpl = obj(j("plugins/templater-obsidian/data.json"))
        let linterPath = (dot as NSString).appendingPathComponent("plugins/obsidian-linter/data.json")

        // 단축키 점유: 우리가 쓰려는 조합이 이미 배정돼 있는가.
        var occupied: [String: String] = [:]
        for cmd in hotkeys.keys {
            guard case .array(let binds)? = hotkeys[cmd] else { continue }
            for b in binds {
                guard case .object(let o) = b else { continue }
                var mods: [String] = []
                if case .array(let ms)? = o["modifiers"] {
                    mods = ms.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                }
                var key = ""
                if case .string(let k)? = o["key"] { key = k }
                else if case .int(let n)? = o["key"] { key = String(n) }
                occupied[Py.stableSorted(mods, by: Py.less).joined(separator: "+") + "+" + key] = cmd
            }
        }
        let conflictsHotkey: [JSON] = wantedKeys.compactMap { c in
            guard let by = occupied[c] else { return nil }
            return .object(JSONObject([("combo", .string(c)), ("taken_by", .string(by))]))
        }

        // 폴더 이름 충돌: 우리가 만들 경로가 이미 존재하는가.
        let conflictsFolder: [JSON] = wantedFolders.compactMap { f in
            var d: ObjCBool = false
            let p = (vault as NSString).appendingPathComponent(f)
            return (fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue)
                ? .string(f) : nil
        }

        let smartEnv = (vault as NSString).appendingPathComponent(".smart-env")
        var smartIsDir: ObjCBool = false
        let smartExists = fm.fileExists(atPath: smartEnv, isDirectory: &smartIsDir)
            && smartIsDir.boolValue
        let smartCfg = obj(JSONParser.parseFile(
            (smartEnv as NSString).appendingPathComponent("smart_env.json")))
        let excluded = Py.str(obj(smartCfg["smart_sources"])["folder_exclusions"])

        func count(_ o: JSONObject, _ k: String) -> Int {
            if case .array(let a)? = o[k] { return a.count }
            return 0
        }

        return JSONObject([
            ("present", .bool(true)),
            ("plugins", .object(JSONObject([
                ("community_enabled", .int(community.count)),
                ("required_missing", .array(requiredPlugins.filter { !community.contains($0) }
                    .map { .string($0) })),
                ("recommended_missing", .array(recommendedPlugins.filter { !community.contains($0) }
                    .map { .string($0) })),
                ("core_missing", .array(requiredCore.filter { !Py.truthy(core[$0]) }
                    .map { .string($0) })),
                ("zk_prefixer_on", .bool(Py.truthy(core["zk-prefixer"]))),
            ]))),
            ("conflicts", .object(JSONObject([
                ("hotkeys", .array(conflictsHotkey)),
                ("folders", .array(conflictsFolder)),
                ("auto_note_mover_rules", .int(count(anm, "folder_tag_pattern"))),
                ("auto_note_mover_trigger", anm["trigger_auto_manual"] ?? .null),
                ("templater_folder_templates", .int(count(tpl, "folder_templates"))),
                ("linter_present", .bool(fm.fileExists(atPath: linterPath))),
                ("always_update_links", app["alwaysUpdateLinks"] ?? .null),
                ("attachment_folder", app["attachmentFolderPath"] ?? .null),
            ]))),
            ("rag", .object(JSONObject([
                ("smart_connections", .bool(community.contains("smart-connections"))),
                ("index_bytes", .int(smartExists ? dirSize(smartEnv) : 0)),
                ("excluded_configured", .bool(!excluded.isEmpty)),
            ]))),
        ])
    }

    static func obj(_ v: JSON?) -> JSONObject {
        if case .object(let o)? = v { return o }
        return JSONObject()
    }

    static func dirSize(_ path: String) -> Int {
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: path) else { return 0 }
        var total = 0
        for case let sub as String in e {
            let p = (path as NSString).appendingPathComponent(sub)
            if let at = try? fm.attributesOfItem(atPath: p),
               (at[.type] as? FileAttributeType) == .typeRegular,
               let sz = at[.size] as? Int {
                total += sz
            }
        }
        return total
    }

    // ── 본체 ────────────────────────────────────────────────────────────────

    static func scan(vault: String, treePath: String, hkPath: String) -> Int32 {
        var wantedFolders: [String] = []
        if !treePath.isEmpty, case .object(let tree)? = JSONParser.parseFile(treePath),
           case .array(let fs)? = tree["folders"] {
            for fv in fs {
                guard case .object(let f) = fv else { continue }
                let path = Py.str(f["path"])
                wantedFolders.append(path)
                if case .array(let cs)? = f["children"] {
                    for cv in cs {
                        guard case .object(let c) = cv else { continue }
                        wantedFolders.append(path + "/" + Py.str(c["path"]))
                    }
                }
            }
        }
        var wantedKeys: [String] = []
        if !hkPath.isEmpty, case .object(let hk)? = JSONParser.parseFile(hkPath) {
            for group in ["templater", "shellcommands", "plugin"] {
                guard case .array(let bs)? = hk[group] else { continue }
                for bv in bs {
                    guard case .object(let b) = bv else { continue }
                    var mods: [String] = []
                    if case .array(let ms)? = b["modifiers"] {
                        mods = ms.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                    }
                    wantedKeys.append(
                        Py.stableSorted(mods, by: Py.less).joined(separator: "+")
                        + "+" + Py.str(b["key"]))
                }
            }
        }

        // ⚠️ files_by_dir 는 python 의 dict — **삽입 순서**를 지킨다.
        var dirOrder: [String] = []
        var byDir: [String: [String]] = [:]
        var total = 0
        var fmPresent = 0
        var fieldKey = Counter()
        var fieldVal = Counter()
        var tagCounter = Counter()
        var customFields = Counter()

        for (full, rel) in walkMD(vault) {
            total += 1
            var d = (rel as NSString).deletingLastPathComponent
            if d.isEmpty { d = "." }
            if byDir[d] == nil { dirOrder.append(d) }
            byDir[d, default: []].append(full)

            guard let fields = readFrontmatter(full) else { continue }
            fmPresent += 1

            for (k, v) in fields {
                if trackedFields.contains(k) {
                    fieldKey.add(k)
                    if fieldHasValue(v) { fieldVal.add(k) }
                } else {
                    customFields.add(k)
                }
            }
            for t in extractTags(fields) { tagCounter.add(t) }
            if fieldHasValue(fields.first(where: { $0.0 == "type" })?.1 ?? .str("")) {
                // 값이 없는 type 은 세지 않는다.
            }
        }

        func pct(_ x: Int) -> Double { total > 0 ? round1(Double(x) * 100 / Double(total)) : 0.0 }

        let typeTags = tagCounter.pairs().filter { $0.0.hasPrefix("type/") }
            .reduce(0) { $0 + $1.1 }
        let allTags = tagCounter.total

        var fieldsObj = JSONObject()
        for k in trackedFields {
            fieldsObj[k] = .object(JSONObject([
                ("with_key", .int(fieldKey[k])),
                ("with_value", .int(fieldVal[k])),
                ("key_pct", .double(pct(fieldKey[k]))),
                ("value_pct", .double(pct(fieldVal[k]))),
            ]))
        }

        let folders = analyseFolders(
            vault: vault,
            filesByDir: dirOrder.map { ($0, byDir[$0]!) },
            now: nowSeconds())

        let out = JSONObject([
            ("vault", .string(vault)),
            ("scale", .object(JSONObject([
                ("notes", .int(total)),
                ("folders", .int(dirOrder.count)),
                ("frontmatter_notes", .int(fmPresent)),
                ("frontmatter_pct", .double(pct(fmPresent))),
            ]))),
            ("fields", .object(fieldsObj)),
            ("custom_fields", .array(customFields.mostCommon(10).map {
                .array([.string($0.0), .int($0.1)])
            })),
            ("tags", .object(JSONObject([
                ("total_uses", .int(allTags)),
                ("type_namespaced", .int(typeTags)),
                ("type_pct", .double(allTags > 0
                    ? round1(Double(typeTags) * 100 / Double(allTags)) : 0.0)),
                ("top", .array(tagCounter.mostCommon(20).map {
                    .array([.string($0.0), .int($0.1)])
                })),
            ]))),
            ("folders", .array(folders.map { f in
                .object(JSONObject([
                    ("path", .string(f.path)),
                    ("notes", .int(f.notes)),
                    ("subfolders", .int(f.subfolders)),
                    ("depth", .int(f.depth)),
                    ("dated_ratio", f.notes > 0 ? .double(f.datedRatio) : .int(0)),
                    ("last_modified", .int(f.lastModified)),
                    ("role_candidates", .object(JSONObject(
                        f.roles.map { ($0.0, JSON.double($0.1)) }))),
                ]))
            })),
            ("obsidian", .object(analyseObsidian(
                vault: vault, wantedKeys: wantedKeys, wantedFolders: wantedFolders))),
        ])
        // ⚠️ scan 은 **indent=2** 로 낸다. 에러 두 줄만 compact 다 —
        //    같은 파일 안에서 형식이 다르니 각각 맞춰야 한다.
        print(JSON.object(out).pythonJSON())
        return 0
    }

    /// 현재 시각(초). `DT_NOW` 로 고정할 수 있다 — 계약 테스트용.
    static func nowSeconds() -> Int {
        if let v = ProcessInfo.processInfo.environment["DT_NOW"], let n = Int(v) { return n }
        return Int(Date().timeIntervalSince1970)
    }
}
