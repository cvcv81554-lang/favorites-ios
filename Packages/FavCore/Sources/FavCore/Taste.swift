import Foundation

// تحليل الذوق — من البيانات الوصفية الموثّقة فقط (حقول StashDB / ThePornDB)، بلا أي تحليل للصور.
// كل نتيجة لها مصدر: عدد المفضلات التي تملك الحقل، والنسبة.

/// قيمة خاصية: فئوية (نص) أو رقمية.
public enum Feat: Hashable, Sendable {
    case s(String), n(Double)
    public var str: String? { if case .s(let v) = self { return v }; return nil }
    public var num: Double? { if case .n(let v) = self { return v }; return nil }
}
public typealias Features = [String: Feat]

public let attrLabels: [String: [String: String]] = [
    "ethnicity": ["CAUCASIAN": "قوقازية", "BLACK": "سمراء البشرة", "ASIAN": "آسيوية", "INDIAN": "هندية", "LATIN": "لاتينية", "MIDDLE_EASTERN": "شرق أوسطية", "MIXED": "مختلطة", "OTHER": "أخرى"],
    "hair_color": ["BLONDE": "أشقر", "BRUNETTE": "بني", "BLACK": "أسود", "RED": "أحمر", "AUBURN": "كستنائي", "GREY": "رمادي", "BALD": "بلا شعر", "VARIOUS": "متنوع", "WHITE": "أبيض", "OTHER": "آخر"],
    "eye_color": ["BLUE": "زرقاء", "BROWN": "بنية", "GREY": "رمادية", "GREEN": "خضراء", "HAZEL": "عسلية", "RED": "حمراء"],
    "breast_type": ["NATURAL": "طبيعي", "FAKE": "مُعزَّز", "NA": "غير محدد"],
    "tattoos": ["yes": "لديها وشوم", "no": "بلا وشوم"],
    "piercings": ["yes": "لديها ثقوب", "no": "بلا ثقوب"],
    "active": ["yes": "ما زالت نشطة", "no": "اعتزلت"],
]
public let fieldNames: [String: String] = ["active": "النشاط", "ethnicity": "العرق", "hair_color": "لون الشعر", "eye_color": "لون العيون", "breast_type": "الصدر", "country": "البلد",
    "tattoos": "الوشوم", "piercings": "الثقوب", "height": "الطول", "age": "العمر", "career_start_year": "بداية المسيرة", "cup": "مقاس الصدر", "waist_size": "الخصر", "hip_size": "الأرداف"]
public func attrLabel(_ field: String, _ value: String) -> String { attrLabels[field]?[value] ?? value }

public let catFields = ["ethnicity", "hair_color", "eye_color", "breast_type", "country", "tattoos", "piercings", "active"]
public let numFields = ["height", "age", "career_start_year", "cup", "waist_size", "hip_size"]

