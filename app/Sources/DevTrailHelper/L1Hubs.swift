import Foundation

/// `lib/gen/hubs.py` 의 Swift 판 — L1 대시보드 · 일일 체크인 생성기.
///
/// ⚠️ 생성기 중 **유일하게 디렉터리에 파일을 쓴다.** 나머지 일곱은 stdout
///    으로만 낸다. 그리고 **이미 있는 파일은 건드리지 않는다** — 사용자가
///    고쳤을 수 있다.
///
/// ⚠️ `build_area` 는 python 에도 있지만 **아무도 부르지 않는다**(죽은 코드).
///    옮기지 않는다 — 도달하지 않는 코드를 옮기면 유지 비용만 늘고, 그것이
///    맞는지 확인할 방법도 없다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum L1Hubs {

    /// 인자: <paths.json> <config.json> <scan.json> <outdir>
    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 4 else {
            FileHandle.standardError.write(Data(
                "사용법: gen-hubs <paths> <config> <scan> <outdir>\n".utf8))
            return 2
        }
        var P = obj(obj(JSONParser.parseFile(args[0]))["paths"])
        let cfg = obj(JSONParser.parseFile(args[1]))
        let scan = obj(JSONParser.parseFile(args[2]))
        let outdir = args[3]
        let date = ProcessInfo.processInfo.environment["DT_DATE"] ?? ""

        var root = ""
        if case .object(let vault)? = cfg["vault"], case .string(let r)? = vault["root"] {
            root = r
        }
        P["_root"] = .string(root)

        // 커버리지 — scan 의 fields.<k>.value_pct
        func cov(_ k: String) -> Double {
            let fields = obj(scan["fields"])
            let f = obj(fields[k])
            switch f["value_pct"] {
            case .some(.double(let d)): return d
            case .some(.int(let i)): return Double(i)
            default: return 0
            }
        }

        try? FileManager.default.createDirectory(atPath: outdir,
                                                 withIntermediateDirectories: true)
        var made: [String] = []

        func write(_ name: String, _ body: String) {
            let path = outdir + "/" + name
            // ⚠️ 이미 있으면 **건드리지 않는다.** 사용자가 고쳤을 수 있다.
            if Posix.exists(path) { return }
            guard Posix.write(path: path, contents: body) else { return }
            made.append(name)
        }

        write(I18n.t("l1.dashboard") + ".md",
              buildDashboard(P: P, date: date, covStatus: cov("status"), cfg: cfg))
        write(I18n.t("l1.checkin") + ".md", buildCheckin(P: P, date: date, cfg: cfg))

        print(made.joined(separator: "\n"))
        FileHandle.standardError.write(Data("L1 \(made.count)\n".utf8))
        return 0
    }

    // ── 부품 ────────────────────────────────────────────────────────────────

    static func obj(_ v: JSON?) -> JSONObject {
        if case .object(let o)? = v { return o }
        return JSONObject()
    }

    static func fm(_ pairs: [(String, String)]) -> String {
        var lines = ["---", "tags:", "  - type/moc", "type: moc"]
        for (k, v) in pairs { lines.append("\(k): \(v)") }
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    /// 이동 버튼. `devtrail.css` 의 `.dt-nav` / `.dt-btn` 을 쓴다.
    static func nav(_ items: [(String, String)]) -> String {
        var out = ["<div class=\"dt-nav\">"]
        for (label, target) in items {
            out.append("  <a class=\"dt-btn internal-link\" data-href=\"\(target)\" "
                       + "href=\"\(target)\">\(label)</a>")
        }
        out.append("</div>")
        return out.joined(separator: "\n")
    }

    static func dv(_ body: String) -> String {
        "```dataview\n" + Py.strip(body) + "\n```"
    }

    /// 개발일지 파일명에서 날짜를 뺀 나머지.
    ///
    /// ⚠️ 여기를 박아두면 쿼리가 **조용히 0건**이 된다. 설정은
    ///    `"{{DATE}} devlog.md"` 인데 쿼리가 `" 개발일지"` 를 찾고 있었다 —
    ///    한국어 볼트에서도 오늘 할 일이 한 번도 뜨지 않았다.
    static func devlogSuffix(_ cfg: JSONObject) -> String {
        var pat = Py.str(obj(cfg["naming"])["devlog_file"])
        if pat.isEmpty { pat = "{{DATE}} devlog.md" }
        return pat.replacingOccurrences(of: "{{DATE}}", with: "")
            .replacingOccurrences(of: ".md", with: "")
    }

    /// 템플릿 폴더 이름. 제외 조건에 쓴다.
    ///
    /// ⚠️ `"템플릿"` 을 박으면 영어 볼트에서 제외가 조용히 실패해 템플릿
    ///    파일이 '최근 노트' 에 섞인다.
    static func tplFolder(_ P: JSONObject) -> String {
        var t = Py.str(P["templates"])
        if t.isEmpty { t = "Templates" }
        return t.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? t
    }

    static func p(_ P: JSONObject, _ k: String) -> String { Py.str(P[k]) }
}
