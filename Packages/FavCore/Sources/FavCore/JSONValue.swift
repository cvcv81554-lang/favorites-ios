import Foundation

/// قيمة JSON عامة: السجلات تُحفظ كما هي (خريطة) حتى لا يضيع أي حقل مجهول عند الاستيراد أو الحفظ.
/// الأعداد الصحيحة تبقى صحيحة والعشرية عشرية (4.5 تبقى 4.5، و5 تبقى 5) — نفس سلوك التطبيق السابق.
public enum JSONValue: Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: قراءة مريحة
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// عدد (صحيح أو عشري) كـ Double.
    public var number: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; default: return nil }
    }
    public var int: Int? {
        switch self { case .int(let i): return Int(i); case .double(let d): return d.isFinite ? Int(d) : nil; default: return nil }
    }
    /// «تشغيل» بنمط التطبيق السابق: 1 أو true.
    public var isOn: Bool {
        switch self { case .bool(let b): return b; case .int(let i): return i == 1; case .double(let d): return d == 1; default: return false }
    }
    /// نص كما يظهر في `'${v}'` في Dart (للمقارنات النصية).
    public var text: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : String(d)
        case .string(let s): return s
        case .array, .object: return ""
        }
    }
    public subscript(key: String) -> JSONValue? { object?[key] }

    // MARK: تحويل من/إلى Foundation
    public static func from(any v: Any?) -> JSONValue {
        guard let v else { return .null }
        if v is NSNull { return .null }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let t = String(cString: n.objCType)
            if t == "d" || t == "f" { return .double(n.doubleValue) }
            return .int(n.int64Value)
        }
        if let s = v as? String { return .string(s) }
        if let a = v as? [Any] { return .array(a.map { from(any: $0) }) }
        if let o = v as? [String: Any] { return .object(o.mapValues { from(any: $0) }) }
        return .null
    }

    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.any }
        case .object(let o): return o.mapValues { $0.any }
        }
    }

    /// قراءة نص JSON (أي جذر).
    public static func parse(_ data: Data) throws -> JSONValue {
        from(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }
    public static func parse(_ text: String) throws -> JSONValue { try parse(Data(text.utf8)) }

    /// كتابة JSON مضغوطة (بلا تهريب «/»).
    public func encoded(sorted: Bool = false) throws -> Data {
        var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if sorted { opts.insert(.sortedKeys) }
        return try JSONSerialization.data(withJSONObject: any, options: opts)
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .int(Int64(v)) }
    public init(floatLiteral v: Double) { self = .double(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b })) }
}

public typealias JSONObject = [String: JSONValue]
