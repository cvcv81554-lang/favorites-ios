import Foundation

// «مقاطع»: خلاصة عمودية بخوارزمية محلية تتعلم من سلوكك (لا يُرسل شيء لأي جهة).

/// [src]: المصدر الظاهر؛ [start]/[len]: مقطع قصير من فيديو كامل (ثوانٍ، 0 = كامل)؛ [full]: فيديو كامل.
public struct Reel: Identifiable, Sendable {
    public let g: WorkGroup; public let url, why, src: String; public let explore, full: Bool; public let start, len: Int
    public init(g: WorkGroup, url: String, why: String, explore: Bool = false, src: String = "ThePornDB · إعلان", start: Int = 0, len: Int = 0, full: Bool = false) {
        self.g = g; self.url = url; self.why = why; self.explore = explore; self.src = src; self.start = start; self.len = len; self.full = full
    }
    public var key: String { g.key + (start > 0 ? "@\(start)" : "") + (full ? "#full" : "") }
    public var id: String { key }
    public func variant(start: Int = 0, len: Int = 0, full: Bool = false, src: String? = nil) -> Reel {
        Reel(g: g, url: url, why: why, explore: explore, src: src ?? self.src, start: start, len: len, full: full)
    }
}

/// دمج خلاصتين بالتناوب ([bPerA] من b لكل واحد من a) بلا تكرار.
public func weave(_ a: [Reel], _ b: [Reel], bPerA: Int = 2) -> [Reel] {
    var out: [Reel] = [], seen = Set<String>(), i = 0, j = 0
    func add(_ r: Reel) { if seen.insert(r.key).inserted { out.append(r) } }
    while i < a.count || j < b.count {
        if i < a.count { add(a[i]); i += 1 }
        var k = 0; while k < bPerA && j < b.count { add(b[j]); j += 1; k += 1 }
    }
    return out
}

/// إشارات المشاهدة المحفوظة: clips[مفتاح العمل] = {n ظهور، w أعلى نسبة، l إعجاب، h مخفي، s محفوظ، v آخر مشاهدة، t ثوانٍ}،
/// aff[«pf:<ممثلة>» / «st:<استوديو>» / «dP|…» لفترة اليوم] = ميل −2..2، day = آخر يوم طُبّق فيه التلاشي.
public struct ReelSignals: Sendable, Equatable {
    public var clips: [String: [String: Double]]; public var aff: [String: Double]; public var day: Int
    public init(clips: [String: [String: Double]] = [:], aff: [String: Double] = [:], day: Int = 0) { self.clips = clips; self.aff = aff; self.day = day }
    public init(json: JSONValue?) {
        clips = (json?["c"]?.object ?? [:]).mapValues { ($0.object ?? [:]).compactMapValues { $0.number } }
        aff = (json?["a"]?.object ?? [:]).compactMapValues { $0.number }
        day = json?["d"]?.int ?? 0
    }
    public var json: JSONValue {
        var o: JSONObject = ["c": .object(clips.mapValues { .object($0.mapValues { .double($0) }) }), "a": .object(aff.mapValues { .double($0) })]
        if day > 0 { o["d"] = .int(Int64(day)) }
        return .object(o)
    }
}

func nowSec() -> Double { Date().timeIntervalSince1970.rounded() }
public func reelDay(_ d: Date = Date()) -> Int { Int(d.timeIntervalSince1970 / 86400) }

/// تلاشي الاهتمام مع الوقت: كل يوم ×0.985، عدا «أقل منها» الصريح (−2) يبقى.
public func decayReels(_ s: ReelSignals, today: Int) -> ReelSignals {
    if s.day == 0 { return ReelSignals(clips: s.clips, aff: s.aff, day: today) }
    let days = today - s.day; if days <= 0 { return s }
    let f = pow(0.985, Double(days))
    return ReelSignals(clips: s.clips, aff: s.aff.mapValues { $0 <= -1.99 ? $0 : $0 * f }, day: today)
}

