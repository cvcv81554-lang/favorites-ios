import Foundation

// MARK: - Favorites Intelligence Engine
// محرك ذكاء محلي بالكامل: إحصاء حتمي قابل للتفسير (لا نموذج لغوي يخترع). كل نتيجة معها: الدليل، الحجم، الثقة، والقيود.
// يفرّق بين: بيانات موثّقة من المصدر / ما أدخلته أنت / تفضيل مستنتج / ارتباط إحصائي / تنبؤ. الارتباط ليس سببًا.

/// ثقة تقييم سجل: كامل (≥6 معايير + تقييم)، جزئي، أو ما حدّدته أنت (rconf: 1 غير متأكد، 2 جزئي، 3 متأكد).
public func ratingConfidence(_ p: Performer) -> Double {
    if let c = p.raw["rconf"]?.int, (1...3).contains(c) { return [0.4, 0.7, 1.0][c - 1] }
    let n = p.criteriaValues.count
    if p.rating > 0 && n >= 6 { return 1 }
    if p.rating > 0 && n >= 2 { return 0.8 }
    return p.rating > 0 ? 0.65 : 0
}

/// عيّنة: ممثلة مقيّمة + خصائصها + وزن ثقة تقييمها.
public struct Sample: Sendable { public let p: Performer; public let f: Features; public let y: Double; public let w: Double }

public func samples(_ lib: [Performer], _ feats: [String: Features], excluded: Set<String> = []) -> [Sample] {
    lib.compactMap { p in
        guard !p.isMinor, p.rating > 0, !excluded.contains(p.id), let f = feats[p.id], !f.isEmpty else { return nil }
        return Sample(p: p, f: f, y: p.rating, w: ratingConfidence(p))
    }
}

func wmean(_ xs: [(Double, Double)]) -> Double { let ws = xs.reduce(0) { $0 + $1.1 }; return ws == 0 ? 0 : xs.reduce(0) { $0 + $1.0 * $1.1 } / ws }
func wsd(_ xs: [(Double, Double)], _ m: Double) -> Double { let ws = xs.reduce(0) { $0 + $1.1 }; return ws == 0 ? 0 : (xs.reduce(0) { $0 + $1.1 * ($1.0 - m) * ($1.0 - m) } / ws).squareRoot() }

/// ترميز الخاصية كنص مقروء: «لون الشعر: أشقر» أو «الطول: 165–174».
public func traitLabel(_ key: String) -> String {
    let parts = key.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return key }
    return "\(fieldNames[parts[0]] ?? parts[0]): \(attrLabel(parts[0], parts[1]))"
}

/// الخصائص الرقمية تُقسَّم لنطاقات حتى تدخل التحليل التوافقي.
public func traitKeys(_ f: Features) -> [String] {
    var out: [String] = []
    for (k, v) in f {
        if let s = v.str { out.append("\(k)=\(s)") }
        else if let n = v.num {
            switch k {
            case "height": out.append("height=\(n < 160 ? "<160" : n < 170 ? "160–169" : n < 180 ? "170–179" : "180+")")
            case "age": out.append("age=\(n < 25 ? "18–24" : n < 30 ? "25–29" : n < 35 ? "30–34" : n < 40 ? "35–39" : "40+")")
            case "cup": out.append("cup=\(n < 2.5 ? "صغير" : n < 4 ? "متوسط" : "كبير")")
            default: break
            }
        }
    }
    return out.sorted()
}

// MARK: Taste DNA

public struct TraitEffect: Identifiable, Sendable {
    public let key: String; public let n: Int; public let mean, effect, z: Double
    public var id: String { key }
    public var label: String { traitLabel(key) }
    public var confidence: Double { min(1, Double(n) / Double(n + 4)) * min(1, abs(z) / 2.5) }
}

public struct ComboEffect: Identifiable, Sendable {
    public let a, b: String; public let n: Int; public let mean, expected, interaction: Double
    public var id: String { a + "&" + b }
    public var label: String { "\(traitLabel(a)) + \(traitLabel(b))" }
    public var confidence: Double { min(1, Double(n) / Double(n + 4)) * min(1, abs(interaction) / 1.0) }
}

public struct TasteDNA: Sendable {
    public let baseline: Double; public let count: Int
    public let effects: [TraitEffect]; public let combos: [ComboEffect]
    public var strong: [TraitEffect] { effects.filter { $0.effect >= 0.4 && $0.n >= 3 && $0.z >= 1.5 } }
    public var secondary: [TraitEffect] { effects.filter { $0.effect >= 0.2 && $0.effect < 0.4 && $0.n >= 3 } }
    public var negative: [TraitEffect] { effects.filter { $0.effect <= -0.3 && $0.n >= 3 } }
    /// تراكيب: تقييمك لها أعلى بوضوح مما تتوقعه كل خاصية وحدها (تآزر) — أو أقل (حدود التفضيل).
    public var synergies: [ComboEffect] { combos.filter { $0.interaction >= 0.35 } }
    public var boundaries: [ComboEffect] { combos.filter { $0.interaction <= -0.35 } }
    public var sufficient: Bool { count >= 6 }
}

/// يقيس أثر كل خاصية وكل تركيب خاصيتين على تقييماتك (مقارنةً بمتوسطك)، بأوزان ثقة التقييم.
public func tasteDNA(_ s: [Sample], minSupport: Int = 3) -> TasteDNA {
    let all = s.map { ($0.y, $0.w) }
    let base = wmean(all), sd = max(0.35, wsd(all, base))
    var by: [String: [(Double, Double)]] = [:]
    let keysOf = s.map { traitKeys($0.f) }
    for (i, ks) in keysOf.enumerated() { for k in ks { by[k, default: []].append((s[i].y, s[i].w)) } }
    var effects: [TraitEffect] = []
    for (k, xs) in by where xs.count >= 2 {
        let m = wmean(xs)
        effects.append(TraitEffect(key: k, n: xs.count, mean: m, effect: m - base, z: (m - base) / (sd / Double(xs.count).squareRoot())))
    }
    let eff = Dictionary(uniqueKeysWithValues: effects.map { ($0.key, $0.effect) })
    var pairs: [String: [(Double, Double)]] = [:]
    for (i, ks) in keysOf.enumerated() {
        let use = ks.filter { (by[$0]?.count ?? 0) >= minSupport }
        for a in 0..<use.count { for b in (a + 1)..<max(a + 1, use.count) where b < use.count && use[a].split(separator: "=")[0] != use[b].split(separator: "=")[0] {
            pairs["\(use[a])&\(use[b])", default: []].append((s[i].y, s[i].w))
        } }
    }
    var combos: [ComboEffect] = []
    for (k, xs) in pairs where xs.count >= minSupport {
        let parts = k.components(separatedBy: "&")
        let m = wmean(xs), exp = base + (eff[parts[0]] ?? 0) + (eff[parts[1]] ?? 0)
        combos.append(ComboEffect(a: parts[0], b: parts[1], n: xs.count, mean: m, expected: min(5, max(0, exp)), interaction: m - min(5, max(0, exp))))
    }
    return TasteDNA(baseline: base, count: s.count, effects: effects.sorted { $0.effect > $1.effect }, combos: combos.sorted { abs($0.interaction) > abs($1.interaction) })
}

