import Foundation

// الأدوات: المواجهة (Elo)، المستويات، الاكتمال، التقييم بالمعايير، الحسابات، الإنجازات، أعياد الميلاد، في مثل هذا اليوم، «يومياتي».

/// Elo بـ K=32. يعيد التقييمين الجديدين.
public func eloUpdate(winner: Double, loser: Double, k: Double = 32) -> (Double, Double) {
    let ew = 1 / (1 + pow(10, (loser - winner) / 400))
    return (winner + k * (1 - ew), loser - k * (1 - ew))
}
public func duelsOf(_ p: Performer) -> Int { p.raw["duels"]?.int ?? 0 }

/// اختيار زوج: الأقل مواجهات من 5 عشوائيات، ثم الأقرب تقييمًا من 9 أخريات، مع تجنب الزوج السابق.
public func pickPair<G: RandomNumberGenerator>(_ pool: [Performer], using rng: inout G, last: Set<String> = []) -> (Performer, Performer)? {
    if pool.count < 2 { return nil }
    let a = (0..<5).map { _ in pool.randomElement(using: &rng)! }.min { duelsOf($0) < duelsOf($1) }!
    let others = (0..<9).map { _ in pool.randomElement(using: &rng)! }.filter { $0.id != a.id && !(last.contains(a.id) && last.contains($0.id)) }
        .sorted { abs($0.elo - a.elo) < abs($1.elo - a.elo) }
    if let b = others.first { return (a, b) }
    return pool.first { $0.id != a.id }.map { (a, $0) }
}

public func tierFromRating(_ r: Double) -> String { r >= 4.75 ? "S" : r >= 4 ? "A" : r >= 3 ? "B" : r >= 2 ? "C" : r > 0 ? "D" : "" }

