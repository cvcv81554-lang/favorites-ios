import Foundation

// تنقية كل ما يدخل من ملف أو مزامنة أو API — منقولة من التطبيق السابق (safeId / safeImg / safeWorks / ydOf / wkey).

func matches(_ s: String, _ pattern: String, options: String.CompareOptions = []) -> Bool {
    s.range(of: pattern, options: options.union(.regularExpression)) != nil
}

public func safeId(_ v: JSONValue?) -> Bool {
    guard let s = v?.string else { return false }
    return matches(s, #"^[A-Za-z0-9_.:-]{1,128}$"#)   // \w في Dart (بلا unicode) = [A-Za-z0-9_]
}

private let badImgChars = #"["<>`\\]"#

/// صورة مقبولة: https/http أو data:image بصيغة معروفة، بلا رموز خطرة.
public func safeImg(_ v: JSONValue?) -> Bool {
    guard let s = v?.string, !s.isEmpty else { return false }
    if matches(s, badImgChars) { return false }
    if s.hasPrefix("https://") || s.hasPrefix("http://") { return true }
    return matches(s, #"^data:image/(png|jpe?g|webp|gif|avif);base64,"#, options: .caseInsensitive)
}

public func safeHttps(_ v: JSONValue?) -> Bool {
    guard let s = v?.string else { return false }
    return s.hasPrefix("https://") && !matches(s, badImgChars)
}

/// مفتاح العمل عبر الممثلات: الحروف والأرقام فقط (Unicode) بأحرف صغيرة.
public func wkey(_ t: String) -> String {
    String(String.UnicodeScalarView(t.lowercased().unicodeScalars.filter(isLetterOrNumber)))
}

/// \p{L} أو \p{N} بالضبط (بلا علامات التشكيل Mn — مثل Dart).
func isLetterOrNumber(_ u: Unicode.Scalar) -> Bool {
    switch u.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber: return true
    default: return false
    }
}
public func wKeyOf(_ w: JSONObject) -> String { "\(wkey(w["t"]?.text ?? ""))|\(wkey(w["s"]?.text ?? ""))" }

/// تطبيع اسم للمقارنة (بحث، تطابق).
public func norm(_ s: String) -> String {
    s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

/// تطبيع عنوان للمقارنة بين المصدرين (حروف وأرقام فقط، مفصولة بمسافة).
public func normTitle(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
}

private func p2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

private func groups(_ s: String, _ pattern: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = s as NSString
    guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
}

/// تاريخ عمل: يقبل YYYY-M-D و D-M-YYYY و YYYY-M و YYYY ⇒ {d, y}.
public func ydOf(_ raw: String) -> [String: String] {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let m = groups(s, #"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#) { return ["d": "\(m[1])-\(p2(Int(m[2])!))-\(p2(Int(m[3])!))", "y": m[1]] }
    if let m = groups(s, #"^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})"#) { return ["d": "\(m[3])-\(p2(Int(m[2])!))-\(p2(Int(m[1])!))", "y": m[3]] }
    if let m = groups(s, #"^(\d{4})[-/.](\d{1,2})$"#) { return ["y": m[1]] }
    if let m = groups(s, #"^(\d{4})$"#) { return ["y": m[1]] }
    return [:]
}

public func todayStr(_ now: Date = Date()) -> String { let t = ymd(now); return "\(t.0)-\(p2(t.1))-\(p2(t.2))" }

/// تنقية قائمة أعمال واردة: حقول معروفة الأنواع، روابط https فقط، وحدود الأحجام. الحقول المجهولة تبقى.
public func safeWorks(_ v: JSONValue?) -> [JSONValue] {
    guard let list = v?.array else { return [] }
    var out: [JSONValue] = []
    for x in list.prefix(5000) {
        if let str = x.string {
            // صيغة قديمة: "عنوان | موقع | سنة" أو "عنوان (YYYY)"
            let parts = str.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first, !first.isEmpty else { continue }
            var w: JSONObject = ["t": .string(first)]
            if parts.count > 1 && !parts[1].isEmpty { w["s"] = .string(parts[1]) }
            if parts.count > 2 && matches(parts[2], #"^\d{4}$"#) { w["y"] = .string(parts[2]) }
            if let ym = groups(first, #"^(.*)\((\d{4})\)\s*$"#) { w["t"] = .string(ym[1].trimmingCharacters(in: .whitespaces)); w["y"] = .string(ym[2]) }
            out.append(.object(w))
            continue
        }
        guard var w = x.object else { continue }
        let t = (w["t"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { continue }
        w["t"] = .string(t.count > 400 ? String(t.prefix(400)) : t)
        if let p = w["p"], !p.isNull, !safeHttps(p) { w["p"] = nil }
        if let u = w["u"], !u.isNull, !safeHttps(u) { w["u"] = nil }
        for k in ["ip", "is"] { if let id = w[k], !id.isNull, !matches(id.text, #"^[A-Za-z0-9-]{1,64}$"#) { w[k] = nil } }
        if let im = w["im"], !im.isNull, !matches(im.text, #"^tt\d{5,10}$"#) { w["im"] = nil }
        if let tm = w["tm"], !tm.isNull, !matches(tm.text, #"^\d{1,10}$"#) { w["tm"] = nil }
        if let d = w["d"], !d.isNull {
            let yd = ydOf(d.text); w["d"] = nil
            if let dd = yd["d"] { w["d"] = .string(dd) }
            if let yy = yd["y"], (w["y"]?.text ?? "").isEmpty { w["y"] = .string(yy) }
        }
        if let y = w["y"], !y.isNull, !matches(y.text, #"^\d{4}$"#) { w["y"] = nil }
        if let wd = w["wd"], !wd.isNull, !matches(wd.text, #"^\d{4}-\d{2}-\d{2}$"#) { w["wd"] = nil }
        if let tg = w["tg"]?.array {
            var seen = Set<String>(); var l: [JSONValue] = []
            for e in tg { if let s = e.string, seen.insert(s).inserted { l.append(.string(s)); if l.count == 10 { break } } }
            w["tg"] = .array(l)
        } else { w["tg"] = nil }
        if let ls = w["ls"]?.array { w["ls"] = .array(ls.filter { $0.string != nil }) } else { w["ls"] = nil }
        out.append(.object(w))
    }
    return out
}