// MARK: Archetypes (k-means)

public struct Archetype: Identifiable, Sendable {
    public let id: String; public var name: String; public let traits: [(String, Double)]; public let members: [Performer]; public let avgRating: Double
}

/// يجد عدة أنماط تفضيل (عناقيد) بدل ملف واحد. k من 2 إلى 4 يُختار بأفضل فصل.
public func archetypes(_ s: [Sample], seed: UInt64 = 7) -> [Archetype] {
    let pool = s.filter { $0.y >= 3.5 || $0.p.fav }
    if pool.count < 6 { return [] }
    let (x, _) = featureVectors(pool.map(\.f))
    func dist(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
    func kmeans(_ k: Int) -> ([Int], Double) {
        var rng = SeededRandom(seed: seed &+ UInt64(k))
        var cents = [x[Int(rng.next() % UInt64(x.count))]]
        while cents.count < k {   // k-means++
            let d = x.map { p in cents.map { dist(p, $0) }.min()! }; let tot = d.reduce(0, +)
            var r = rng.unit() * tot, pick = 0
            for (i, v) in d.enumerated() { r -= v; if r <= 0 { pick = i; break } }
            cents.append(x[pick])
        }
        var assign = [Int](repeating: 0, count: x.count)
        for _ in 0..<40 {
            assign = x.map { p in (0..<k).min { dist(p, cents[$0]) < dist(p, cents[$1]) }! }
            for c in 0..<k { let m = x.indices.filter { assign[$0] == c }; if m.isEmpty { continue }
                cents[c] = (0..<x[0].count).map { j in m.reduce(0) { $0 + x[$1][j] } / Double(m.count) } }
        }
        let inertia = x.indices.reduce(0) { $0 + dist(x[$1], cents[assign[$1]]) }
        return (assign, inertia)
    }
    var best: ([Int], Int) = (kmeans(2).0, 2)
    var prevInertia = kmeans(1).1
    for k in 2...min(4, pool.count / 3) {
        let (a, inr) = kmeans(k)
        if prevInertia > 0 && (prevInertia - inr) / prevInertia >= 0.15 { best = (a, k) }
        prevInertia = inr
    }
    var out: [Archetype] = []
    for c in 0..<best.1 {
        let members = pool.indices.filter { best.0[$0] == c }.map { pool[$0] }
        if members.count < 2 { continue }
        var cnt: [String: Int] = [:]; for m in members { for k in traitKeys(m.f) { cnt[k, default: 0] += 1 } }
        let traits = cnt.map { ($0.key, Double($0.value) / Double(members.count)) }.filter { $0.1 >= 0.6 }.sorted { $0.1 > $1.1 }
        let name = traits.prefix(3).map { traitLabel($0.0).components(separatedBy: ": ").last ?? $0.0 }.joined(separator: " · ")
        let id = "arch:" + traits.prefix(3).map(\.0).joined(separator: "|")
        out.append(Archetype(id: id, name: name.isEmpty ? "نمط متنوع" : name, traits: Array(traits.prefix(6)), members: members.map(\.p), avgRating: members.map(\.y).reduce(0, +) / Double(members.count)))
    }
    return out.sorted { $0.members.count > $1.members.count }
}

// MARK: Rating predictor

public struct Prediction: Sendable {
    public let rating: Double; public let confidence: Double
    public let reasons: [String]; public let neighbors: [(Performer, Double)]; public let missing: [String]
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    let d = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }, na = a.reduce(0) { $0 + $1 * $1 }.squareRoot(), nb = b.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return na == 0 || nb == 0 ? 0 : d / (na * nb)
}

/// تنبؤ بتقييمك لممثلة: أقرب ممثلاتك المقيّمة (بخصائصها) + أثر خصائصها في «Taste DNA». لا تنبؤ ببيانات غير كافية.
public func predictRating(_ f: Features, samples s: [Sample], dna: TasteDNA? = nil, excludeId: String? = nil, userWeights: [String: Double] = [:]) -> Prediction? {
    let pool = s.filter { $0.p.id != excludeId }
    if pool.count < 8 || f.count < 3 { return nil }
    let (vecs, _) = featureVectors(pool.map(\.f) + [f])
    let me = vecs.last!
    let sims = pool.indices.map { (pool[$0], max(0, cosine(vecs[$0], me))) }.sorted { $0.1 > $1.1 }
    let nb = Array(sims.prefix(7)).filter { $0.1 > 0.1 }
    if nb.count < 3 { return nil }
    let knn = wmean(nb.map { ($0.0.y, $0.1 * $0.0.w) })
    let d = dna ?? tasteDNA(pool)
    let eff = Dictionary(uniqueKeysWithValues: d.effects.filter { $0.n >= 3 }.map { ($0.key, $0) })
    var add = d.baseline, used: [TraitEffect] = []
    for k in traitKeys(f) {
        guard let e = eff[k] else { continue }
        let field = String(k.split(separator: "=")[0])
        add += e.effect * min(1, Double(e.n) / Double(e.n + 4)) * (userWeights[field] ?? 1); used.append(e)
    }
    add = min(5, max(0, add))
    let rating = min(5, max(0, 0.6 * knn + 0.4 * add))
    let spread = wsd(nb.map { ($0.0.y, $0.1) }, knn)
    let conf = min(1, (nb.map(\.1).reduce(0, +) / Double(nb.count)) * Double(nb.count) / 7) * max(0.2, 1 - spread / 2) * min(1, Double(f.count) / 6)
    var reasons = used.sorted { abs($0.effect) > abs($1.effect) }.prefix(3).map { e in
        "\(e.label): تقييمك لمثلها \(String(format: "%.1f", e.mean)) (\(e.effect >= 0 ? "+" : "")\(String(format: "%.1f", e.effect)) عن متوسطك، من \(e.n))"
    }
    if let top = nb.first { reasons.append("الأقرب إليها: \(top.0.p.name) (قيّمتها \(String(format: "%.1f", top.0.y)))") }
    let missing = catFields.filter { f[$0] == nil }.map { fieldNames[$0] ?? $0 }
    return Prediction(rating: (rating * 2).rounded() / 2, confidence: conf, reasons: reasons, neighbors: nb.map { ($0.0.p, $0.1) }, missing: missing)
}