func affKeys(_ g: WorkGroup) -> [String] { g.who.map { "pf:\($0.id)" } + (g.s.trimmingCharacters(in: .whitespaces).isEmpty ? [] : ["st:\(norm(g.s))"]) }
func clampAff(_ x: Double) -> Double { min(2, max(-2, x)) }

/// فترة اليوم: 0 صباحًا (5–11)، 1 عصرًا (12–17)، 2 مساءً (18–22)، 3 ليلًا.
public func dayPart(_ hour: Int) -> Int { hour >= 5 && hour < 12 ? 0 : hour >= 12 && hour < 18 ? 1 : hour >= 18 && hour < 23 ? 2 : 3 }
public let dayPartName = ["صباحًا", "عصرًا", "مساءً", "ليلًا"]

/// قوة إشارة المشاهدة: الإعادة أقوى إشارة، والثواني تمنع اعتبار مشاهدة طويلة من فيديو طويل «تخطيًا».
public func viewSignal(frac: Double, secs: Double) -> Double {
    let byFrac = frac >= 1.8 ? 1.0 : frac >= 1.0 ? 0.6 : frac >= 0.9 ? 0.5 : frac >= 0.5 ? 0.2 : 0
    let bySecs = secs >= 180 ? 0.6 : secs >= 60 ? 0.4 : secs >= 20 ? 0.15 : 0
    let skip = frac < 0.15 && (secs < 0 || secs < 5)
    return skip ? -0.35 : max(byFrac, bySecs)
}

public func recordView(_ s: ReelSignals, _ g: WorkGroup, frac: Double, like: Bool = false, secs: Double = -1, hour: Int? = nil) -> ReelSignals {
    var r = s; var m = r.clips[g.key] ?? [:]
    m["n", default: 0] += 1; m["w"] = max(m["w"] ?? 0, frac); if like { m["l"] = 1 }
    if secs > 0 { m["t", default: 0] += secs.rounded() }
    if frac > 0 || like || secs > 0 { m["v"] = nowSec() }
    r.clips[g.key] = m
    let sig = viewSignal(frac: frac, secs: secs) + (like ? 0.9 : 0)
    let part = dayPart(hour ?? gregorian.component(.hour, from: Date()))
    for k in affKeys(g) {
        r.aff[k] = clampAff((r.aff[k] ?? 0) * 0.97 + sig)
        r.aff["d\(part)|\(k)"] = clampAff((r.aff["d\(part)|\(k)"] ?? 0) * 0.97 + sig)
    }
    return r
}

public func dislikeReel(_ s: ReelSignals, performerId: String? = nil, studio: String? = nil, hideKey: String? = nil) -> ReelSignals {
    var r = s
    if let p = performerId { r.aff["pf:\(p)"] = -2 }
    if let st = studio { r.aff["st:\(norm(st))"] = -2 }
    if let h = hideKey { r.clips[h, default: [:]]["h"] = 1 }
    return r
}

/// إشارات إضافية: زيارة ملفها، فتح الكامل، إضافتها للمفضلة، «غير مهتم».
public let reelActionWeight: [String: Double] = ["profile": 0.4, "full": 0.7, "follow": 0.9, "nope": -0.8]
public func recordAction(_ s: ReelSignals, _ g: WorkGroup, _ action: String) -> ReelSignals {
    var r = s; let w = reelActionWeight[action] ?? 0
    if action == "nope" { r.clips[g.key, default: [:]]["h"] = 1 }
    for k in affKeys(g) { r.aff[k] = clampAff((r.aff[k] ?? 0) + w) }
    return r
}
public func toggleSave(_ s: ReelSignals, _ g: WorkGroup) -> ReelSignals {
    var r = s; var m = r.clips[g.key] ?? [:]
    let on = m["s"] != 1
    if on { m["s"] = 1; m["st"] = nowSec(); for k in affKeys(g) { r.aff[k] = clampAff((r.aff[k] ?? 0) + 0.6) } } else { m["s"] = nil }
    r.clips[g.key] = m
    return r
}
public func reelHistory(_ s: ReelSignals) -> [String] { s.clips.filter { ($0.value["v"] ?? 0) > 0 }.sorted { ($0.value["v"] ?? 0) > ($1.value["v"] ?? 0) }.map(\.key) }
public func reelSaved(_ s: ReelSignals) -> [String] { s.clips.filter { $0.value["s"] == 1 }.sorted { ($0.value["st"] ?? 0) > ($1.value["st"] ?? 0) }.map(\.key) }
public func reelLiked(_ s: ReelSignals) -> [String] { s.clips.filter { $0.value["l"] == 1 }.map(\.key) }