/// سجل StashDB (أو ThePornDB بصيغته) ⇒ خصائص قابلة للمقارنة. الحقول الغائبة لا تُخمَّن.
public func featuresOf(_ p: JSONObject, now: Date = Date()) -> Features {
    var f = Features()
    for k in ["ethnicity", "hair_color", "eye_color", "breast_type"] {
        if let v = p[k]?.string, !v.isEmpty, v != "NA", v != "OTHER" { f[k] = .s(v) }
    }
    let c = (p["country"]?.text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
    if !c.isEmpty { f["country"] = .s(c) }
    if let t = p["tattoos"]?.array { f["tattoos"] = .s(t.isEmpty ? "no" : "yes") }
    if let t = p["piercings"]?.array { f["piercings"] = .s(t.isEmpty ? "no" : "yes") }
    if p["career_start_year"]?.number != nil { f["active"] = .s(p["career_end_year"]?.number != nil ? "no" : "yes") }
    for k in ["height", "career_start_year", "waist_size", "hip_size"] { if let v = p[k]?.number, v > 0 { f[k] = .n(v) } }
    if let a = sdAge(p["birth_date"], now: now).age, a >= 18 { f["age"] = .n(Double(a)) }
    let cup = (p["cup_size"]?.text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
    if let first = cup.unicodeScalars.first, ("A"..."K").contains(Character(first)) {
        let chars = Array(cup)
        f["cup"] = .n(Double(first.value) - 64 + (chars.count > 1 && chars[1] == chars[0] ? 0.5 : 0))
    }
    return f
}

public struct CatStat: Sendable {
    public let field: String; public let counts: [String: Double]; public let n: Int; public let wsum: Double
    public var top: (key: String, value: Double) { counts.max { $0.value < $1.value }.map { ($0.key, $0.value) } ?? ("", 0) }
    public var share: Double { wsum == 0 ? 0 : top.value / wsum }
    public func shareOf(_ v: String) -> Double { wsum == 0 ? 0 : (counts[v] ?? 0) / wsum }
    public func topN(_ k: Int) -> [(String, Double)] { counts.sorted { $0.value > $1.value }.prefix(k).map { ($0.key, $0.value / wsum) } }
    /// تفضيل واضح: 3 مفضلات على الأقل تملك الحقل، والقيمة الأولى ≥ 50٪.
    public var strong: Bool { n >= 3 && share >= 0.5 }
}
public struct NumStat: Sendable { public let field: String; public let mean, sd, lo, hi: Double; public let n: Int }

public struct TasteProfile: Sendable {
    public let total, analyzed: Int
    public let cats: [String: CatStat]; public let nums: [String: NumStat]
    public var sufficient: Bool { analyzed >= 3 }
    public var strongCats: [CatStat] { cats.values.filter(\.strong).sorted { $0.share > $1.share } }
}

/// [weights]: وزن كل مفضلة (افتراضي 1). [ignore]: حقول اختار المستخدم ألّا تُحسب.
public func buildProfile(_ feats: [Features], total: Int? = nil, weights: [Double]? = nil, ignore: Set<String> = []) -> TasteProfile {
    func wt(_ i: Int) -> Double { if let w = weights, i < w.count { return w[i] }; return 1 }
    var cats: [String: CatStat] = [:], nums: [String: NumStat] = [:]
    for k in catFields where !ignore.contains(k) {
        var c: [String: Double] = [:], n = 0, ws = 0.0
        for (i, f) in feats.enumerated() { if let v = f[k]?.str { c[v, default: 0] += wt(i); n += 1; ws += wt(i) } }
        if n > 0 { cats[k] = CatStat(field: k, counts: c, n: n, wsum: ws) }
    }
    for k in numFields where !ignore.contains(k) {
        var v: [Double] = [], w: [Double] = []
        for (i, f) in feats.enumerated() { if let x = f[k]?.num { v.append(x); w.append(wt(i)) } }
        if v.count < 2 { continue }
        let ws = w.reduce(0, +)
        var m = 0.0; for i in v.indices { m += v[i] * w[i] }; m /= ws
        var vv = 0.0; for i in v.indices { vv += w[i] * (v[i] - m) * (v[i] - m) }
        nums[k] = NumStat(field: k, mean: m, sd: (vv / ws).squareRoot(), lo: v.min()!, hi: v.max()!, n: v.count)
    }
    return TasteProfile(total: total ?? feats.count, analyzed: feats.filter { !$0.isEmpty }.count, cats: cats, nums: nums)
}

/// ملخص مقروء (كل سطر بنسبته وعدده — لا شيء مخترع).
public func describeProfile(_ p: TasteProfile) -> [String] {
    var out: [String] = []
    for c in p.strongCats.prefix(7) { out.append("\(fieldNames[c.field] ?? c.field): \(attrLabel(c.field, c.top.key)) (\(Int((c.share * 100).rounded()))٪ من \(c.n))") }
    func r(_ x: Double) -> String { String(Int(x.rounded())) }
    if let h = p.nums["height"] { out.append("الطول: متوسط \(r(h.mean)) سم (\(r(h.lo))–\(r(h.hi))، من \(h.n))") }
    if let a = p.nums["age"] { out.append("العمر: متوسط \(r(a.mean)) سنة (\(r(a.lo))–\(r(a.hi)))") }
    if let cs = p.nums["career_start_year"] { out.append("بداية المسيرة: حوالي \(r(cs.mean)) (\(r(cs.lo))–\(r(cs.hi)))") }
    let mixed = p.cats.values.filter { $0.n >= 3 && !$0.strong }.compactMap { fieldNames[$0.field] }
    if !mixed.isEmpty { out.append("متنوع لديك: " + mixed.joined(separator: "، ")) }
    return out
}

/// تعلّم من التفاعل: أوزان لقيم الخصائص (+ عند الإضافة، − عند «ليست ذوقي»)، محدودة بين −1 و+1.
public func learn(_ w: [String: Double], _ feats: Features, _ delta: Double) -> [String: Double] {
    var o = w
    for (k, v) in feats { if let s = v.str { o["\(k)=\(s)"] = min(1, max(-1, (o["\(k)=\(s)"] ?? 0) + delta)) } }
    return o
}

public struct Similarity: Sendable { public let score: Double; public let why: [String]; public let diff: [String] }

/// تشابه مرشحة مع الذوق: درجة 0..1 + أسباب التشابه + أوجه الاختلاف.
public func similarity(_ p: TasteProfile, _ f: Features, fb: [String: Double] = [:], weights extra: [String: Double] = [:]) -> Similarity {
    var got = 0.0, total = 0.0, why: [String] = [], diff: [String] = []
    let w: [String: Double] = ["ethnicity": 1.2, "hair_color": 1.0, "eye_color": 0.5, "breast_type": 0.8, "country": 0.6, "tattoos": 0.5, "piercings": 0.3, "active": 0.3]
    for (k, c) in p.cats {
        guard let v = f[k]?.str, c.n >= 2 else { continue }
        let weight = (w[k] ?? 0.5) * (c.strong ? 1 : 0.5) * (extra[k] ?? 1)
        total += weight
        let share = c.shareOf(v)
        got += weight * share
        if c.strong && v == c.top.key { why.append("\(fieldNames[k] ?? k) \(attrLabel(k, v)) مثل \(Int((c.share * 100).rounded()))٪ من مفضلاتك") }
        else if c.strong && share == 0 { diff.append("\(fieldNames[k] ?? k) \(attrLabel(k, v)) (أغلب مفضلاتك \(attrLabel(k, c.top.key)))") }
    }
    let nw: [String: Double] = ["height": 0.8, "age": 0.7, "career_start_year": 0.4, "cup": 0.6, "waist_size": 0.3, "hip_size": 0.3]
    for (k, s) in p.nums {
        guard let v = f[k]?.num else { continue }
        let weight = (nw[k] ?? 0.3) * (extra[k] ?? 1); total += weight
        let sd = max(s.sd, k == "height" ? 4 : k == "age" ? 3 : 2)
        let z = abs(v - s.mean) / sd
        let m = exp(-z * z / 2); got += weight * m
        if m > 0.75 && k == "height" { why.append("طولها \(Int(v.rounded())) سم قريب من متوسط مفضلاتك") }
        if m > 0.75 && k == "age" { why.append("عمرها \(Int(v.rounded())) ضمن الفئة التي تفضّلها") }
    }
    var score = total == 0 ? 0 : got / total
    var adj = 0.0; for (k, v) in f { if let s = v.str { adj += fb["\(k)=\(s)"] ?? 0 } }
    score = min(1, max(0, score + adj * 0.08))
    return Similarity(score: score, why: why, diff: diff)
}

/// وزن مفضلة في التحليل: المفضلة ★ أساس، والتقييم الأعلى يزيد الوزن (0.6..2).
public func tasteWeight(fav: Bool, rating: Double) -> Double { min(2, max(0.6, (fav ? 1 : 0.7) + (rating > 0 ? (rating - 3) * 0.25 : 0))) }

// MARK: - ذوقك في الأعمال (محلي بالكامل)

/// إشارة كل عمل: تقييم عالٍ قوي، مشاهدة/مفضلة متوسطة، «للمشاهدة» خفيفة، تقييم منخفض سلبي.
public func workSignal(_ g: WorkGroup) -> Double {
    if g.r >= 1 { return (Double(g.r) - 2.5) / 1.5 }
    if !g.rc.isEmpty { let a = Double(g.rc.values.reduce(0, +)) / Double(g.rc.count); return (a - 2.5) / 1.5 }
    var s = 0.0
    if g.seen { s += 0.6 }; if g.fav { s += 0.8 }; if g.q { s += 0.3 }
    return s
}

public struct KeyStat: Sendable { public let key, label: String; public let sum: Double; public let n: Int; public let avgR: Double
    public var score: Double { sum / Double(n + 2) } }

public struct WorkTaste: Sendable {
    public let keys: [String: KeyStat]; public let signals: Int
    public var sufficient: Bool { signals >= 5 }
    public func top(_ prefix: String, k: Int = 5) -> [KeyStat] { Array(keys.values.filter { $0.key.hasPrefix(prefix) && $0.score > 0.15 && $0.n >= 2 }.sorted { $0.score > $1.score }.prefix(k)) }
}

func workKeys(_ g: WorkGroup) -> [(String, String)] {
    var out: [(String, String)] = []
    if !g.s.trimmingCharacters(in: .whitespaces).isEmpty { out.append(("st:\(norm(g.s))", g.s.trimmingCharacters(in: .whitespaces))) }
    for t in g.tg.prefix(12) where !t.trimmingCharacters(in: .whitespaces).isEmpty { out.append(("tg:\(norm(t))", t.trimmingCharacters(in: .whitespaces))) }
    for p in g.who { out.append(("pf:\(p.id)", p.name)) }
    return out
}

public func buildWorkTaste(_ all: [WorkGroup]) -> WorkTaste {
    var sum: [String: Double] = [:], n: [String: Int] = [:], label: [String: String] = [:], rSum: [String: Int] = [:], rN: [String: Int] = [:]
    var signals = 0
    for g in all {
        let s = workSignal(g); if s == 0 { continue }
        signals += 1
        for (k, l) in workKeys(g) {
            sum[k, default: 0] += s; n[k, default: 0] += 1; if label[k] == nil { label[k] = l }
            if g.r > 0 { rSum[k, default: 0] += g.r; rN[k, default: 0] += 1 }
        }
    }
    var keys: [String: KeyStat] = [:]
    for (k, v) in sum { keys[k] = KeyStat(key: k, label: label[k]!, sum: v, n: n[k]!, avgR: (rN[k] ?? 0) == 0 ? 0 : Double(rSum[k]!) / Double(rN[k]!)) }
    return WorkTaste(keys: keys, signals: signals)
}

public struct WorkPick: Sendable { public let g: WorkGroup; public let score: Double; public let why: [String] }

/// أعمال لم تشاهدها (صدرت) مرتبة حسب ذوقك — لا اقتراح بلا سبب حقيقي.
public func recommendWorks(_ all: [WorkGroup], _ t: WorkTaste, limit: Int = 60, now: Date = Date()) -> [WorkPick] {
    var out: [WorkPick] = []
    let t0 = todayStr(now)
    for g in all {
        if g.seen || g.isUpcoming(now: now) || g.r > 0 || !g.rc.isEmpty { continue }
        if !g.date.isEmpty && g.date > t0 { continue }
        var score = 0.0, why: [String] = []
        if let st = t.keys["st:\(norm(g.s))"], st.score > 0.15 {
            score += st.score
            why.append(st.avgR >= 3.5 ? "من \(st.label) — متوسط تقييمك لأعماله \(String(format: "%.1f", st.avgR))" : "من \(st.label) الذي تشاهد أعماله كثيرًا")
        }
        let tags = g.tg.compactMap { t.keys["tg:\(norm($0))"] }.filter { $0.score > 0.15 }.sorted { $0.score > $1.score }
        if !tags.isEmpty {
            score += tags.prefix(4).reduce(0) { $0 + $1.score * 0.5 }
            why.append("وسوم تحبها: " + tags.prefix(3).map(\.label).joined(separator: "، "))
        }
        let ps = g.who.compactMap { p in t.keys["pf:\(p.id)"].map { (p, $0) } }.filter { $0.1.score > 0.15 }.sorted { $0.1.score > $1.1.score }
        if let first = ps.first { score += first.1.score * 1.2; why.append("مع \(first.0.name) التي أحببت أعمالها") }
        else if let f = g.who.first(where: \.fav) { score += 0.25; why.append("مع \(f.name) من مفضلاتك") }
        if why.isEmpty { continue }
        if let yr = Int(g.y), yr > 0 { score += Double(max(0, yr - 2000)) * 0.002 }
        out.append(WorkPick(g: g, score: score, why: why))
    }
    return Array(out.sorted { $0.score > $1.score }.prefix(limit))
}

public enum EveningMood: String, CaseIterable, Sendable { case taste = "✨ حسب ذوقي", favs = "♥ مفضلاتي", fresh = "🆕 الأحدث", newFace = "👀 ممثلة جديدة عليّ", random = "🎲 مفاجأة" }

/// «سهرة»: ثلاثة أعمال لم تشاهدها حسب المزاج والمدة، من ممثلات مختلفات؛ [seed] يغيّر الاختيار.
public func eveningPicks(_ all: [WorkGroup], _ t: WorkTaste, mood: EveningMood = .taste, maxMinutes: Int = 0, seed: UInt64 = 0, n: Int = 3, now: Date = Date()) -> [WorkPick] {
    let t0 = todayStr(now)
    let watchedP = Set(all.filter(\.seen).flatMap { $0.who.map(\.id) })
    func ok(_ g: WorkGroup) -> Bool { !g.seen && !g.isUpcoming(now: now) && (g.date.isEmpty || g.date <= t0) && (maxMinutes == 0 || (g.du > 0 && g.du <= maxMinutes)) }
    let ranked = Dictionary(recommendWorks(all, t, limit: 400, now: now).map { ($0.g.key, $0) }, uniquingKeysWith: { a, _ in a })
    var pool: [WorkPick]
    switch mood {
    case .taste: pool = ranked.values.filter { ok($0.g) }.sorted { $0.score > $1.score }
    case .favs: pool = all.filter { ok($0) && $0.who.contains(where: \.fav) }.map { g in ranked[g.key] ?? WorkPick(g: g, score: 0.1, why: ["مع \(g.who.first(where: \.fav)!.name) من مفضلاتك"]) }.sorted { $0.score > $1.score }
    case .fresh: pool = all.filter(ok).sorted { $0.date > $1.date }.prefix(40).map { g in ranked[g.key] ?? WorkPick(g: g, score: 0, why: ["صدر \(g.date.isEmpty ? "حديثًا" : g.date)"]) }
    case .newFace: pool = all.filter { ok($0) && !$0.who.isEmpty && $0.who.allSatisfy { !watchedP.contains($0.id) } }.map { g in ranked[g.key] ?? WorkPick(g: g, score: 0, why: ["لم تشاهد لـ \(g.who[0].name) شيئًا بعد"]) }.sorted { $0.score > $1.score }
    case .random: pool = all.filter(ok).map { g in ranked[g.key] ?? WorkPick(g: g, score: 0, why: ["اختيار عشوائي"]) }
    }
    if pool.isEmpty { return [] }
    var top = mood == .random ? pool : Array(pool.prefix(15))
    var rng = SeededRandom(seed: seed); top.shuffle(using: &rng)
    var out: [WorkPick] = [], used = Set<String>()
    for x in top where out.count < n { if x.g.who.contains(where: { used.contains($0.id) }) { continue }; out.append(x); x.g.who.forEach { used.insert($0.id) } }
    for x in top where out.count < n { if !out.contains(where: { $0.g.key == x.g.key }) { out.append(x) } }
    return out
}

/// مولّد عشوائي ثابت البذرة (اختيار يومي ثابت، خلط قابل للتكرار).
public struct SeededRandom: RandomNumberGenerator, Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

// MARK: - مسيرتها

public struct CareerYear: Sendable { public let year, count, seen: Int; public let avgR: Double; public let studios: [String] }
public struct Career: Sendable {
    public let years: [CareerYear]; public let start, first, last, peak: Int?; public let topStudios: [(String, Int)]; public let trend: Double?
    public var isEmpty: Bool { years.isEmpty }
}

/// مسيرتها سنة بسنة: العدد، ما شاهدته، متوسط تقييمك، أكثر الاستوديوهات، واتجاه تقييمك.
public func careerOf(_ p: Performer, now: Date = Date()) -> Career {
    var by: [Int: [JSONObject]] = [:]
    let maxYear = ymd(now).0 + 2
    for w in p.works {
        let d = w["d"]?.text ?? ""
        guard let y = Int(d.count >= 4 ? String(d.prefix(4)) : (w["y"]?.text ?? "")), y >= 1970, y <= maxYear else { continue }
        by[y, default: []].append(w)
    }
    var years: [CareerYear] = [], studioN: [String: (String, Int)] = [:]
    for y in by.keys.sorted() {
        let l = by[y]!; var st: [String: Int] = [:]
        for w in l {
            let s = (w["s"]?.text ?? "").trimmingCharacters(in: .whitespaces); if s.isEmpty { continue }
            st[s, default: 0] += 1; let k = norm(s); studioN[k] = (studioN[k]?.0 ?? s, (studioN[k]?.1 ?? 0) + 1)
        }
        let rs = l.compactMap { $0["r"]?.number }.filter { $0 > 0 }
        years.append(CareerYear(year: y, count: l.count, seen: l.filter { $0["w"]?.isOn == true }.count, avgR: rs.isEmpty ? 0 : rs.reduce(0, +) / Double(rs.count),
                                studios: st.sorted { $0.value > $1.value }.prefix(3).map(\.key)))
    }
    if years.isEmpty { return Career(years: [], start: nil, first: nil, last: nil, peak: nil, topStudios: [], trend: nil) }
    let peak = years.max { $0.count < $1.count }!.year
    let rated = years.filter { $0.avgR > 0 }
    return Career(years: years, start: p.raw["cs"]?.int, first: years.first!.year, last: years.last!.year, peak: peak,
                  topStudios: Array(studioN.values.sorted { $0.1 > $1.1 }.prefix(5)), trend: rated.count >= 2 ? rated.last!.avgR - rated.first!.avgR : nil)
}

// MARK: - لماذا تحبها؟

/// ما تشترك فيه مع بقية مفضلاتك (من البيانات الموثّقة فقط): (السمة، كم مفضلة تشاركها، النسبة).
public func sharedTraits(_ her: Features, _ others: [Features]) -> [(String, Int, Double)] {
    var out: [(String, Int, Double)] = []
    if others.isEmpty { return out }
    for (k, v) in her { guard let s = v.str else { continue }
        let n = others.filter { $0[k]?.str == s }.count
        if n > 0 { out.append(("\(fieldNames[k] ?? k): \(attrLabel(k, s))", n, Double(n) / Double(others.count))) }
    }
    for k in ["height", "age"] { guard let v = her[k]?.num else { continue }
        let n = others.filter { o in o[k]?.num.map { abs($0 - v) <= (k == "height" ? 4 : 3) } ?? false }.count
        if n > 0 { out.append((k == "height" ? "الطول قريب من \(Int(v.rounded())) سم" : "العمر قريب من \(Int(v.rounded()))", n, Double(n) / Double(others.count))) }
    }
    return out.sorted { $0.1 > $1.1 }
}

/// الأقرب إليها هي تحديدًا: درجة التشابه مع ملف من ممثلة واحدة.
public func closestTo<T>(_ her: Features, _ cands: [(T, Features)], k: Int = 10) -> [(T, Double)] {
    let prof = buildProfile([her, her, her])
    return Array(cands.filter { !$0.1.isEmpty }.map { ($0.0, similarity(prof, $0.1).score) }.sorted { $0.1 > $1.1 }.prefix(k))
}

// MARK: - خريطة الذوق (تحليل المكوّنات الرئيسية)

let numScale: [String: Double] = ["height": 10, "age": 6, "career_start_year": 5, "cup": 1.5, "waist_size": 4, "hip_size": 4]

/// متجه خصائص: فئوية (واحد-ساخن) + رقمية مطبّعة. يعيد (المتجهات، أسماء الأبعاد).
public func featureVectors(_ fs: [Features]) -> ([[Double]], [String]) {
    let voc = Array(Set(fs.flatMap { f in f.compactMap { k, v in v.str.map { "\(k)=\($0)" } } })).sorted()
    var means: [String: Double] = [:]
    for k in numScale.keys.sorted() { let v = fs.compactMap { $0[k]?.num }; if !v.isEmpty { means[k] = v.reduce(0, +) / Double(v.count) } }
    let mk = means.keys.sorted()
    let rows = fs.map { f -> [Double] in
        voc.map { d in let parts = d.split(separator: "=", maxSplits: 1); return f[String(parts[0])]?.str == String(parts[1]) ? 1 : 0 }
        + mk.map { k in f[k]?.num.map { ($0 - means[k]!) / numScale[k]! } ?? 0 }
    }
    return (rows, voc + mk.map { "#\($0)" })
}

/// إسقاط ثنائي الأبعاد — نقاط متقاربة = خصائص متقاربة. يعيد (x,y) بين −1 و1.
public func tasteMap(_ fs: [Features]) -> [(Double, Double)] {
    if fs.isEmpty { return [] }
    var (x, dims) = featureVectors(fs)
    if dims.isEmpty { return fs.map { _ in (0, 0) } }
    let n = x.count, m = dims.count
    let mu = (0..<m).map { j in x.reduce(0) { $0 + $1[j] } / Double(n) }
    for i in 0..<n { for j in 0..<m { x[i][j] -= mu[j] } }
    func power(_ orth: [Double]?) -> [Double] {
        var v = (0..<m).map { 1 / Double($0 + 1) }
        for _ in 0..<60 {
            let xv = x.map { r in zip(r, v).reduce(0) { $0 + $1.0 * $1.1 } }
            var nv = [Double](repeating: 0, count: m)
            for i in 0..<n { for j in 0..<m { nv[j] += x[i][j] * xv[i] } }
            if let o = orth { let d = zip(nv, o).reduce(0) { $0 + $1.0 * $1.1 }; for j in 0..<m { nv[j] -= d * o[j] } }
            let nn = nv.reduce(0) { $0 + $1 * $1 }.squareRoot(); if nn < 1e-12 { return [Double](repeating: 0, count: m) }
            v = nv.map { $0 / nn }
        }
        return v
    }
    let a = power(nil), b = power(a)
    let pts = x.map { r in (zip(r, a).reduce(0) { $0 + $1.0 * $1.1 }, zip(r, b).reduce(0) { $0 + $1.0 * $1.1 }) }
    let mx = pts.reduce(1e-9) { max($0, max(abs($1.0), abs($1.1))) }
    return pts.map { ($0.0 / mx, $0.1 / mx) }
}

// MARK: - ذوقك عبر الزمن

public struct TasteYear: Sendable { public let year, added, watched: Int; public let traits, studios: [String] }

public func tasteOverTime(_ lib: [Performer], _ works: [WorkGroup], _ featsById: [String: Features]) -> [TasteYear] {
    var years = Set<Int>(), addedBy: [Int: [Performer]] = [:], watchedBy: [Int: [WorkGroup]] = [:]
    for p in lib where p.added > 0 && !p.isMinor && (p.fav || p.rating >= 4) {
        let y = gregorian.component(.year, from: Date(timeIntervalSince1970: Double(p.added) / 1000)); years.insert(y); addedBy[y, default: []].append(p)
    }
    for g in works where g.wd.count >= 4 { if let y = Int(g.wd.prefix(4)) { years.insert(y); watchedBy[y, default: []].append(g) } }
    return years.sorted().map { y in
        let ps = addedBy[y] ?? []
        var cnt: [String: Int] = [:]
        for p in ps { for (k, v) in featsById[p.id] ?? [:] where ["hair_color", "ethnicity", "country", "eye_color"].contains(k) { if let s = v.str { cnt["\(fieldNames[k] ?? k): \(attrLabel(k, s))", default: 0] += 1 } } }
        let traits = cnt.filter { ps.count >= 2 && Double($0.value) / Double(ps.count) >= 0.5 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var st: [String: Int] = [:]; for g in watchedBy[y] ?? [] where !g.s.isEmpty { st[g.s, default: 0] += 1 }
        return TasteYear(year: y, added: ps.count, watched: (watchedBy[y] ?? []).count, traits: Array(traits), studios: st.sorted { $0.value > $1.value }.prefix(3).map(\.key))
    }
}