/// تنبؤ تقييم عمل من ذوقك في الأعمال (الاستوديو، الوسوم، الممثلات) — متوسط تقييماتك لما يشبهه.
public func predictWork(_ g: WorkGroup, _ t: WorkTaste) -> (rating: Double, confidence: Double, reasons: [String])? {
    var xs: [(Double, Double)] = [], reasons: [String] = []
    if let st = t.keys["st:\(norm(g.s))"], st.avgR > 0 { xs.append((st.avgR, Double(st.n))); reasons.append("\(st.label): متوسط تقييمك \(String(format: "%.1f", st.avgR)) من \(st.n)") }
    for p in g.who { if let k = t.keys["pf:\(p.id)"], k.avgR > 0 { xs.append((k.avgR, Double(k.n) * 1.3)); reasons.append("\(p.name): متوسط تقييمك لأعمالها \(String(format: "%.1f", k.avgR))") } }
    for tg in g.tg.prefix(8) { if let k = t.keys["tg:\(norm(tg))"], k.avgR > 0, k.n >= 2 { xs.append((k.avgR, Double(k.n) * 0.4)) } }
    let n = xs.reduce(0) { $0 + $1.1 }
    if xs.count < 2 || n < 4 { return nil }
    return ((wmean(xs) * 2).rounded() / 2, min(1, n / (n + 8)), reasons)
}

// MARK: Prediction feedback loop

/// سجل التنبؤات: id ⇒ {p: المتوقع، c: الثقة، t: الوقت، a: الفعلي إن قيّمت لاحقًا}.
public struct PredictionLog: Sendable {
    public var entries: [String: [String: Double]]
    public init(json: JSONValue?) { entries = (json?.object ?? [:]).mapValues { ($0.object ?? [:]).compactMapValues { $0.number } } }
    public var json: JSONValue { .object(entries.mapValues { .object($0.mapValues { .double($0) }) }) }
    public mutating func predict(_ id: String, _ p: Prediction) {
        if entries[id]?["a"] != nil { return }
        entries[id] = ["p": p.rating, "c": p.confidence, "t": Date().timeIntervalSince1970]
    }
    /// يُسجَّل التقييم الفعلي (أول مرة فقط) — خطأ واحد لا يغيّر النموذج كثيرًا لأنه يُستخدم مع البقية.
    public mutating func resolve(_ id: String, actual: Double) {
        guard var e = entries[id], e["a"] == nil, actual > 0 else { return }
        e["a"] = actual; e["ta"] = Date().timeIntervalSince1970; entries[id] = e
    }
    public var resolved: [(id: String, p: Double, a: Double, c: Double, t: Double)] {
        entries.compactMap { k, e in e["a"].map { (k, e["p"] ?? 0, $0, e["c"] ?? 0, e["ta"] ?? e["t"] ?? 0) } }.sorted { $0.t < $1.t }
    }
    /// الدقة: متوسط الخطأ، نسبة ±0.5، المعايرة (خطأ عالي/منخفض الثقة)، والتحسن (الأقدم مقابل الأحدث).
    public var metrics: (n: Int, mae: Double, within05: Double, maeHighConf: Double?, maeLowConf: Double?, improving: Double?) {
        let r = resolved; if r.isEmpty { return (0, 0, 0, nil, nil, nil) }
        func mae(_ l: [(id: String, p: Double, a: Double, c: Double, t: Double)]) -> Double { l.reduce(0) { $0 + abs($1.p - $1.a) } / Double(l.count) }
        let hi = r.filter { $0.c >= 0.6 }, lo = r.filter { $0.c < 0.6 }
        let half = r.count / 2
        return (r.count, mae(r), Double(r.filter { abs($0.p - $0.a) <= 0.5 }.count) / Double(r.count),
                hi.isEmpty ? nil : mae(hi), lo.isEmpty ? nil : mae(lo), r.count >= 6 ? mae(Array(r.prefix(half))) - mae(Array(r.suffix(r.count - half))) : nil)
    }
}

// MARK: Anomalies

public struct Anomaly: Identifiable, Sendable { public let p: Performer; public let actual, expected: Double; public var id: String { p.id } }

/// تقييمات تخالف نمطك المعتاد بوضوح (تُعامل كاستثناءات مثيرة، لا كأخطاء). كل سجل يُقارن بنموذج لا يراه (leave-one-out).
public func tasteAnomalies(_ s: [Sample], threshold: Double = 1.5) -> [Anomaly] {
    if s.count < 10 { return [] }
    return s.compactMap { x in
        guard let pr = predictRating(x.f, samples: s, excludeId: x.p.id), pr.confidence >= 0.3, abs(pr.rating - x.y) >= threshold else { return nil }
        return Anomaly(p: x.p, actual: x.y, expected: pr.rating)
    }.sorted { abs($0.actual - $0.expected) > abs($1.actual - $1.expected) }
}

// MARK: Preference shifts

public struct Shift: Identifiable, Sendable {
    public let key: String; public let recent, before: Double; public let nRecent, nBefore: Int
    public var id: String { key }
    public var delta: Double { recent - before }
    public var label: String { key.hasPrefix("st:") ? "استوديو \(key.dropFirst(3))" : key.hasPrefix("tg:") ? "وسم \(key.dropFirst(3))" : traitLabel(key) }
}

/// يقارن آخر [days] يومًا بما قبلها: نسبة الخاصية بين من أضفتهن (مفضلة أو 4+)، ونسبة الاستوديو/الوسم بين ما شاهدته.
public func preferenceShifts(lib: [Performer], feats: [String: Features], works: [WorkGroup], days: Int, now: Date = Date()) -> (rising: [Shift], falling: [Shift], emerging: [Shift]) {
    let cut = (now.timeIntervalSince1970 - Double(days) * 86400) * 1000
    let liked = lib.filter { !$0.isMinor && ($0.fav || $0.rating >= 4) && feats[$0.id] != nil && $0.added > 0 }
    let rec = liked.filter { Double($0.added) >= cut }, old = liked.filter { Double($0.added) < cut }
    var shifts: [Shift] = []
    func share(_ ps: [Performer], _ k: String) -> Double { ps.isEmpty ? 0 : Double(ps.filter { traitKeys(feats[$0.id]!).contains(k) }.count) / Double(ps.count) }
    if rec.count >= 3 && old.count >= 3 {
        for k in Set((rec + old).flatMap { traitKeys(feats[$0.id]!) }) { shifts.append(Shift(key: k, recent: share(rec, k), before: share(old, k), nRecent: rec.count, nBefore: old.count)) }
    }
    let cutDay = todayStr(Date(timeIntervalSince1970: cut / 1000))
    let wr = works.filter { $0.seen && $0.wd >= cutDay }, wo = works.filter { $0.seen && !$0.wd.isEmpty && $0.wd < cutDay }
    if wr.count >= 5 && wo.count >= 5 {
        var keys = Set<String>(); for g in wr + wo { if !g.s.isEmpty { keys.insert("st:\(g.s)") }; for t in g.tg.prefix(6) { keys.insert("tg:\(t)") } }
        func ws(_ l: [FavCore.WorkGroup], _ k: String) -> Double {
            Double(l.filter { k.hasPrefix("st:") ? $0.s == String(k.dropFirst(3)) : $0.tg.contains(String(k.dropFirst(3))) }.count) / Double(l.count)
        }
        for k in keys { shifts.append(Shift(key: k, recent: ws(wr, k), before: ws(wo, k), nRecent: wr.count, nBefore: wo.count)) }
    }
    let rising = shifts.filter { $0.delta >= 0.15 && $0.before > 0 }.sorted { $0.delta > $1.delta }
    let falling = shifts.filter { $0.delta <= -0.15 }.sorted { $0.delta < $1.delta }
    let emerging = shifts.filter { $0.before == 0 && $0.recent >= 0.25 }.sorted { $0.recent > $1.recent }
    return (Array(rising.prefix(8)), Array(falling.prefix(8)), Array(emerging.prefix(6)))
}