/// تركيز الخلاصة: pf ممثلة، st استوديو، tg وسم.
public func reelFocusMatch(_ g: WorkGroup, kind: String, value v: String) -> Bool {
    switch kind {
    case "pf": return g.who.contains { $0.id == v }
    case "st": return norm(g.s) == norm(v)
    case "tg": return g.tg.contains { norm($0) == norm(v) }
    default: return true
    }
}

/// ترتيب المقاطع: ذوقك في الأعمال + ميلك المتعلَّم + المفضلة + الحداثة − ما رأيته كثيرًا + ميلك في فترة اليوم،
/// ثم ~20٪ استكشاف، ولا تتكرر ممثلة خلال 3 مقاطع ولا استوديو مرتين متتاليتين (ما أمكن).
public func rankReels(_ all: [WorkGroup], _ t: WorkTaste, _ sig: ReelSignals, favsOnly: Bool = true, seed: UInt64 = 0, n: Int = 80,
                      playable: ((String) -> Bool)? = nil, isCached: ((String) -> Bool)? = nil, hour: Int? = nil) -> [Reel] {
    let part = dayPart(hour ?? gregorian.component(.hour, from: Date()))
    var pool: [(WorkGroup, Double, String)] = []
    for g in all {
        if g.tr.isEmpty || g.who.isEmpty { continue }
        if let p = playable, !p(g.tr) { continue }
        if favsOnly && !g.who.contains(where: { $0.fav || $0.rating >= 4 }) { continue }
        let c = sig.clips[g.key]
        if c?["h"] == 1 { continue }
        var score = 0.0
        let st = t.keys["st:\(norm(g.s))"]
        if let st { score += st.score }
        for p in g.who { if let k = t.keys["pf:\(p.id)"] { score += k.score * 1.2 } }
        for x in g.tg { if let k = t.keys["tg:\(norm(x))"] { score += k.score * 0.3 } }
        if g.who.contains(where: \.fav) { score += 0.35 }
        var aff = 0.0, affWhy: String? = nil
        for k in affKeys(g) {
            let v = sig.aff[k] ?? 0; aff += v
            if v > 0.6 && affWhy == nil {
                affWhy = k.hasPrefix("pf:") ? "لأنك تكمل مقاطع \(g.who.first { "pf:\($0.id)" == k }?.name ?? g.who[0].name)" : "لأنك تحب مقاطع \(g.s)"
            }
        }
        score += aff * 0.6
        var partAff = 0.0; for k in affKeys(g) { partAff += sig.aff["d\(part)|\(k)"] ?? 0 }
        score += partAff * 0.35
        if affWhy == nil && partAff > 1 { affWhy = "لأنك تشاهد مثله عادةً \(dayPartName[part])" }
        if let yr = Int(g.y), yr > 0 { score += Double(max(0, yr - 2015)) * 0.02 }
        score -= (c?["n"] ?? 0) * 0.35
        if c?["l"] == 1 { score += 0.2 }
        if let ic = isCached, ic(g.tr) { score += 0.25 }
        let why = affWhy ?? (st.map { $0.score > 0.2 } == true ? "من \(g.s) الذي تحبه" : g.who.first(where: \.fav).map { "من مفضلاتك: \($0.name)" } ?? "من مكتبتك")
        pool.append((g, score, why))
    }
    if pool.isEmpty { return [] }
    pool.sort { $0.1 > $1.1 }
    var rng = SeededRandom(seed: seed)
    var explorePool = pool.filter { x in x.0.who.allSatisfy { abs(sig.aff["pf:\($0.id)"] ?? 0) < 0.3 } }
    explorePool.shuffle(using: &rng)
    var used = Set<String>(), out: [Reel] = [], recent: [String] = [], recentSt: [String] = []
    func fitsP(_ x: (WorkGroup, Double, String)) -> Bool { !used.contains(x.0.key) && !x.0.who.contains { recent.contains($0.id) } }
    func fits(_ x: (WorkGroup, Double, String)) -> Bool { fitsP(x) && (x.0.s.trimmingCharacters(in: .whitespaces).isEmpty || !recentSt.contains(norm(x.0.s))) }
    var i = 0, e = 0
    while out.count < n && (i < pool.count || e < explorePool.count) {
        let exploreTurn = rng.unit() < 0.2 && e < explorePool.count
        var pick: (WorkGroup, Double, String)? = nil
        if exploreTurn { while e < explorePool.count && pick == nil { let x = explorePool[e]; e += 1; if fits(x) { pick = x } } }
        if pick == nil { for k in i..<pool.count where fits(pool[k]) { pick = pool[k]; if k == i { i += 1 }; break } }
        if pick == nil { for k in i..<pool.count where fitsP(pool[k]) { pick = pool[k]; if k == i { i += 1 }; break } }
        if pick == nil {
            while i < pool.count && used.contains(pool[i].0.key) { i += 1 }
            if i >= pool.count { break }
            pick = pool[i]; i += 1
        }
        guard let p = pick else { break }
        used.insert(p.0.key)
        out.append(Reel(g: p.0, url: p.0.tr, why: exploreTurn ? "استكشاف: شيء مختلف قليلًا" : p.2, explore: exploreTurn))
        recent.append(contentsOf: p.0.who.map(\.id)); while recent.count > 3 { recent.removeFirst() }
        if !p.0.s.trimmingCharacters(in: .whitespaces).isEmpty { recentSt.append(norm(p.0.s)); if recentSt.count > 1 { recentSt.removeFirst() } }
    }
    return out
}

