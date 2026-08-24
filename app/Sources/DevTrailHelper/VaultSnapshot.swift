import Foundation

/// `lib/snapshot.py` 의 Swift 판 — 볼트를 읽어 상태를 JSON 으로 낸다.
///
/// ⚠️ 집계 규칙은 `plugin/read-model.js` 의 `collect()` 에도 있다. **두 벌이다.**
///    `tests/test-snapshot.sh` 가 같은 볼트에서 두 구현을 실제로 돌려
///    비교한다 — 어긋나면 빨간불이다. 두 벌을 허용하는 결정은 그 계약
///    테스트가 있는 동안에만 유효하다 (ADR 0003).
///
/// ⚠️ **읽기만 한다.** 파일을 만들거나 고치지 않는다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum VaultSnapshot {

    static func run(_ args: [String]) -> Int32 {
        guard let raw = args.first,
              let parsed = JSONParser.parse(raw), case .object(let cfg) = parsed else {
            FileHandle.standardError.write(Data("사용법: gen-snapshot '<cfg-json>'\n".utf8))
            return 2
        }
        let root = Py.str(cfg["root"])
        var limit = 5
        if case .int(let n)? = cfg["limit"] { limit = n }
        else if case .string(let s)? = cfg["limit"], let n = Int(s) { limit = n }

        var today = Py.str(cfg["today"])
        if today.isEmpty { today = Self.todayString() }

        // ⚠️ today 가 이미 cfg 로 주입되는데 now_ms 만 시계를 직접 읽으면
        //    출력을 고정할 수 없다. 같은 방식으로 받는다.
        var nowMS = Int(Date().timeIntervalSince1970 * 1000)
        if case .int(let n)? = cfg["now_ms"] { nowMS = n }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir),
              isDir.boolValue else {
            // ⚠️ 없는 것을 0 으로 말하지 않는다. 세어 본 적이 없는 것과
            //    세어 보니 0 인 것은 다른 사실이다.
            print(JSON.object(JSONObject([("available", .bool(false))])).pythonJSONCompact(),
                  terminator: "")
            return 0
        }

        let c = collect(root: root, templatesRel: Py.str(cfg["templates_rel"]),
                        projectsRel: Py.str(cfg["projects_rel"]),
                        today: today, nowMS: nowMS)
        let devlog = Py.str(cfg["devlog_path"])
        let exists = !devlog.isEmpty && FileManager.default.fileExists(atPath: devlog)

        let openTasks: JSON = exists
            ? .int(countOpenTasks(devlog))
            : (devlog.isEmpty ? .string("unknown") : .int(0))

        let todayObj = JSONObject([
            ("date", .string(today)),
            ("devlog_exists", .bool(exists)),
            ("open_tasks", openTasks),
            // ⚠️ 경로를 돌려준다. 앱이 파일명 규칙을 한 벌 더 갖지 않게 —
            //    그 순간 규칙이 갈리고 "있는데 없다" 는 화면이 생긴다.
            ("devlog_path", devlog.isEmpty ? .null : .string(devlog)),
        ])

        let nextActions = c.projects.prefix(limit).filter { !$0.nextAction.isEmpty }.map {
            JSON.object(JSONObject([
                ("project", .string($0.name)),
                ("next_action", .string($0.nextAction)),
                ("stage", $0.stage.isEmpty ? .null : .string($0.stage)),
            ]))
        }

        var oldestAt: JSON = .null
        if let first = c.inbox.first {
            oldestAt = first.created.isEmpty
                ? .string(localDateString(first.mtime)) : .string(first.created)
        }

        let out = JSONObject([
            ("available", .bool(true)),
            ("today", .object(todayObj)),
            ("projects", .object(JSONObject([
                ("active_count", .int(c.projects.count)),
                ("next_actions", .array(nextActions)),
            ]))),
            ("inbox", .object(JSONObject([
                ("count", .int(c.inbox.count)),
                ("oldest_at", oldestAt),
                ("preview", .array(c.inbox.prefix(limit).map {
                    .object(JSONObject([("title", .string($0.title)),
                                        ("path", .string($0.path))]))
                })),
            ]))),
            ("notes", .object(JSONObject([
                ("total", .int(c.total)),
                ("this_week", .int(c.thisWeek)),
                ("trouble", .int(c.trouble)),
                ("overdue", .int(c.overdue.count)),
            ]))),
            ("recent", .array(c.recent.prefix(limit).map {
                .object(JSONObject([
                    ("title", .string($0.title)),
                    ("type", $0.type.isEmpty ? .null : .string($0.type)),
                    ("path", .string($0.path)),
                ]))
            })),
        ])
        print(JSON.object(out).pythonJSONCompact(), terminator: "")
        return 0
    }

    // ── 집계 ────────────────────────────────────────────────────────────────

    struct Project { let name: String; let stage: String; let nextAction: String
                     let path: String; let mtime: Int }
    struct Inbox { let title: String; let path: String; let created: String; let mtime: Int }
    struct Overdue { let path: String; let at: String }
    struct Recent { let title: String; let type: String; let path: String; let mtime: Int }
    struct Collected {
        let projects: [Project]; let inbox: [Inbox]; let overdue: [Overdue]
        let trouble: Int; let recent: [Recent]; let thisWeek: Int; let total: Int
    }

    static func collect(root: String, templatesRel: String, projectsRel: String,
                        today: String, nowMS: Int) -> Collected {
        var projects: [Project] = []
        var inbox: [Inbox] = []
        var overdue: [Overdue] = []
        var recent: [Recent] = []
        var trouble = 0
        var thisWeek = 0
        var total = 0
        let weekAgo = nowMS - 7 * 24 * 60 * 60 * 1000

        for (full, rel) in walk(root: root, templatesRel: templatesRel) {
            guard let at = try? FileManager.default.attributesOfItem(atPath: full) else { continue }
            total += 1
            let mtime = ms(at[.modificationDate] as? Date)
            // macOS 는 birthtime 이 있다. 없으면 ctime — 플러그인의
            // f.stat.ctime 과 같은 자리다.
            let ctime = ms((at[.creationDate] as? Date) ?? (at[.modificationDate] as? Date))
            if ctime >= weekAgo { thisWeek += 1 }

            let meta = readFrontmatter(full)
            let t = meta["type"] ?? ""
            let name = String((rel as NSString).lastPathComponent.dropLast(3))

            // draft 상태도 관리 대상이다. 숨기면 상태를 바꿀 입구도 사라진다.
            if t == "project-home" {
                let pname = projectName(meta, rel: rel, fallback: name, projectsRel: projectsRel)
                projects.append(Project(name: pname, stage: meta["stage"] ?? "",
                                        nextAction: meta["next_action"] ?? "",
                                        path: rel, mtime: mtime))
            }
            if t == "trouble" || t == "troubleshooting" { trouble += 1 }
            if meta["status"] == "inbox" {
                inbox.append(Inbox(title: name, path: rel,
                                   created: meta["created"] ?? "", mtime: mtime))
            }
            if let ra = meta["review_at"], !ra.isEmpty {
                let at10 = String(ra.prefix(10))
                if at10 <= today { overdue.append(Overdue(path: rel, at: at10)) }
            }
            recent.append(Recent(title: name, type: t, path: rel, mtime: mtime))
        }

        projects = Py.stableSorted(projects) { $0.mtime > $1.mtime }
        inbox = Py.stableSorted(inbox) { $0.mtime < $1.mtime }      // 오래된 것 먼저
        overdue = Py.stableSorted(overdue) { Py.less($0.at, $1.at) }
        recent = Py.stableSorted(recent) { $0.mtime > $1.mtime }

        return Collected(projects: projects, inbox: inbox, overdue: overdue,
                         trouble: trouble, recent: Array(recent.prefix(10)),
                         thisWeek: thisWeek, total: total)
    }

    /// project:가 있으면 그것을 쓰고, 없으면 projects 아래 첫 폴더를 쓴다.
    /// project-home이 docs/00-overview에 있어도 "00-overview"를 프로젝트명으로
    /// 오인하지 않게 한다.
    private static func projectName(_ meta: [String: String], rel: String, fallback: String,
                                    projectsRel: String) -> String {
        let explicit = (meta["project"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        let base = projectsRel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = base.isEmpty ? "" : base + "/"
        if !prefix.isEmpty && rel.hasPrefix(prefix) {
            let tail = String(rel.dropFirst(prefix.count))
            if let first = tail.split(separator: "/").first, !first.isEmpty {
                return String(first)
            }
        }
        let parent = ((rel as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return parent.isEmpty ? fallback : parent
    }

    /// python: `int(st.st_mtime * 1000)` — **버림**이지 반올림이 아니다.
    private static func ms(_ d: Date?) -> Int {
        guard let d else { return 0 }
        return Int(d.timeIntervalSince1970 * 1000)
    }

    // ── 걷기 ────────────────────────────────────────────────────────────────

    /// 플러그인의 `isUserNote` 와 같은 규칙.
    static func isUserNote(_ rel: String, _ templatesRel: String) -> Bool {
        let name = (rel as NSString).lastPathComponent
        if name.hasPrefix("_") { return false }
        if !templatesRel.isEmpty,
           rel == templatesRel || rel.hasPrefix(templatesRel + "/") { return false }
        return true
    }

    /// python 의 `os.walk` + 숨은 폴더 제외. 순서는 정렬해 고정한다.
    ///
    /// ⚠️ python 의 os.walk 는 파일시스템 순서를 따른다. 그대로 두면 골든이
    ///    기계마다 달라질 수 있어, **양쪽 다** 정렬한다 — python 쪽 출력은
    ///    어차피 mtime 으로 다시 정렬되므로 최종 결과는 같다.
    static func walk(root: String, templatesRel: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: root) else { return out }
        for case let sub as String in e {
            let name = (sub as NSString).lastPathComponent
            // ⚠️ **디렉터리만** 거른다 (2026-08-24 실물 QA).
            //
            //    python 도 `dirs[:] = [d for d in dirs if not d.startswith('.')]`
            //    로 디렉터리 목록만 걸러낸다.
            //
            //    그리고 skipDescendants() 를 파일에 부르면 지금 훑고 있던
            //    디렉터리가 통째로 잘린다 — `.DS_Store` 하나로 그 폴더의
            //    노트가 전부 사라졌다. ScanCore 와 같은 결함이었다.
            var isDirEntry: ObjCBool = false
            let entryPath = (root as NSString).appendingPathComponent(sub)
            let entryIsDir = fm.fileExists(atPath: entryPath, isDirectory: &isDirEntry)
                && isDirEntry.boolValue
            if entryIsDir, name.hasPrefix(".") {
                e.skipDescendants()
                continue
            }
            guard sub.hasSuffix(".md") else { continue }
            var isDir: ObjCBool = false
            let full = (root as NSString).appendingPathComponent(sub)
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            if !isUserNote(sub, templatesRel) { continue }
            out.append((full, sub))
        }
        return out
    }

    // ── frontmatter ─────────────────────────────────────────────────────────

    /// 필요한 **스칼라 키만** 읽는다.
    ///
    /// ⚠️ YAML 파서를 쓰지 않는다 — 의존성 때문이 아니라, Obsidian 이 읽는
    ///    것과 다르게 해석할 위험이 더 크다. 우리가 보는 키는 전부 한 줄
    ///    스칼라이므로 그만 읽는다. 리스트(tags)는 보지 않는다.
    static func readFrontmatter(_ path: String) -> [String: String] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [:] }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: 4096)
        guard let head = String(data: data, encoding: .utf8) else { return [:] }

        // python: `\A---\r?\n(.*?)\r?\n---\r?\n` — 앞머리의 --- 블록 하나뿐.
        let norm = head.replacingOccurrences(of: "\r\n", with: "\n")
        guard norm.hasPrefix("---\n") else { return [:] }
        let rest = String(norm.dropFirst(4))
        guard let end = rest.range(of: "\n---\n") else { return [:] }
        let body = String(rest[rest.startIndex..<end.lowerBound])

        var out: [String: String] = [:]
        for line in body.components(separatedBy: "\n") {
            if let f = line.first, f == " " || f == "\t" || f == "-" { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let k = Py.strip(String(line[line.startIndex..<colon]))
            var v = Py.strip(String(line[line.index(after: colon)...]))
            // 따옴표는 벗긴다. Obsidian 도 그렇게 읽는다.
            if v.count >= 2, let a = v.first, let b = v.last, a == b, a == "\"" || a == "'" {
                v = String(v.dropFirst().dropLast())
            }
            out[k] = v
        }
        return out
    }

    /// 미완료이고 **내용이 있는** 체크박스만.
    ///
    /// ⚠️ 템플릿은 `- [ ]` 를 자리표시로 넣는다. 그것을 세면 아무것도 안 쓴
    ///    날에 "할 일 3개" 라고 말하게 된다.
    static func countOpenTasks(_ path: String) -> Int {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        var n = 0
        for line in raw.components(separatedBy: "\n") {
            // python: `^\s*- \[ \]\s*(.*)$` 이고 group(1).strip() 이 있어야 한다.
            let t = line.drop(while: { $0 == " " || $0 == "\t" })
            guard t.hasPrefix("- [ ]") else { continue }
            if !Py.strip(String(t.dropFirst(5))).isEmpty { n += 1 }
        }
        return n
    }

    // ── 시각 ────────────────────────────────────────────────────────────────

    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = pattern
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// python: `time.strftime('%Y-%m-%d')` — **현지 시각**.
    static func todayString() -> String { fmt("yyyy-MM-dd").string(from: Date()) }

    /// python: `time.strftime('%Y-%m-%d', time.localtime(ms / 1000))`
    static func localDateString(_ ms: Int) -> String {
        fmt("yyyy-MM-dd").string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