// MARK: Hidden patterns (works)

public struct Pattern: Identifiable, Sendable { public let title: String; public let evidence: String; public let n: Int; public let lift: Double; public let ids: [String]; public var id: String { title } }

/// أنماط ليست واضحة: تراكيب استوديو×وسم أو وسم×وسم تقييمك لها أعلى بوضوح من متوسطك في الأعمال (دعم ≥3، فرق ≥0.6).
public func hiddenPatterns(_ works: [WorkGroup]) -> [Pattern] {
    let rated = works.filter { $0.r > 0 }
    if rated.count < 10 { return [] }
    let base = Double(rated.reduce(0) { $0 + $1.r }) / Double(rated.count)
    let sd = max(0.5, (rated.reduce(0) { $0 + pow(Double($1.r) - base, 2) } / Double(rated.count)).squareRoot())
    var by: [String: [FavCore.WorkGroup]] = [:]
    for g in rated {
        let tags = Array(Set(g.tg.prefix(6))).sorted()
        for t in tags where !g.s.isEmpty { by["الاستوديو \(g.s) مع وسم «\(t)»", default: []].append(g) }
        for i in 0..<tags.count { for j in (i + 1)..<max(i + 1, tags.count) where j < tags.count { by["الوسمان «\(tags[i])» و«\(tags[j])» معًا", default: []].append(g) } }
    }
    return by.compactMap { k, l -> Pattern? in
        guard l.count >= 3 else { return nil }
        let m = Double(l.reduce(0) { $0 + $1.r }) / Double(l.count)
        let z = (m - base) / (sd / Double(l.count).squareRoot())
        guard m - base >= 0.6, z >= 2 else { return nil }
        return Pattern(title: k, evidence: "متوسط تقييمك \(String(format: "%.1f", m)) مقابل \(String(format: "%.1f", base)) عمومًا — في \(l.count) أعمال", n: l.count, lift: m - base, ids: l.map(\.key))
    }.sorted { $0.lift * Double($0.n) > $1.lift * Double($1.n) }.prefix(12).map { $0 }
}

// MARK: Personal insights

public struct Insight: Identifiable, Sendable {
    public let id: String; public let title, explanation, evidence: String; public let confidence: Double; public let related: [String]; public var discovered: Double = 0
}

/// ملاحظات ذات معنى، كل واحدة بدليلها وثقتها والسجلات المرتبطة. [seen]: متى اكتُشفت أول مرة (يُحفظ).
public func insights(dna: TasteDNA, shifts: (rising: [Shift], falling: [Shift], emerging: [Shift]), works: [WorkGroup], lib: [Performer], workTaste: WorkTaste, seen: [String: Double]) -> [Insight] {
    var out: [Insight] = []
    if dna.sufficient, let e = dna.strong.first {
        out.append(Insight(id: "dna:\(e.key)", title: "أقوى ما يرفع تقييمك: \(e.label)", explanation: "الممثلات بهذه الخاصية تقيّمهن أعلى من متوسطك بـ \(String(format: "%.1f", e.effect)).",
                           evidence: "\(e.n) ممثلة، متوسط \(String(format: "%.1f", e.mean)) مقابل \(String(format: "%.1f", dna.baseline))", confidence: e.confidence, related: []))
    }
    if let c = dna.synergies.first {
        out.append(Insight(id: "combo:\(c.id)", title: "تركيب يعجبك أكثر من مجموع أجزائه", explanation: "\(c.label): تقييمك لها أعلى مما تتوقعه كل خاصية وحدها.",
                           evidence: "\(c.n) ممثلات، متوسط \(String(format: "%.1f", c.mean)) مقابل المتوقع \(String(format: "%.1f", c.expected))", confidence: c.confidence, related: []))
    }
    if let r = shifts.rising.first {
        out.append(Insight(id: "rise:\(r.key)", title: "اهتمام يزداد مؤخرًا: \(r.label)", explanation: "نسبته فيما أضفته/شاهدته مؤخرًا أعلى بوضوح مما قبله.",
                           evidence: "\(Int((r.recent * 100).rounded()))٪ مؤخرًا مقابل \(Int((r.before * 100).rounded()))٪ قبل (من \(r.nRecent) مقابل \(r.nBefore))", confidence: min(1, Double(r.nRecent) / 10), related: []))
    }
    if let e = shifts.emerging.first {
        out.append(Insight(id: "emerge:\(e.key)", title: "نمط جديد يظهر: \(e.label)", explanation: "لم يكن موجودًا قبل الفترة الأخيرة.", evidence: "\(Int((e.recent * 100).rounded()))٪ مؤخرًا (من \(e.nRecent))", confidence: min(1, Double(e.nRecent) / 10), related: []))
    }
    if let st = workTaste.top("st:", k: 1).first, st.avgR >= 4, st.n >= 3 {
        out.append(Insight(id: "studio:\(st.key)", title: "استوديو يتفوق في تقييماتك: \(st.label)", explanation: "متوسط تقييمك لأعماله مرتفع باستمرار.", evidence: "\(st.n) أعمال، متوسط \(String(format: "%.1f", st.avgR))", confidence: min(1, Double(st.n) / 8), related: []))
    }
    // مفضلات أهملتها مؤخرًا: لها أعمال لم تشاهدها، ولم تشاهد لها شيئًا منذ 90 يومًا
    let cut = todayStr(Date().addingTimeInterval(-90 * 86400))
    let neglected = lib.filter { p in p.fav && works.contains { g in !g.seen && g.who.contains { $0.id == p.id } } && !works.contains { g in g.seen && g.wd >= cut && g.who.contains { $0.id == p.id } } }
    if neglected.count >= 2 {
        out.append(Insight(id: "neglect:\(neglected.count)", title: "مفضلات لم تعد إليهن مؤخرًا", explanation: "لهن أعمال لم تشاهدها، ولم تشاهد لهن شيئًا منذ 3 أشهر.",
                           evidence: neglected.prefix(4).map(\.name).joined(separator: "، ") + (neglected.count > 4 ? " و\(neglected.count - 4) أخريات" : ""), confidence: 0.9, related: neglected.map(\.id)))
    }
    // نمط متكرر عبر السنوات: استوديو حاضر فيما شاهدته في 3 سنوات فأكثر
    var studioYears: [String: Set<String>] = [:]
    for g in works where g.seen && g.wd.count >= 4 && !g.s.isEmpty { studioYears[g.s, default: []].insert(String(g.wd.prefix(4))) }
    if let top = studioYears.filter({ $0.value.count >= 3 }).max(by: { $0.value.count < $1.value.count }) {
        let st = top.key, ys = top.value
        out.append(Insight(id: "years:\(st)", title: "رفيق سنوات: \(st)", explanation: "تعود لأعماله سنة بعد سنة.", evidence: "شاهدت له في \(ys.count) سنوات: \(ys.sorted().joined(separator: "، "))", confidence: 0.85, related: []))
    }
    let now = Date().timeIntervalSince1970
    return out.map { var i = $0; i.discovered = seen[i.id] ?? now; return i }
}

