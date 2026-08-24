import Foundation

extension VaultScan {

    /// python 의 `collections.Counter` 중 이 파일이 쓰는 부분.
    ///
    /// ⚠️ `most_common(n)` 의 **동점 순서가 계약**이다. python 의 Counter 는
    ///    삽입 순서를 유지한 채 개수로만 정렬한다(안정 정렬) — 같은 개수면
    ///    **먼저 본 키가 앞**이다. Swift 의 Dictionary 는 순서가 없으므로
    ///    직접 유지해야 한다.
    struct Counter {
        private(set) var keys: [String] = []
        private var counts: [String: Int] = [:]

        mutating func add(_ k: String) {
            if counts[k] == nil { keys.append(k) }
            counts[k, default: 0] += 1
        }
        subscript(k: String) -> Int { counts[k] ?? 0 }
        var total: Int { counts.values.reduce(0, +) }

        func mostCommon(_ n: Int) -> [(String, Int)] {
            Py.stableSorted(keys) { counts[$0]! > counts[$1]! }
                .prefix(n).map { ($0, counts[$0]!) }
        }
        func pairs() -> [(String, Int)] { keys.map { ($0, counts[$0]!) } }
    }

    // ── 걷기 ────────────────────────────────────────────────────────────────

    /// python 의 `os.walk` + SKIP_DIRS · 숨은 폴더 제외.
    static func walkMD(_ vault: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: vault) else { return out }
        for case let sub as String in e {
            let name = (sub as NSString).lastPathComponent
            // ⚠️ 거르는 규칙은 **디렉터리에만** 적용한다.
            //
            //    python 은 `dirs[:] = [...]` 로 디렉터리 목록만 걸러낸다 —
            //    파일 이름이 점으로 시작해도 `.md` 면 센다. 실제 볼트에
            //    `.env … 공유.md` 같은 노트가 있었고, Swift 만 그것을
            //    빠뜨려 노트 수가 1 어긋났다 (2026-08-24).
            let isDir = e.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if isDir, skipDirs.contains(name) || name.hasPrefix(".") {
                // ⚠️ **디렉터리일 때만** 건너뛴다 (2026-08-24 실물 QA).
                //
                //    skipDescendants() 는 "가장 최근에 얻은 **디렉터리**로
                //    내려가지 않는다" 는 뜻이다. 파일에 부르면 지금 훑고 있던
                //    디렉터리가 통째로 잘린다 — `.DS_Store` 하나로 그 폴더의
                //    노트가 전부 사라졌다.
                //
                //    사용자의 실제 볼트에서 노트 1,775개 중 **8개만** 보였고,
                //    그래서 '기존 폴더 매핑' 질문이 뜨지 않아 기존 구조 위에
                //    평행 트리가 생겼다. python 판(os.walk)은 멀쩡했다.
                e.skipDescendants()
                continue
            }
            guard sub.hasSuffix(".md") else { continue }
            out.append(((vault as NSString).appendingPathComponent(sub), sub))
        }
        return out
    }

    // ── frontmatter ─────────────────────────────────────────────────────────

    /// 값은 문자열이거나 문자열 리스트다. **값이 빈 키도 남긴다.**
    enum Field { case str(String); case list([String]) }

    /// ⚠️ YAML 다중행 리스트를 반드시 처리해야 한다:
    ///
    ///        tags:
    ///          - type/devlog
    ///
    ///    한 줄짜리 `키: 값` 만 보면 tags 를 '값 없음' 으로 오판한다.
    ///    실제로 그렇게 만들었다가 **태그 집계가 실제의 1%** 로 나왔다.
    static func readFrontmatter(_ path: String, maxBytes: Int = 8192) -> [(String, Field)]? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: maxBytes)
        // python: errors="replace"
        let head = String(decoding: data, as: UTF8.self)

        guard head.hasPrefix("---") else { return nil }
        let afterThree = head.index(head.startIndex, offsetBy: 3)
        guard let endRange = head.range(of: "\n---", range: afterThree..<head.endIndex) else {
            return nil
        }
        let body = String(head[afterThree..<endRange.lowerBound])

        // 순서를 지키며 모은다 — custom_fields 의 most_common 동점 순서가 여기서 갈린다.
        var order: [String] = []
        var map: [String: Field] = [:]
        var current: String?

        for line in body.components(separatedBy: "\n") {
            // python: `^\s+-\s*(.*)$` — 앞에 공백이 **하나 이상** 있어야 한다.
            if let item = listItem(line), let cur = current {
                let v = stripQuotes(Py.strip(item))
                if !v.isEmpty {
                    // `tags:` 는 앞줄에서 빈 문자열로 들어가 있다. 리스트로 교체한다.
                    if case .list(var xs)? = map[cur] {
                        xs.append(v)
                        map[cur] = .list(xs)
                    } else {
                        map[cur] = .list([v])
                    }
                }
                continue
            }
            // python: `^([A-Za-z_][\w-]*)\s*:\s*(.*)$`
            guard let (key, val) = keyValue(line) else { continue }
            current = key
            if map[key] == nil { order.append(key) }
            if val.hasPrefix("["), val.hasSuffix("]") {
                // 인라인 배열: tags: [a, b]
                let inner = String(val.dropFirst().dropLast())
                map[key] = .list(inner.split(separator: ",", omittingEmptySubsequences: false)
                    .map { stripQuotes(Py.strip(String($0))) }
                    .filter { !$0.isEmpty })
            } else {
                map[key] = .str(val)
            }
        }
        return order.map { ($0, map[$0]!) }
    }

    /// `^\s+-\s*(.*)$`
    private static func listItem(_ line: String) -> String? {
        var i = line.startIndex
        var sawSpace = false
        while i < line.endIndex, line[i] == " " || line[i] == "\t" {
            sawSpace = true
            i = line.index(after: i)
        }
        guard sawSpace, i < line.endIndex, line[i] == "-" else { return nil }
        i = line.index(after: i)
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        return String(line[i...])
    }

    /// `^([A-Za-z_][\w-]*)\s*:\s*(.*)$`
    private static func keyValue(_ line: String) -> (String, String)? {
        var i = line.startIndex
        guard i < line.endIndex else { return nil }
        let first = line[i]
        guard first.isLetter && first.isASCII || first == "_" else { return nil }
        i = line.index(after: i)
        while i < line.endIndex {
            let c = line[i]
            if (c.isLetter && c.isASCII) || c.isNumber || c == "_" || c == "-" {
                i = line.index(after: i)
            } else { break }
        }
        let key = String(line[line.startIndex..<i])
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        guard i < line.endIndex, line[i] == ":" else { return nil }
        i = line.index(after: i)
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        return (key, Py.strip(String(line[i...])))
    }

    /// python: `x.strip("\"'")` — 앞뒤의 따옴표를 **여러 개라도** 벗긴다.
    static func stripQuotes(_ s: String) -> String {
        var t = Substring(s)
        while let f = t.first, f == "\"" || f == "'" { t = t.dropFirst() }
        while let l = t.last, l == "\"" || l == "'" { t = t.dropLast() }
        return String(t)
    }

    /// 값이 실제로 들어 있는가. 빈 키와 구분하는 판정 한 곳.
    static func fieldHasValue(_ f: Field?) -> Bool {
        switch f {
        case .list(let xs): return !xs.isEmpty
        case .str(let v):
            if v.isEmpty { return false }
            return !["[]", "{}", "\"\"", "''", "null", "~", "-"].contains(v)
        case .none: return false
        }
    }

    /// frontmatter 에서 태그를 뽑는다. 리스트·인라인·문자열 전부 처리한다.
    static func extractTags(_ fields: [(String, Field)]) -> [String] {
        guard let raw = fields.first(where: { $0.0 == "tags" })?.1 else { return [] }
        var out: [String] = []
        switch raw {
        case .list(let xs):
            out = xs.filter { !$0.isEmpty }.map { lstripHash($0) }
        case .str(let s) where !s.isEmpty:
            // python: `re.split(r"[,\s]+", raw)`
            out = s.split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map { lstripHash(String($0)) }
        default:
            out = []
        }
        return out.filter { !$0.isEmpty }
    }

    private static func lstripHash(_ s: String) -> String {
        var t = Substring(s)
        while t.first == "#" { t = t.dropFirst() }
        return String(t)
    }
}