// MARK: الخوادم والجودة

public func hostOf(_ url: String) -> String { URL(string: url)?.host?.lowercased() ?? "" }
/// حالة خادم: {ok, dl, t, why}. المحجوب يُعاد فحصه بعد 6 ساعات، والعامل بعد 14 يومًا.
public func hostStale(_ h: [String: JSONValue]?, now: Double) -> Bool {
    guard let h else { return true }
    return now - (h["t"]?.number ?? 0) > (h["ok"]?.bool == true ? 14 * 86_400_000 : 6 * 3_600_000)
}
public func hostUsable(_ hosts: [String: JSONValue], _ url: String) -> Bool { hosts[hostOf(url)]?["ok"]?.bool != false }
public func looksBlocked(_ err: String) -> Bool { matches(err, #"TLS|-1200|-1005|reset|Handshake|connection was lost|closed"#, options: .caseInsensitive) }
/// معاينة لا إعلان: بلا صوت أو أقل من 480p.
public func isPreviewClip(_ q: [String: Double]?) -> Bool { guard let q else { return false }; return q["a"] == 0 || (q["h"] ?? 9999) < 480 }
public func isPreviewHost(_ quality: [String: [String: Double]], host: String) -> Bool {
    var n = 0, bad = 0
    for (u, q) in quality where hostOf(u) == host { n += 1; if isPreviewClip(q) { bad += 1 } }
    return n >= 3 && Double(bad) / Double(n) >= 0.7
}
public func qualityOk(_ quality: [String: [String: Double]], _ url: String, hqOnly: Bool) -> Bool {
    if !hqOnly { return true }
    if isPreviewClip(quality[url]) { return false }
    return !isPreviewHost(quality, host: hostOf(url))
}
/// نسخة أعلى جودة محتملة من الرابط (1080p) — أو nil.
public func higherQuality(_ url: String) -> String? {
    guard let r = url.range(of: #"(?<![0-9])(240|360|480|540|576|720)p(?![0-9])"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
    return url.replacingCharacters(in: r, with: "1080p")
}