// MARK: Active learning

public struct SmartQuestion: Identifiable, Sendable { public let id: String; public let field: String; public let text: String; public let why: String }

/// سؤال واحد مفيد حين يكون المحرك غير متأكد: الخاصية التي أثرها متوسط ودعمها قليل (أكبر شك متوقع)، ولم تُسأل من قبل.
public func nextQuestion(dna: TasteDNA, answered: Set<String>) -> SmartQuestion? {
    var fieldScore: [String: (Double, TraitEffect)] = [:]
    for e in dna.effects where e.n >= 2 {
        let f = String(e.key.split(separator: "=")[0])
        if answered.contains(f) { continue }
        let uncertainty = abs(e.effect) * (1 - min(1, Double(e.n) / Double(e.n + 4)))
        if uncertainty > (fieldScore[f]?.0 ?? 0) { fieldScore[f] = (uncertainty, e) }
    }
    guard let top = fieldScore.max(by: { $0.value.0 < $1.value.0 }), top.value.0 > 0.05 else { return nil }
    let f = top.key, e = top.value.1
    return SmartQuestion(id: "q:\(f)", field: f, text: "هل «\(fieldNames[f] ?? f)» مهم لك عند تقييم ممثلة؟",
                         why: "لاحظت أن \(e.label) \(e.effect >= 0 ? "يرفع" : "يخفض") تقييمك قليلًا، لكن من \(e.n) ممثلات فقط — جوابك يحسم ذلك.")
}

/// أوزان المستخدم للحقول من إجاباته: أهم ×1.5، عادي ×1، غير مهم ×0.3.
public func userFieldWeights(_ answers: [String: String]) -> [String: Double] {
    answers.mapValues { $0 == "more" ? 1.5 : $0 == "less" ? 0.3 : 1 }
}

// MARK: Preference memory

public struct LearnedPreference: Identifiable, Sendable {
    public let id: String; public let description, evidence: String; public let confidence: Double; public let kind: String   // trait | combo | negative | archetype
    public var status: String = "inferred"; public var first: Double = 0, last: Double = 0; public var history: [String] = []
}

/// ما تعلّمه التطبيق عن ذوقك (مستنتج — لا يُعامل كحقيقة حتى تؤكده). الحالات: inferred / confirmed / rejected.
public func learnedPreferences(dna: TasteDNA, archetypes arch: [Archetype], memory: JSONObject) -> [LearnedPreference] {
    var out: [LearnedPreference] = []
    for e in dna.strong + dna.secondary { out.append(LearnedPreference(id: "t:\(e.key)", description: "تميل لـ \(e.label)", evidence: "\(e.n) ممثلة، +\(String(format: "%.1f", e.effect)) عن متوسطك", confidence: e.confidence, kind: "trait")) }
    for e in dna.negative { out.append(LearnedPreference(id: "n:\(e.key)", description: "تقلّ تقييماتك مع \(e.label)", evidence: "\(e.n) ممثلة، \(String(format: "%.1f", e.effect)) عن متوسطك", confidence: e.confidence, kind: "negative")) }
    for c in dna.synergies.prefix(5) { out.append(LearnedPreference(id: "c:\(c.id)", description: "التركيب: \(c.label)", evidence: "\(c.n) ممثلات، أعلى من المتوقع بـ \(String(format: "%.1f", c.interaction))", confidence: c.confidence, kind: "combo")) }
    for a in arch { out.append(LearnedPreference(id: a.id, description: "نمط «\(a.name)»", evidence: "\(a.members.count) ممثلات، متوسط \(String(format: "%.1f", a.avgRating))", confidence: min(1, Double(a.members.count) / 8), kind: "archetype")) }
    let now = Date().timeIntervalSince1970
    return out.map { var p = $0
        let m = memory[p.id]?.object ?? [:]
        p.status = m["s"]?.string ?? "inferred"; p.first = m["f"]?.number ?? now; p.last = m["l"]?.number ?? now
        p.history = (m["h"]?.array ?? []).map(\.text)
        return p
    }
}

// MARK: Recommendation portfolio + simulator

public struct Scored: Identifiable, Sendable { public let c: RecCand; public let score: Double; public let confidence: Double; public let why, diff: [String]; public var id: String { c.id } }

/// يقيّم مرشحات الاقتراح بذوقك (مع أوزان مؤقتة للمحاكاة دون حفظها).
public func scoreCandidates(_ cands: [RecCand], feats: [String: Features], profile: TasteProfile, feedback: [String: Double] = [:], fieldWeights: [String: Double] = [:], rejected: Set<String> = []) -> [Scored] {
    cands.compactMap { c in
        guard c.adult else { return nil }
        let f = (feats[c.id] ?? [:]).filter { k, v in !rejected.contains("t:\(k)=\(v.str ?? "")") }
        let sim = similarity(profile, f, fb: feedback, weights: fieldWeights)
        let coverage = min(1, Double(f.count) / 6)
        let score = f.isEmpty ? c.score * 0.6 : 0.7 * sim.score + 0.3 * c.score
        return Scored(c: c, score: score, confidence: coverage * (profile.sufficient ? 1 : 0.5), why: c.reasons + sim.why, diff: sim.diff)
    }.sorted { $0.score > $1.score }
}

public struct Portfolio: Sendable { public var safe: [Scored] = [], newTerritory: [Scored] = [], unexpected: [Scored] = [], highConfidence: [Scored] = [] }

