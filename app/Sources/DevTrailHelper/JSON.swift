import Foundation

/// 순서를 지키는 JSON 값.
///
/// ⚠️ 왜 Foundation 의 JSONSerialization 을 쓰지 않는가
///
///    python 생성기의 출력을 **바이트 단위로** 재현해야 한다(ADR 0006 M1).
///    그런데 python 의 dict 는 **삽입 순서**를 지키고, 그 순서가 그대로
///    출력에 나온다. 실제 골든:
///
///        {
///          "smart_sources": { … },
///          "other_key": "건드리면 안 된다",   ← 기존 파일의 순서 그대로
///          "is_obsidian_vault": true          ← 나중에 붙은 것이 맨 끝
///        }
///
///    JSONSerialization 은 순서를 보장하지 않고, JSONEncoder 의
///    .sortedKeys 는 알파벳순으로 **바꿔 버린다.** 둘 다 다른 파일을 만든다.
///    사용자 설정 파일에서 "키 순서만 다름" 은 다름이다.
///
/// ⚠️ 이 파일은 8개 생성기 전부의 토대다. 여기가 틀리면 전부 틀린다.
indirect enum JSON {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object(JSONObject)
}

/// 삽입 순서를 지키는 객체.
struct JSONObject {
    private(set) var keys: [String] = []
    private var values: [String: JSON] = [:]

    init() {}

    init(_ pairs: [(String, JSON)]) {
        for (k, v) in pairs { self[k] = v }
    }

    subscript(key: String) -> JSON? {
        get { values[key] }
        set {
            if let newValue {
                if values[key] == nil { keys.append(key) }
                values[key] = newValue
            } else if values[key] != nil {
                keys.removeAll { $0 == key }
                values[key] = nil
            }
        }
    }

    /// 없을 때만 넣는다. python 의 dict.setdefault 와 같다 —
    /// **있으면 순서도 값도 건드리지 않는다.**
    mutating func setDefault(_ key: String, _ value: JSON) {
        if values[key] == nil { self[key] = value }
    }

    var isEmpty: Bool { keys.isEmpty }
}

// ── 쓰기 ─────────────────────────────────────────────────────────────────────

extension JSON {
    /// python 의 `json.dumps(x, ensure_ascii=False, indent=2)` 와 같은 문자열.
    ///
    /// ⚠️ 끝에 개행을 붙이지 않는다. python 쪽도 `print` 가 붙인다 —
    ///    여기서 붙이면 두 번이 된다.
    func pythonJSON(indent: Int = 2) -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    /// python 의 `json.dump(x, fp, ensure_ascii=False)` — **indent 없음**.
    ///
    /// ⚠️ indent 를 안 주면 python 의 구분자는 `(', ', ': ')` 다. 쉼표 뒤
    ///    **공백이 하나** 붙는다 — `{"a": 1, "b": 2}`. 공백을 빼면 다른
    ///    파일이 된다. snapshot.py 가 이 형식으로 낸다.
    func pythonJSONCompact() -> String {
        var out = ""
        writeCompact(into: &out)
        return out
    }

    private func writeCompact(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += JSON.pythonNumber(d)
        case .string(let s): out += JSON.quote(s)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += ", " }
                item.writeCompact(into: &out)
            }
            out += "]"
        case .object(let obj):
            out += "{"
            for (i, key) in obj.keys.enumerated() {
                if i > 0 { out += ", " }
                out += JSON.quote(key) + ": "
                obj[key]!.writeCompact(into: &out)
            }
            out += "}"
        }
    }

    private func write(into out: inout String, indent: Int, level: Int) {
        switch self {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .int(let i):
            out += String(i)
        case .double(let d):
            out += JSON.pythonNumber(d)
        case .string(let s):
            out += JSON.quote(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            let pad = String(repeating: " ", count: indent * (level + 1))
            let close = String(repeating: " ", count: indent * level)
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent, level: level + 1)
                out += (i == items.count - 1) ? "\n" : ",\n"
            }
            out += close + "]"
        case .object(let obj):
            if obj.isEmpty { out += "{}"; return }
            let pad = String(repeating: " ", count: indent * (level + 1))
            let close = String(repeating: " ", count: indent * level)
            out += "{\n"
            for (i, key) in obj.keys.enumerated() {
                out += pad + JSON.quote(key) + ": "
                obj[key]!.write(into: &out, indent: indent, level: level + 1)
                out += (i == obj.keys.count - 1) ? "\n" : ",\n"
            }
            out += close + "}"
        }
    }

    /// python 의 문자열 이스케이프. `ensure_ascii=False` 이므로
    /// **한글·이모지는 그대로 둔다** — \uXXXX 로 바꾸면 사람이 못 읽는다.
    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }

    /// python 의 float 표기. 정수값이면 `.0` 을 붙인다 (repr 과 같다).
    static func pythonNumber(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e16 {
            return String(format: "%.1f", d)
        }
        return String(d)
    }
}
