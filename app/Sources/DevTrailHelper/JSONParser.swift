import Foundation

/// 순서를 지키며 읽는 JSON 파서.
///
/// ⚠️ 읽을 때도 순서를 지켜야 한다. 기존 설정 파일을 읽어 몇 개를 더한 뒤
///    다시 쓰는 것이 생성기들이 하는 일인데, 읽는 쪽에서 순서를 잃으면
///    쓸 때 복원할 방법이 없다 — 사용자 파일의 키 순서가 통째로 뒤집힌다.
enum JSONParseError: Error {
    case unexpected(String, at: Int)
}

struct JSONParser {
    private let s: [UInt8]
    private var i = 0

    init(_ text: String) {
        s = Array(text.utf8)
    }

    static func parse(_ text: String) -> JSON? {
        var p = JSONParser(text)
        do {
            p.skipSpace()
            let v = try p.value()
            p.skipSpace()
            guard p.i == p.s.count else { return nil }
            return v
        } catch {
            return nil
        }
    }

    /// 파일에서 읽는다. python 의 `load(p, d)` 와 같은 자리 —
    /// 못 읽거나 깨졌으면 nil 이다 (부르는 쪽이 기본값을 정한다).
    static func parseFile(_ path: String) -> JSON? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(text)
    }

    private mutating func skipSpace() {
        while i < s.count, s[i] == 0x20 || s[i] == 0x09 || s[i] == 0x0A || s[i] == 0x0D { i += 1 }
    }

    private mutating func value() throws -> JSON {
        skipSpace()
        guard i < s.count else { throw JSONParseError.unexpected("끝", at: i) }
        switch s[i] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return try number()
        }
    }

    private mutating func expect(_ word: String) throws {
        for b in word.utf8 {
            guard i < s.count, s[i] == b else { throw JSONParseError.unexpected(word, at: i) }
            i += 1
        }
    }

    private mutating func object() throws -> JSON {
        i += 1                                  // {
        var obj = JSONObject()
        skipSpace()
        if i < s.count, s[i] == UInt8(ascii: "}") { i += 1; return .object(obj) }
        while true {
            skipSpace()
            let key = try string()
            skipSpace()
            guard i < s.count, s[i] == UInt8(ascii: ":") else {
                throw JSONParseError.unexpected(":", at: i)
            }
            i += 1
            // ⚠️ 같은 키가 두 번 나오면 python 은 **뒤엣것**을 쓰고 위치는
            //    처음 자리를 지킨다. subscript 가 그렇게 동작한다.
            obj[key] = try value()
            skipSpace()
            guard i < s.count else { throw JSONParseError.unexpected("}", at: i) }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "}") { i += 1; return .object(obj) }
            throw JSONParseError.unexpected(", 또는 }", at: i)
        }
    }

    private mutating func array() throws -> JSON {
        i += 1                                  // [
        var items: [JSON] = []
        skipSpace()
        if i < s.count, s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            items.append(try value())
            skipSpace()
            guard i < s.count else { throw JSONParseError.unexpected("]", at: i) }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw JSONParseError.unexpected(", 또는 ]", at: i)
        }
    }

    private mutating func string() throws -> String {
        guard i < s.count, s[i] == UInt8(ascii: "\"") else {
            throw JSONParseError.unexpected("\"", at: i)
        }
        i += 1
        var bytes: [UInt8] = []
        while i < s.count {
            let b = s[i]
            if b == UInt8(ascii: "\"") {
                i += 1
                return String(decoding: bytes, as: UTF8.self)
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                guard i < s.count else { break }
                switch s[i] {
                case UInt8(ascii: "\""): bytes.append(UInt8(ascii: "\"")); i += 1
                case UInt8(ascii: "\\"): bytes.append(UInt8(ascii: "\\")); i += 1
                case UInt8(ascii: "/"): bytes.append(UInt8(ascii: "/")); i += 1
                case UInt8(ascii: "n"): bytes.append(0x0A); i += 1
                case UInt8(ascii: "r"): bytes.append(0x0D); i += 1
                case UInt8(ascii: "t"): bytes.append(0x09); i += 1
                case UInt8(ascii: "b"): bytes.append(0x08); i += 1
                case UInt8(ascii: "f"): bytes.append(0x0C); i += 1
                case UInt8(ascii: "u"):
                    i += 1
                    let scalar = try unicodeEscape()
                    bytes.append(contentsOf: Array(String(scalar).utf8))
                default:
                    throw JSONParseError.unexpected("이스케이프", at: i)
                }
                continue
            }
            bytes.append(b)
            i += 1
        }
        throw JSONParseError.unexpected("\"", at: i)
    }

    /// `\uXXXX` — 서러게이트 쌍까지 본다. python 이 쓴 파일은 대개
    /// ensure_ascii=False 라 안 나오지만, 남이 쓴 파일은 나온다.
    private mutating func unicodeEscape() throws -> Unicode.Scalar {
        let hi = try hex4()
        if hi >= 0xD800, hi <= 0xDBFF,
           i + 1 < s.count, s[i] == UInt8(ascii: "\\"), s[i + 1] == UInt8(ascii: "u") {
            i += 2
            let lo = try hex4()
            if lo >= 0xDC00, lo <= 0xDFFF {
                let v = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                guard let sc = Unicode.Scalar(UInt32(v)) else {
                    throw JSONParseError.unexpected("코드포인트", at: i)
                }
                return sc
            }
            guard let sc = Unicode.Scalar(UInt32(lo)) else {
                throw JSONParseError.unexpected("코드포인트", at: i)
            }
            return sc
        }
        guard let sc = Unicode.Scalar(UInt32(hi)) else {
            throw JSONParseError.unexpected("코드포인트", at: i)
        }
        return sc
    }

    private mutating func hex4() throws -> Int {
        var v = 0
        for _ in 0..<4 {
            guard i < s.count, let d = JSONParser.hexDigit(s[i]) else {
                throw JSONParseError.unexpected("16진수", at: i)
            }
            v = v * 16 + d
            i += 1
        }
        return v
    }

    private static func hexDigit(_ b: UInt8) -> Int? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(b - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(b - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(b - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }

    private mutating func number() throws -> JSON {
        let start = i
        if i < s.count, s[i] == UInt8(ascii: "-") { i += 1 }
        var isDouble = false
        while i < s.count {
            let b = s[i]
            if b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") { i += 1; continue }
            if b == UInt8(ascii: ".") || b == UInt8(ascii: "e") || b == UInt8(ascii: "E")
                || b == UInt8(ascii: "+") || b == UInt8(ascii: "-") {
                isDouble = true
                i += 1
                continue
            }
            break
        }
        guard start < i else { throw JSONParseError.unexpected("숫자", at: i) }
        let text = String(decoding: s[start..<i], as: UTF8.self)
        if !isDouble, let n = Int(text) { return .int(n) }
        guard let d = Double(text) else { throw JSONParseError.unexpected("숫자", at: start) }
        return .double(d)
    }
}