/// مسارات الاقتراح: آمن، أرض جديدة، مفاجأة ذات معنى، ثقة عالية — بلا تكرار بين المسارات.
public func portfolio(_ scored: [Scored], per: Int = 8) -> Portfolio {
    var used = Set<String>(), p = Portfolio()
    func take(_ l: [Scored]) -> [Scored] { var o: [Scored] = []; for x in l where !used.contains(x.id) && o.count < per { o.append(x); used.insert(x.id) }; return o }
    p.highConfidence = take(scored.filter { $0.confidence >= 0.75 && $0.score >= 0.6 })
    p.safe = take(scored.filter { $0.score >= 0.55 })
    p.unexpected = take(scored.filter { $0.score >= 0.35 && $0.score < 0.55 && !$0.c.withSeeds.isEmpty })
    p.newTerritory = take(Array(scored.filter { $0.score < 0.4 && $0.confidence >= 0.4 }.reversed()))
    return p
}

/// محاكي «ماذا لو؟»: يعيد ترتيب المرشحات بأوزان مؤقتة ويُظهر من صعد ومن نزل — دون تغيير ملفك الحقيقي.
public func simulate(_ cands: [RecCand], feats: [String: Features], profile: TasteProfile, base: [String: Double], trial: [String: Double]) -> [(c: RecCand, before: Int, after: Int)] {
    let a = scoreCandidates(cands, feats: feats, profile: profile, fieldWeights: base).map(\.c.id)
    let b = scoreCandidates(cands, feats: feats, profile: profile, fieldWeights: trial)
    let idxA = Dictionary(uniqueKeysWithValues: a.enumerated().map { ($1, $0) })
    return b.enumerated().map { i, s in (s.c, idxA[s.c.id] ?? i, i) }
}

// MARK: Knowledge graph

/// رسم معرفي: ممثلات ↔ أعمال ↔ استوديوهات ↔ وسوم ↔ قوائم (من بياناتك فقط، بلا علاقات مخترعة).
public struct KnowledgeGraph: Sendable {
    public private(set) var edges: [String: Set<String>] = [:]
    public private(set) var labels: [String: String] = [:]
    public init(lib: [Performer], works: [WorkGroup], lists: [JSONObject]) {
        for p in lib { labels["p:\(p.id)"] = p.name; for l in p.lists { link("p:\(p.id)", "l:\(l)") }; for t in p.tags { link("p:\(p.id)", "t:\(norm(t))"); labels["t:\(norm(t))"] = t } }
        for l in lists { if let id = l["id"]?.string { labels["l:\(id)"] = l["name"]?.text ?? id } }
        for g in works {
            labels["w:\(g.key)"] = g.t
            for p in g.who { link("w:\(g.key)", "p:\(p.id)") }
            if !g.s.isEmpty { link("w:\(g.key)", "s:\(norm(g.s))"); labels["s:\(norm(g.s))"] = g.s }
            for t in g.tg { link("w:\(g.key)", "t:\(norm(t))"); labels["t:\(norm(t))"] = t }
        }
    }
    mutating func link(_ a: String, _ b: String) { edges[a, default: []].insert(b); edges[b, default: []].insert(a) }
    public func neighbors(_ n: String) -> [String] { Array(edges[n] ?? []) }
    /// أقصر طريق بين عقدتين (مثلًا ممثلتان عبر عمل مشترك أو استوديو).
    public func path(_ a: String, _ b: String, maxDepth: Int = 6) -> [String]? {
        if a == b { return [a] }
        var prev: [String: String] = [a: a], q = [a], depth = 0
        while !q.isEmpty && depth < maxDepth {
            var next: [String] = []
            for x in q { for y in edges[x] ?? [] where prev[y] == nil {
                prev[y] = x
                if y == b { var p = [b]; var c = b; while c != a { c = prev[c]!; p.append(c) }; return p.reversed() }
                next.append(y)
            } }
            q = next; depth += 1
        }
        return nil
    }
    /// ممثلات مرتبطة بأخرى بطريق غير مباشر: عمل مشترك (قوي)، نفس الاستوديو أو الوسم (أضعف).
    public func related(performer id: String, k: Int = 10) -> [(String, Double, String)] {
        var score: [String: (Double, String)] = [:]
        for w in edges["p:\(id)"] ?? [] where w.hasPrefix("w:") {
            for x in edges[w] ?? [] where x.hasPrefix("p:") && x != "p:\(id)" { score[x] = ((score[x]?.0 ?? 0) + 1, "عمل مشترك: \(labels[w] ?? "")") }
            for s in edges[w] ?? [] where s.hasPrefix("s:") { for w2 in edges[s] ?? [] { for x in edges[w2] ?? [] where x.hasPrefix("p:") && x != "p:\(id)" { if score[x] == nil || score[x]!.0 < 0.2 { score[x] = ((score[x]?.0 ?? 0) + 0.05, "نفس الاستوديو: \(labels[s] ?? "")") } } } }
        }
        return score.sorted { $0.value.0 > $1.value.0 }.prefix(k).map { (String($0.key.dropFirst(2)), $0.value.0, $0.value.1) }
    }
}

// MARK: Library health, cleanup, detective, gems, hall of fame

public struct HealthIssue: Identifiable, Sendable { public let id: String; public let kind, title, detail: String; public let performerIds: [String] }

/// صحة المكتبة: درجة 0–100 + مشكلات مع اقتراحات آمنة (لا شيء يُطبَّق بلا تأكيدك).
public func libraryHealth(_ lib: [Performer]) -> (score: Int, issues: [HealthIssue]) {
    var issues: [HealthIssue] = []
    let checks = lib.map { completeness($0) }
    let filled = checks.reduce(0) { $0 + $1.filter(\.1).count }, total = max(1, checks.reduce(0) { $0 + $1.count })
    var byName: [String: [Performer]] = [:]; for p in lib { byName[norm(p.name), default: []].append(p) }
    for (n, l) in byName where l.count > 1 { issues.append(HealthIssue(id: "dup:\(n)", kind: "duplicate", title: "تكرار محتمل: \(l[0].name)", detail: "\(l.count) سجلات بنفس الاسم — راجعها قبل الدمج", performerIds: l.map(\.id))) }
    for p in lib {
        let d = dedupeWorks(p.works).removed
        if d > 0 { issues.append(HealthIssue(id: "dw:\(p.id)", kind: "dupWorks", title: "أعمال مكررة عند \(p.name)", detail: "\(d) عمل مكرر يمكن دمجه بلا فقد بيانات", performerIds: [p.id])) }
        if !p.birth.isEmpty && sdAge(p.birth).invalid { issues.append(HealthIssue(id: "bd:\(p.id)", kind: "badDate", title: "تاريخ ميلاد غير صالح: \(p.name)", detail: p.birth, performerIds: [p.id])) }
        if p.photos.isEmpty { issues.append(HealthIssue(id: "np:\(p.id)", kind: "noPhoto", title: "بلا صور: \(p.name)", detail: "أضف صورة أو حدّثها من المصدرين", performerIds: [p.id])) }
        if p.stashIds.isEmpty && p.pdbIds.isEmpty { issues.append(HealthIssue(id: "nl:\(p.id)", kind: "unlinked", title: "غير مرتبطة بمصدر: \(p.name)", detail: "اربطها بـ StashDB أو ThePornDB لتكتمل بياناتها", performerIds: [p.id])) }
    }
    let penalty = min(40, issues.filter { ["duplicate", "badDate", "dupWorks"].contains($0.kind) }.count * 2)
    return (max(0, Int((Double(filled) / Double(total) * 100).rounded()) - penalty), issues)
}

