import Foundation

/// python 과 **같은 답을 내기 위한** 부품들.
///
/// ⚠️ Swift 의 기본 동작이 python 과 다른 자리가 몇 곳 있다. 그 차이가
///    출력에 새면 이관이 조용히 실패한다 — 골든이 잡아 주지만, 왜 다른지
///    모르면 고칠 수 없다. 여기 모아 두고 이유를 적는다.
enum Py {

    /// 문자열 비교 — **유니코드 코드포인트 순**.
    ///
    /// ⚠️ Swift 의 `String <` 는 유니코드 정규화를 거친 비교라 python 의
    ///    `<`(코드포인트 순)와 다를 수 있다. 예: 결합 문자, 한글 자모.
    ///    태그·레포명은 사용자 설정에서 오므로 ASCII 라고 가정하지 않는다.
    static func less(_ a: String, _ b: String) -> Bool {
        var x = a.unicodeScalars.makeIterator()
        var y = b.unicodeScalars.makeIterator()
        while true {
            switch (x.next(), y.next()) {
            case (nil, nil): return false          // 같다
            case (nil, _): return true             // a 가 짧다
            case (_, nil): return false            // b 가 짧다
            case (let p?, let q?):
                if p.value != q.value { return p.value < q.value }
            }
        }
    }

    /// **안정** 정렬. python 의 `list.sort` 는 안정이지만 Swift 의 `sort` 는
    /// 보장하지 않는다 — 키가 같은 항목의 순서가 뒤집히면 다른 출력이 된다.
    static func stableSorted<T>(_ xs: [T], by less: (T, T) -> Bool) -> [T] {
        xs.enumerated()
            .sorted { a, b in
                if less(a.element, b.element) { return true }
                if less(b.element, a.element) { return false }
                return a.offset < b.offset       // 같으면 원래 순서
            }
            .map(\.element)
    }

    /// python: `list(dict.fromkeys(xs))` — 순서를 지키며 중복 제거.
    static func dedup(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in xs where !seen.contains(x) {
            seen.insert(x)
            out.append(x)
        }
        return out
    }

    /// python: `s.strip()`
    static func strip(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// python: `s.lstrip("#")` — 앞의 `#` 를 **전부** 뗀다 (한 개가 아니다).
    static func lstripHash(_ s: String) -> String {
        var t = Substring(s)
        while t.first == "#" { t = t.dropFirst() }
        return String(t)
    }

    /// python: `env.get(name, "").split("\n")` 에서 빈 것을 뺀 목록.
    static func envLines(_ name: String) -> [String] {
        (ProcessInfo.processInfo.environment[name] ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// JSON 값에서 문자열을 꺼낸다. 없거나 다른 타입이면 빈 문자열 —
    /// python 의 `d.get(k) or ""` 와 같은 자리.
    static func str(_ v: JSON?) -> String {
        if case .string(let s)? = v { return s }
        return ""
    }

    /// JSON 값에서 불리언을 꺼낸다. 없으면 기본값 —
    /// python 의 `d.get(k, default)` 와 같다.
    static func bool(_ v: JSON?, _ fallback: Bool) -> Bool {
        if case .bool(let b)? = v { return b }
        return fallback
    }

    /// python 의 truthy: 없음·false 는 거짓, 그 외 true.
    static func truthy(_ v: JSON?) -> Bool {
        switch v {
        case .none, .some(.null): return false
        case .some(.bool(let b)): return b
        case .some(.int(let i)): return i != 0
        case .some(.string(let s)): return !s.isEmpty
        case .some(.array(let a)): return !a.isEmpty
        case .some(.object(let o)): return !o.isEmpty
        case .some(.double(let d)): return d != 0
        }
    }
}
