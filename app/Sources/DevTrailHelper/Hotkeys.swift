import Foundation

/// `lib/gen/hotkeys.py` 의 Swift 판 — 단축키 · Templater 폴더매핑 · daily-notes.
///
/// ⚠️ 정적 hotkeys.json 을 복사하면 안 된다. Templater 커맨드 ID 안에 볼트
///    경로가 통째로 들어간다: `templater-obsidian:create-<루트>/<템플릿폴더>/…`
///    사용자가 루트를 다른 이름으로 정하면 템플릿 단축키가 전부 죽는다 —
///    설치는 성공했는데 단축키만 조용히 안 먹는 종류다.
///
/// ⚠️ 이미 쓰이는 키는 빼앗지 않는다. fallback_keys 에서 빈 키를 찾아
///    재배정하고, 그것도 없으면 배정하지 않는다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum Hotkeys {

    /// 인자: <what> <spec.json> <paths.json> [<existing.json>] [<shell_ids.json>]
    static func run(_ args: [String]) -> Int32 {
        guard let what = args.first else {
            FileHandle.standardError.write(Data("사용법: gen-hotkeys <what> …\n".utf8))
            return 2
        }
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data(
                "사용법: gen-hotkeys <hotkeys|templater|daily> <spec> <paths> [<existing>] [<ids>]\n".utf8))
            return 2
        }
        let spec = obj(JSONParser.parseFile(args[1]))
        let pathsJSON = obj(JSONParser.parseFile(args[2]))
        let existing = args.count > 3 && !args[3].isEmpty
            ? obj(JSONParser.parseFile(args[3])) : JSONObject()

        let paths = obj(pathsJSON["paths"])
        var tmplRel = Py.str(paths["templates"])
        if tmplRel.isEmpty { tmplRel = I18n.lang == "en" ? "Templates" : "템플릿" }

        // 실제로 배포된 템플릿 파일명. 없으면 확인을 건너뛴다.
        var have: Set<String>?
        let tdir = ProcessInfo.processInfo.environment["DT_TEMPLATES_DIR"] ?? ""
        var isDir: ObjCBool = false
        if !tdir.isEmpty,
           FileManager.default.fileExists(atPath: tdir, isDirectory: &isDir), isDir.boolValue,
           let names = try? FileManager.default.contentsOfDirectory(atPath: tdir) {
            have = Set(names.filter { $0.hasSuffix(".md") })
        }

        switch what {
        case "templater":
            let (out, added) = buildTemplater(tmplRel: tmplRel, paths: paths,
                                              existing: existing, have: have, spec: spec)
            print(JSON.object(out).pythonJSON())
            var total = 0
            if case .array(let ft)? = out["folder_templates"] { total = ft.count }
            warn("폴더 매핑 \(added)개 추가 · 전체 \(total)개")
            return 0

        case "daily":
            var out = existing
            var folder = Py.str(paths["devlog"])
            if folder.isEmpty { folder = Py.str(out["folder"]) }
            out["folder"] = .string(folder)
            out["template"] = .string("\(tmplRel)/개발일지양식.md")
            print(JSON.object(out).pythonJSON())
            warn("데일리노트 → \(folder)")
            return 0

        case "hotkeys":
            let shellIds = args.count > 4 && !args[4].isEmpty
                ? obj(JSONParser.parseFile(args[4])) : JSONObject()
            let r = buildHotkeys(spec: spec, tmplRel: tmplRel, existing: existing,
                                 shellIds: shellIds, have: have)
            print(JSON.object(r.out).pythonJSON())
            warn(I18n.t("hk.assigned", ["a": "\(r.assigned)", "r": "\(r.remapped.count)",
                                        "s": "\(r.skipped.count)"]))
            for m in r.remapped {
                warn(I18n.t("hk.remapped", ["old": m.from, "new": m.to]))
            }
            for s in r.skipped {
                warn("  건너뜀 \(s.combo) (이미 사용: \(s.by))")
            }
            for c in r.clashes {
                warn("  ⚠️  \(c.combo) 를 두 명령이 씁니다: \(c.a) · \(c.b)")
                warn("     Obsidian 설정 → 단축키에서 한쪽을 바꾸세요. "
                     + "고치지 않는 이유는 어느 쪽이 맞는지 우리가 모르기 때문입니다.")
            }
            return 0

        default:
            warn("알 수 없는 대상: \(what)")
            return 2
        }
    }

    // ── 단축키 조립 ─────────────────────────────────────────────────────────

    struct Remap { let from: String; let to: String }
    struct Skip { let combo: String; let by: String }
    struct Clash { let combo: String; let a: String; let b: String }
    struct Result {
        let out: JSONObject
        let assigned: Int
        let remapped: [Remap]
        let skipped: [Skip]
        let clashes: [Clash]
    }

    /// python: `"+".join(sorted(mods)) + "+" + key`
    static func combo(_ mods: [String], _ key: String) -> String {
        Py.stableSorted(mods, by: Py.less).joined(separator: "+") + "+" + key
    }

    private static func modsOf(_ v: JSON?) -> [String] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    /// python: `str(b.get("key", ""))`
    private static func keyOf(_ v: JSON?) -> String {
        switch v {
        case .some(.string(let s)): return s
        case .some(.int(let i)): return String(i)
        case .none: return ""
        default: return Py.str(v)
        }
    }

    static func buildHotkeys(spec: JSONObject, tmplRel: String, existing: JSONObject,
                             shellIds: JSONObject, have: Set<String>?) -> Result {
        // ⚠️ 삽입 순서대로 훑어야 한다. 같은 조합을 두 명령이 쓰면
        //    **나중 것**이 occupied 에 남는다 — python 의 dict 순회와 같다.
        var occupied: [String: String] = [:]
        for cmd in existing.keys {
            guard case .array(let binds)? = existing[cmd] else { continue }
            for b in binds {
                guard case .object(let o) = b else { continue }
                occupied[combo(modsOf(o["modifiers"]), keyOf(o["key"]))] = cmd
            }
        }

        var out = existing
        var pool: [String] = []
        if case .array(let fk)? = spec["fallback_keys"] {
            pool = fk.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }
        var assigned = 0
        var remapped: [Remap] = []
        var skipped: [Skip] = []

        func place(_ cmdId: String, _ mods: [String], _ key: String) {
            // ⚠️ 이미 우리가 배정한 커맨드면 그대로 둔다. 이걸 안 하면
            //    재실행할 때마다 '남이 쓰는 키' 로 보고 새 키를 소모해
            //    fallback 이 금방 고갈된다(실제로 5개가 배정되지 못했다).
            if existing[cmdId] != nil {
                assigned += 1                       // python: ("유지")
                return
            }
            let c = combo(mods, key)
            if let by = occupied[c], by != cmdId {
                for alt in pool {
                    let ac = combo(mods, alt)
                    if occupied[ac] == nil {
                        pool.removeAll { $0 == alt }
                        out[cmdId] = .array([.object(JSONObject([
                            ("modifiers", .array(mods.map { .string($0) })),
                            ("key", .string(alt)),
                        ]))])
                        occupied[ac] = cmdId
                        remapped.append(Remap(from: c, to: ac))
                        return
                    }
                }
                skipped.append(Skip(combo: c, by: by))
                return
            }
            out[cmdId] = .array([.object(JSONObject([
                ("modifiers", .array(mods.map { .string($0) })),
                ("key", .string(key)),
            ]))])
            occupied[c] = cmdId
            assigned += 1
        }

        if case .array(let ts)? = spec["templater"] {
            for tv in ts {
                guard case .object(let t) = tv else { continue }
                // 아직 배포하지 않은 템플릿에는 단축키를 걸지 않는다.
                let name = tplName(t)
                if let have, !have.contains(name) { continue }
                place("templater-obsidian:create-\(tmplRel)/\(name)",
                      modsOf(t["modifiers"]), Py.str(t["key"]))
            }
        }

        if case .array(let scs)? = spec["shellcommands"] {
            for sv in scs {
                guard case .object(let sc) = sv else { continue }
                let real = Py.str(shellIds[Py.str(sc["id"])])
                if real.isEmpty { continue }   // 아직 셸커맨드가 병합되지 않았다
                place("obsidian-shellcommands:shell-command-\(real)",
                      modsOf(sc["modifiers"]), Py.str(sc["key"]))
            }
        }

        if case .array(let ps)? = spec["plugin"] {
            for pv in ps {
                guard case .object(let p) = pv else { continue }
                place(Py.str(p["command"]), modsOf(p["modifiers"]), Py.str(p["key"]))
            }
        }

        // ⚠️ 우리가 먼저 배정한 키를 사용자가 나중에 다른 명령에 줬을 수 있다.
        //    place() 는 '이미 우리 것' 이라 유지하고 넘어가므로 그 겹침을 못 본다.
        //    고쳐주지는 않는다 — 사용자가 일부러 그랬을 수 있다 — 대신 말한다.
        var seen: [String: String] = [:]
        var clashes: [Clash] = []
        for cmd in out.keys {
            guard case .array(let binds)? = out[cmd] else { continue }
            for b in binds {
                guard case .object(let o) = b else { continue }
                let c = combo(modsOf(o["modifiers"]), keyOf(o["key"]))
                if let first = seen[c], first != cmd {
                    clashes.append(Clash(combo: c, a: first, b: cmd))
                } else {
                    seen[c] = cmd
                }
            }
        }

        return Result(out: out, assigned: assigned, remapped: remapped,
                      skipped: skipped, clashes: clashes)
    }

    /// 언어에 맞는 템플릿 파일명.
    ///
    /// ⚠️ 파일명이 언어를 탄다. 한국어 이름을 그대로 쓰면 영어 볼트에서
    ///    없는 파일을 가리켜 "템플릿 없음" 이 뜬다.
    static func tplName(_ entry: JSONObject) -> String {
        if I18n.lang == "en" {
            let en = Py.str(entry["template_en"])
            if !en.isEmpty { return en }
        }
        return Py.str(entry["template"])
    }

    private static func obj(_ v: JSON?) -> JSONObject {
        if case .object(let o)? = v { return o }
        return JSONObject()
    }

    private static func warn(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}