/// اكتمال السجل (7 فحوص).
public func completeness(_ p: Performer) -> [(String, Bool)] {
    [("صورة", !p.photos.isEmpty), ("تاريخ ميلاد كامل", matches(p.birth, #"^\d{4}-\d{2}-\d{2}$"#)), ("البلد", !p.country.isEmpty),
     ("رابط مصدر", !p.stashIds.isEmpty || !p.pdbIds.isEmpty), ("تقييم", p.rating > 0), ("أعمال", !p.works.isEmpty), ("وسوم", !p.tags.isEmpty)]
}

func round05(_ v: Double) -> Double { (v * 2).rounded() / 2 }
public func meanOf(_ m: [String: Double]) -> Double { m.isEmpty ? 0 : m.values.reduce(0, +) / Double(m.count) }

/// مع وجود الجسم التفصيلي يصبح criteria.body متوسطه، والتقييم العام = متوسط المعايير المعبأة مقرّبًا لـ 0.5.
public func applyRatings(criteria c: [String: Double], body b: [String: Double]) -> (criteria: [String: Double], rating: Double) {
    var cc = c.filter { $0.value > 0 }
    if !b.isEmpty { cc["body"] = round05(meanOf(b)) }
    return (cc, cc.isEmpty ? 0 : round05(meanOf(cc)))
}

/// منصات الحسابات (نفس مفاتيح التطبيق السابق).
public let platforms: [(key: String, label: String, base: String)] = [
    ("instagram", "Instagram", "https://instagram.com/"), ("x", "X", "https://x.com/"), ("tiktok", "TikTok", "https://tiktok.com/@"),
    ("onlyfans", "OnlyFans", "https://onlyfans.com/"), ("fansly", "Fansly", "https://fansly.com/"), ("snapchat", "Snapchat", "https://snapchat.com/add/"),
    ("telegram", "Telegram", "https://t.me/"), ("reddit", "Reddit", "https://reddit.com/user/"), ("youtube", "YouTube", "https://youtube.com/@"),
    ("twitch", "Twitch", "https://twitch.tv/"), ("linktree", "Linktree", "https://linktr.ee/"), ("website", "موقع", ""), ("other", "أخرى", ""),
]

/// رابط الحساب: رابط https كامل كما هو؛ وإلا اسم مستخدم آمن + أساس المنصة. لا شيء غير https.
public func accountURL(platform: String, value: String) -> URL? {
    let v = value.trimmingCharacters(in: .whitespaces)
    if v.hasPrefix("https://") { return URL(string: v) }
    if v.hasPrefix("http://") { return nil }
    let base = platforms.first { $0.key == platform }?.base ?? ""
    if base.isEmpty { return matches(v, #"^[\w.-]+\.[a-zA-Z]{2,}(/\S*)?$"#) ? URL(string: "https://\(v)") : nil }
    let u = v.replacingOccurrences(of: #"^[@/]+|/+$"#, with: "", options: .regularExpression)
    return matches(u, #"^[\w.\-]+$"#) ? URL(string: base + u) : nil
}

// MARK: الإنجازات (11 عائلة بمستويات — كالتطبيق السابق)

public struct Achievement: Sendable { public let title: String, icon: String; public let value: Int; public let levels: [Int]
    public var reached: Int { levels.filter { value >= $0 }.count }
    public var next: Int? { levels.first { value < $0 } }
}

public func achievements(_ lib: [Performer], _ works: [WorkGroup], lists: Int) -> [Achievement] {
    let watched = works.filter(\.seen)
    let st = streaks(watched.map(\.wd))
    let filled = lib.filter { p in [!p.photos.isEmpty, !p.birth.isEmpty, !p.country.isEmpty, p.rating > 0, !p.works.isEmpty, !p.tags.isEmpty, !p.notes.isEmpty, !p.aliases.isEmpty].filter { $0 }.count >= 6 }.count
    return [
        Achievement(title: "جامع", icon: "person.3.fill", value: lib.count, levels: [10, 50, 100, 250]),
        Achievement(title: "ناقد", icon: "star.fill", value: lib.filter { $0.rating > 0 }.count, levels: [10, 50, 150]),
        Achievement(title: "مشاهد", icon: "eye.fill", value: watched.count, levels: [25, 100, 500, 1000]),
        Achievement(title: "سلسلة أيام", icon: "flame.fill", value: st.best, levels: [3, 7, 30]),
        Achievement(title: "ناقد أعمال", icon: "film.fill", value: works.filter { $0.r > 0 }.count, levels: [10, 50, 200]),
        Achievement(title: "مواجهات", icon: "bolt.fill", value: lib.reduce(0) { $0 + duelsOf($1) } / 2, levels: [20, 100, 500]),
        Achievement(title: "مستويات", icon: "list.number", value: lib.filter { !$0.tier.isEmpty }.count, levels: [10, 50]),
        Achievement(title: "صور", icon: "photo.fill", value: lib.reduce(0) { $0 + $1.photos.count }, levels: [50, 250, 1000]),
        Achievement(title: "منظّم", icon: "folder.fill", value: lists, levels: [3, 10]),
        Achievement(title: "مكتمل", icon: "checkmark.seal.fill", value: filled, levels: [10, 50]),
        Achievement(title: "كاتب", icon: "pencil", value: works.filter { !$0.n.isEmpty }.count, levels: [5, 25]),
    ]
}

/// أعياد الميلاد القادمة خلال [days] يومًا (التاريخ الكامل فقط، والقاصر مستبعد).
public func upcomingBirthdays(_ lib: [Performer], days: Int = 45, now: Date = Date()) -> [(Performer, Int, Int)] {
    let t = ymd(now)
    let today = gregorian.date(from: DateComponents(year: t.0, month: t.1, day: t.2))!
    var out: [(Performer, Int, Int)] = []
    for p in lib where !p.isMinor && matches(p.birth, #"^\d{4}-\d{2}-\d{2}"#) {
        let y = Int(p.birth.prefix(4))!, m = Int(p.birth.dropFirst(5).prefix(2))!, d = Int(p.birth.dropFirst(8).prefix(2))!
        for yr in [t.0, t.0 + 1] {
            guard let next = gregorian.date(from: DateComponents(year: yr, month: m, day: min(d, daysIn(year: yr, month: m)))) else { continue }
            let diff = gregorian.dateComponents([.day], from: today, to: next).day ?? -1
            if diff >= 0 { if diff <= days { out.append((p, diff, yr - y)) }; break }
        }
    }
    return out.sorted { $0.1 < $1.1 }
}

/// في مثل هذا اليوم: أعمال شاهدتها/صدرت في هذا التاريخ من سنوات سابقة.
public func onThisDay(_ works: [WorkGroup], now: Date = Date()) -> (watched: [WorkGroup], released: [WorkGroup]) {
    let t = todayStr(now); let md = String(t.dropFirst(4))
    return (works.filter { $0.wd.count == 10 && $0.wd.hasSuffix(md) && $0.wd != t },
            works.filter { $0.d.count == 10 && $0.d.hasSuffix(md) && $0.d < t })
}

// MARK: «يومياتي»

public struct MonthReview: Sendable {
    public let year, month, watched, prevWatched, added, rated, activeDays: Int
    public let avgRating: Double
    public let topPerformers: [(Performer, Int)]
    public let topStudios, topTags: [(String, Int)]
    public let firstTime: [Performer]
    public let bestDay: String; public let bestDayCount: Int
    public var delta: Int { watched - prevWatched }
}

func ymKey(_ y: Int, _ m: Int) -> String { "\(y)-\(m < 10 ? "0" : "")\(m)" }

public func monthReview(_ works: [WorkGroup], _ lib: [Performer], year: Int, month: Int) -> MonthReview {
    let key = ymKey(year, month), pm = month == 1 ? ymKey(year - 1, 12) : ymKey(year, month - 1)
    let seen = works.filter { $0.seen && $0.wd.hasPrefix(key) }
    let prev = works.filter { $0.seen && $0.wd.hasPrefix(pm) }.count
    var byP: [String: (Performer, Int)] = [:], bySt: [String: Int] = [:], byTg: [String: Int] = [:], byDay: [String: Int] = [:]
    for g in seen {
        for p in g.who { byP[p.id] = (p, (byP[p.id]?.1 ?? 0) + 1) }
        if !g.s.isEmpty { bySt[g.s, default: 0] += 1 }
        for t in g.tg { byTg[t, default: 0] += 1 }
        byDay[g.wd, default: 0] += 1
    }
    let before = Set(works.filter { $0.seen && !$0.wd.isEmpty && $0.wd < key }.flatMap { $0.who.map(\.id) })
    let first = byP.values.map(\.0).filter { !before.contains($0.id) }
    let rated = seen.filter { $0.r > 0 }
    let best = byDay.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first
    func top(_ m: [String: Int], _ n: Int) -> [(String, Int)] { m.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) } }
    let added = lib.filter { p in let d = Date(timeIntervalSince1970: Double(p.added) / 1000); return gregorian.component(.year, from: d) == year && gregorian.component(.month, from: d) == month }.count
    return MonthReview(year: year, month: month, watched: seen.count, prevWatched: prev, added: added, rated: rated.count, activeDays: byDay.count,
                       avgRating: rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.r }) / Double(rated.count),
                       topPerformers: Array(byP.values.sorted { $0.1 > $1.1 }.prefix(5)), topStudios: top(bySt, 5), topTags: top(byTg, 6),
                       firstTime: first, bestDay: best?.key ?? "", bestDayCount: best?.value ?? 0)
}

/// تقويم المشاهدة: عدد ما شاهدته في كل يوم لآخر [days] يومًا.
public func watchHeatmap(_ works: [WorkGroup], days: Int = 182, now: Date = Date()) -> [String: Int] {
    let t = ymd(now)
    let start = gregorian.date(byAdding: .day, value: -(days - 1), to: gregorian.date(from: DateComponents(year: t.0, month: t.1, day: t.2))!)!
    let s0 = todayStr(start)
    var out: [String: Int] = [:]
    for g in works where g.seen && g.wd.count == 10 && g.wd >= s0 { out[g.wd, default: 0] += 1 }
    return out
}

/// أطول سلسلة أيام متتالية وسلسلتك الحالية.
public func streaks(_ days: [String], now: Date = Date()) -> (best: Int, current: Int) {
    let set = Set(days.filter { $0.count == 10 })
    let nums = set.compactMap { s -> Int? in
        guard let y = Int(s.prefix(4)), let m = Int(s.dropFirst(5).prefix(2)), let d = Int(s.dropFirst(8)) else { return nil }
        return gregorian.date(from: DateComponents(year: y, month: m, day: d)).map { Int($0.timeIntervalSince1970 / 86400) }
    }.sorted()
    if nums.isEmpty { return (0, 0) }
    var best = 1, run = 1
    for i in 1..<max(1, nums.count) where nums.count > 1 { run = nums[i] - nums[i - 1] == 1 ? run + 1 : 1; best = max(best, run) }
    let t = ymd(now)
    var d = Int(gregorian.date(from: DateComponents(year: t.0, month: t.1, day: t.2))!.timeIntervalSince1970 / 86400)
    let s = Set(nums)
    if !s.contains(d) { d -= 1 }   // اليوم لم ينتهِ بعد
    var cur = 0; while s.contains(d) { cur += 1; d -= 1 }
    return (best, cur)
}

/// مراحل: أعمالها المنشورة التي شاهدتها من مجموعها — للمفضلات اللاتي لهن [minTotal] أعمال فأكثر، الأقرب للاكتمال أولًا.
public func performerMilestones(_ works: [WorkGroup], _ lib: [Performer], minTotal: Int = 5, now: Date = Date()) -> [(p: Performer, seen: Int, total: Int)] {
    var byP: [String: (Int, Int)] = [:]
    for g in works where !g.isUpcoming(now: now) { for p in g.who { let x = byP[p.id] ?? (0, 0); byP[p.id] = (x.0 + (g.seen ? 1 : 0), x.1 + 1) } }
    return lib.compactMap { p in
        guard p.fav || p.rating >= 4, let x = byP[p.id], x.1 >= minTotal else { return nil }
        return (p, x.0, x.1)
    }.sorted { Double($0.seen) / Double($0.total) > Double($1.seen) / Double($1.total) }
}

/// المرحلة التالية لمجموع ما شاهدته (10، 25، 50، 100، 250، 500، 1000…).
public func nextMilestone(_ n: Int) -> (next: Int, prev: Int) {
    var prev = 0
    for s in [10, 25, 50, 100, 250, 500, 1000, 2500, 5000] { if n < s { return (s, prev) }; prev = s }
    return ((n / 5000 + 1) * 5000, prev)
}