public struct FieldConflict: Identifiable, Sendable { public let field, stash, tpdb: String; public var id: String { field } }

/// محقق البيانات: يقارن ما يقوله كل مصدر رسمي عن الحقل نفسه ويُظهر الاختلاف بمصدره.
public func dataDetective(stash s: JSONObject?, tpdb t: JSONObject?) -> [FieldConflict] {
    guard let s, let t else { return [] }
    let tt = tpdbAsStash(t)
    var out: [FieldConflict] = []
    for (k, label) in [("birth_date", "تاريخ الميلاد"), ("country", "البلد"), ("height", "الطول"), ("hair_color", "لون الشعر"), ("eye_color", "لون العيون"), ("ethnicity", "العرق"), ("breast_type", "الصدر"), ("career_start_year", "بداية المسيرة")] {
        let a = s[k]?.text ?? "", b = tt[k]?.text ?? ""
        if a.isEmpty || b.isEmpty { continue }
        let same = k == "height" ? abs((Double(a) ?? 0) - (Double(b) ?? 0)) <= 2 : a.uppercased() == b.uppercased()
        if !same { out.append(FieldConflict(field: label, stash: k == "hair_color" || k == "eye_color" || k == "ethnicity" ? attrLabel(k, a) : a, tpdb: k == "hair_color" || k == "eye_color" || k == "ethnicity" ? attrLabel(k, b) : b)) }
    }
    return out
}

/// جواهر مخفية: مقيّمة عاليًا (4+) لكنها نادرًا ما تُزار ولها أعمال لم تشاهدها.
public func hiddenGems(_ lib: [Performer], _ works: [WorkGroup]) -> [Performer] {
    lib.filter { p in p.rating >= 4 && p.views <= 2 && works.contains { g in !g.seen && g.who.contains { $0.id == p.id } } }.sorted { $0.rating > $1.rating }
}

/// قاعة المشاهير لسنة: الأعلى تقييمًا ممن أُضفن فيها، والأعمال المشاهدة الأعلى تقييمًا، والاستوديوهات (3 أعمال فأكثر).
public func hallOfFame(_ lib: [Performer], _ works: [WorkGroup], year: Int) -> (performers: [Performer], works: [WorkGroup], studios: [(String, Double, Int)]) {
    let ps = lib.filter { gregorian.component(.year, from: Date(timeIntervalSince1970: Double($0.added) / 1000)) == year && $0.rating > 0 }.sorted { $0.rating > $1.rating }
    let ws = works.filter { $0.seen && $0.wd.hasPrefix("\(year)") && $0.r > 0 }.sorted { $0.r > $1.r }
    var st: [String: [Int]] = [:]; for g in ws where !g.s.isEmpty { st[g.s, default: []].append(g.r) }
    let studios = st.filter { $0.value.count >= 3 }.map { ($0.key, Double($0.value.reduce(0, +)) / Double($0.value.count), $0.value.count) }.sorted { $0.1 > $1.1 }
    return (Array(ps.prefix(10)), Array(ws.prefix(10)), Array(studios.prefix(5)))
}

// MARK: Personal AI analyst (local query engine)

public struct AnalystAnswer: Sendable { public let text: String; public let refs: [String]; public let uncertainty: String }

public struct AnalystContext: Sendable {
    public let lib: [Performer]; public let works: [WorkGroup]; public let feats: [String: Features]; public let dna: TasteDNA
    public let predictions: PredictionLog; public let workTaste: WorkTaste
    public init(lib: [Performer], works: [WorkGroup], feats: [String: Features], dna: TasteDNA, predictions: PredictionLog, workTaste: WorkTaste) {
        self.lib = lib; self.works = works; self.feats = feats; self.dna = dna; self.predictions = predictions; self.workTaste = workTaste
    }
}

/// المحلل الشخصي: يفهم السؤال (عربي/إنجليزي)، ينفّذ الاستعلام على بياناتك المحلية، ويجيب بمراجع حقيقية وحدود واضحة.
/// لا يخترع أرقامًا: كل رقم محسوب من سجلاتك.
public func analyze(_ question: String, _ c: AnalystContext, now: Date = Date()) -> AnalystAnswer {
    let q = arNorm(question)
    func has(_ words: String...) -> Bool { words.contains { q.contains(arNorm($0)) } }
    let year = ymd(now).0
    if has("تغير", "تغيّر", "changed", "اختلف") && has("ذوق", "taste") {
        let s = preferenceShifts(lib: c.lib, feats: c.feats, works: c.works, days: 365, now: now)
        if s.rising.isEmpty && s.falling.isEmpty && s.emerging.isEmpty { return AnalystAnswer(text: "لا تغيّر واضح في ذوقك خلال السنة (أو البيانات قليلة).", refs: [], uncertainty: "يحتاج 3 مفضلات جديدة و5 مشاهدات على الأقل في كل فترة.") }
        let lines = s.rising.prefix(3).map { "↑ \($0.label): \(Int(($0.recent * 100).rounded()))٪ مقابل \(Int(($0.before * 100).rounded()))٪" }
            + s.falling.prefix(3).map { "↓ \($0.label): \(Int(($0.recent * 100).rounded()))٪ مقابل \(Int(($0.before * 100).rounded()))٪" }
            + s.emerging.prefix(2).map { "جديد: \($0.label)" }
        return AnalystAnswer(text: "مقارنة آخر سنة بما قبلها:\n" + lines.joined(separator: "\n"), refs: [], uncertainty: "نسب من إضافاتك ومشاهداتك — ارتباط لا سبب.")
    }
    if has("ناقص", "مكتمل", "incomplete", "اكتمال") {
        let h = libraryHealth(c.lib)
        let low = c.lib.map { ($0, completeness($0).filter(\.1).count) }.sorted { $0.1 < $1.1 }.prefix(8)
        return AnalystAnswer(text: "صحة مكتبتك \(h.score)/100. الأقل اكتمالًا: " + low.map { "\($0.0.name) (\($0.1)/7)" }.joined(separator: "، "), refs: low.map { $0.0.id }, uncertainty: "")
    }
    if has("متاكد", "متأكد", "uncertain", "شك") {
        let unsure = c.dna.effects.filter { $0.n >= 2 && $0.n < 5 && abs($0.effect) >= 0.2 }.prefix(5)
        if unsure.isEmpty { return AnalystAnswer(text: "لا تفضيلات غامضة واضحة الآن.", refs: [], uncertainty: "") }
        return AnalystAnswer(text: "أقل ما أنا متأكد منه:\n" + unsure.map { "• \($0.label): أثر \(String(format: "%+.1f", $0.effect)) من \($0.n) فقط" }.joined(separator: "\n"), refs: [], uncertainty: "الدعم قليل — جاوب الأسئلة الذكية لتحسمه.")
    }
    if has("تنبؤ", "توقع", "prediction") && has("خطا", "خطأ", "غلط", "inaccurate", "دقه", "دقة") {
        let m = c.predictions.metrics
        if m.n == 0 { return AnalystAnswer(text: "لا تنبؤات مقارنة بتقييم فعلي بعد.", refs: [], uncertainty: "") }
        let worst = c.predictions.resolved.sorted { abs($0.p - $0.a) > abs($1.p - $1.a) }.prefix(5)
        let names = Dictionary(uniqueKeysWithValues: c.lib.map { ($0.id, $0.name) })
        return AnalystAnswer(text: "من \(m.n) تنبؤ: متوسط الخطأ \(String(format: "%.2f", m.mae)) نجمة، و\(Int((m.within05 * 100).rounded()))٪ ضمن ±0.5.\nالأكثر خطأ: " +
                             worst.map { "\(names[$0.id] ?? $0.id) (توقعت \(String(format: "%.1f", $0.p)) وقيّمت \(String(format: "%.1f", $0.a)))" }.joined(separator: "، "), refs: worst.map(\.id), uncertainty: "")
    }
    if has("اضفت", "أضفت", "added") {
        let cal = gregorian; let lm = cal.date(byAdding: .month, value: -1, to: now)!
        let y = cal.component(.year, from: lm), mo = cal.component(.month, from: lm)
        let l = c.lib.filter { let d = Date(timeIntervalSince1970: Double($0.added) / 1000); return cal.component(.year, from: d) == y && cal.component(.month, from: d) == mo }
        return AnalystAnswer(text: l.isEmpty ? "لم تضف أحدًا الشهر الماضي." : "أضفت \(l.count) الشهر الماضي: " + l.prefix(12).map(\.name).joined(separator: "، "), refs: l.map(\.id), uncertainty: "")
    }
    if has("تشابه", "متشابه", "similar") && has("تقييم", "rating") {
        let s = samples(c.lib, c.feats)
        guard s.count >= 4 else { return AnalystAnswer(text: "تحتاج 4 ممثلات مقيّمات بمعايير على الأقل.", refs: [], uncertainty: "") }
        var best: [(Performer, Performer, Double)] = []
        let rated = c.lib.filter { $0.criteriaValues.count >= 4 }
        for i in 0..<rated.count { for j in (i + 1)..<max(i + 1, rated.count) where j < rated.count {
            let a = rated[i].criteriaValues, b = rated[j].criteriaValues
            let keys = Set(a.keys).intersection(b.keys); if keys.count < 4 { continue }
            let d = keys.reduce(0) { $0 + abs(a[$1]! - b[$1]!) } / Double(keys.count)
            best.append((rated[i], rated[j], d))
        } }
        let top = best.sorted { $0.2 < $1.2 }.prefix(5)
        return AnalystAnswer(text: top.isEmpty ? "لا يكفي التقييم بالمعايير للمقارنة." : "الأكثر تشابهًا في نمط تقييمك (المعايير الثمانية):\n" + top.map { "• \($0.0.name) و\($0.1.name) — فرق \(String(format: "%.2f", $0.2))" }.joined(separator: "\n"),
                             refs: top.flatMap { [$0.0.id, $0.1.id] }, uncertainty: "")
    }
    if has("نمط", "انماط", "أنماط", "pattern") {
        let p = hiddenPatterns(c.works)
        let dnaLines = c.dna.strong.prefix(3).map { "• \($0.label): +\(String(format: "%.1f", $0.effect)) (من \($0.n))" } + c.dna.synergies.prefix(2).map { "• \($0.label): أعلى من المتوقع بـ \(String(format: "%.1f", $0.interaction)) (من \($0.n))" }
        let lines = dnaLines + p.prefix(3).map { "• \($0.title): \($0.evidence)" }
        return AnalystAnswer(text: lines.isEmpty ? "لا أنماط ذات دلالة إحصائية بعد." : "أقوى الأنماط في سجلاتك الأعلى تقييمًا:\n" + lines.joined(separator: "\n"), refs: [], uncertainty: "ارتباطات من بياناتك — ليست أسبابًا مؤكدة.")
    }
    if has("لماذا", "ليش", "why") && has("عمل", "اعمال", "أعمال", "work") {
        let rated = c.works.filter { $0.r > 0 }
        let hi = rated.filter { $0.r >= 4 }, lo = rated.filter { $0.r <= 2 }
        func top(_ l: [FavCore.WorkGroup]) -> String { var m: [String: Int] = [:]; for g in l { if !g.s.isEmpty { m[g.s, default: 0] += 1 } }; return m.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) (\($0.value))" }.joined(separator: "، ") }
        return AnalystAnswer(text: "أعمال قيّمتها عاليًا (\(hi.count)) أكثرها من: \(top(hi)).\nأعمال قيّمتها منخفضًا (\(lo.count)) أكثرها من: \(top(lo)).", refs: [], uncertainty: "الاستوديو مؤشر واحد فقط.")
    }
    if has("خارج", "outside") {
        return AnalystAnswer(text: "افتح «اكتشف» ← مسار «أرض جديدة»: مرشحات بعيدة عن نمطك المعتاد لكن بثقة كافية.", refs: [], uncertainty: "")
    }
    let watchedYear = c.works.filter { $0.seen && $0.wd.hasPrefix("\(year)") }.count
    return AnalystAnswer(text: "مكتبتك: \(c.lib.count) ممثلة، \(c.works.count) عمل، شاهدت \(watchedYear) هذه السنة. اسألني مثلًا: «ماذا تغيّر في ذوقي هذه السنة؟»، «ما أقوى الأنماط؟»، «ما الناقص في مكتبتي؟»، «أي تنبؤاتك أخطأت؟».",
                         refs: [], uncertainty: "لم أفهم السؤال تحديدًا.")
}
