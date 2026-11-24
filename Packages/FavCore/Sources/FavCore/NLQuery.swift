import Foundation

/// البحث باللغة الطبيعية: «شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق» ⇒ فلاتر. على جهازك فقط.
/// محلّل قواعد عربي/إنجليزي؛ ونموذج Apple على الجهاز (إن توفّر) يملأ نفس البنية من JSON — قيمه تُتحقق من القوائم المسموحة.
public struct NLQuery: Equatable, Sendable {
    public var hair: Set<String> = [], eth: Set<String> = [], eyes: Set<String> = [], countries: Set<String> = []
    public var minAge: Int?, maxAge: Int?
    public var minRating: Double?, minHeight: Double?, maxHeight: Double?
    public var fav: Bool?, tattoos: Bool?, unseen: Bool?
    public var breast: String?, sort: String?
    public var text = ""
    public init() {}

    public var isEmpty: Bool {
        hair.isEmpty && eth.isEmpty && eyes.isEmpty && countries.isEmpty && minAge == nil && maxAge == nil && minRating == nil && minHeight == nil && maxHeight == nil
            && fav == nil && tattoos == nil && unseen == nil && breast == nil && sort == nil
    }

    public static let hairAr = ["BLONDE": "شقراء", "BRUNETTE": "شعر بني", "BLACK": "شعر أسود", "RED": "صهباء", "AUBURN": "كستنائية", "GREY": "شعر رمادي"]
    public static let ethAr = ["CAUCASIAN": "بيضاء", "BLACK": "سمراء البشرة", "ASIAN": "آسيوية", "INDIAN": "هندية", "LATIN": "لاتينية", "MIDDLE_EASTERN": "شرق أوسطية", "MIXED": "مختلطة"]
    public static let eyesAr = ["BLUE": "زرقاء", "BROWN": "بنية", "GREEN": "خضراء", "HAZEL": "عسلية", "GREY": "رمادية"]
    public static let countryAr = ["BR": "البرازيل", "US": "أمريكا", "RU": "روسيا", "UA": "أوكرانيا", "CZ": "التشيك", "HU": "المجر", "FR": "فرنسا", "DE": "ألمانيا", "ES": "إسبانيا", "IT": "إيطاليا",
        "GB": "بريطانيا", "CA": "كندا", "CO": "كولومبيا", "JP": "اليابان", "RO": "رومانيا", "LV": "لاتفيا", "PL": "بولندا", "AU": "أستراليا", "VE": "فنزويلا", "AR": "الأرجنتين",
        "MX": "المكسيك", "SE": "السويد", "NL": "هولندا", "SK": "سلوفاكيا", "BY": "بيلاروسيا", "TH": "تايلاند", "PH": "الفلبين", "CU": "كوبا", "PT": "البرتغال", "GR": "اليونان"]

    private func n(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }

    /// ما فهمه البحث، بالعربية (رقائق قابلة للإزالة).
    public var labels: [String] {
        var l: [String] = []
        l += hair.sorted().map { Self.hairAr[$0] ?? $0 }; l += eth.sorted().map { Self.ethAr[$0] ?? $0 }
        l += eyes.sorted().map { "عيون \(Self.eyesAr[$0] ?? $0)" }; l += countries.sorted().map { Self.countryAr[$0] ?? $0 }
        if let a = minAge, let b = maxAge { l.append("العمر \(a)–\(b)") } else if let a = minAge { l.append("العمر \(a)+") } else if let b = maxAge { l.append("العمر حتى \(b)") }
        if let r = minRating { l.append("التقييم \(n(r))+") }
        if let h = minHeight { l.append("الطول \(Int(h.rounded()))+ سم") }
        if let h = maxHeight { l.append("الطول حتى \(Int(h.rounded())) سم") }
        if fav == true { l.append("المفضلة") }
        if tattoos == true { l.append("بوشوم") }; if tattoos == false { l.append("بلا وشوم") }
        if unseen == true { l.append("لم تشاهد لها") }
        if breast == "NATURAL" { l.append("صدر طبيعي") }; if breast == "FAKE" { l.append("صدر مُعزَّز") }
        switch sort { case "rating": l.append("الأعلى تقييمًا"); case "young": l.append("الأصغر"); case "old": l.append("الأكبر"); case "new": l.append("الأحدث إضافة"); default: break }
        return l
    }

    public func without(_ label: String) -> NLQuery {
        var q = self
        q.hair = hair.filter { (Self.hairAr[$0] ?? $0) != label }; q.eth = eth.filter { (Self.ethAr[$0] ?? $0) != label }
        q.eyes = eyes.filter { "عيون \(Self.eyesAr[$0] ?? $0)" != label }; q.countries = countries.filter { (Self.countryAr[$0] ?? $0) != label }
        if label.hasPrefix("العمر") { q.minAge = nil; q.maxAge = nil }
        if label.hasPrefix("التقييم") { q.minRating = nil }
        if label.hasPrefix("الطول") { q.minHeight = nil; q.maxHeight = nil }
        if label == "المفضلة" { q.fav = nil }
        if label.contains("وشوم") { q.tattoos = nil }
        if label == "لم تشاهد لها" { q.unseen = nil }
        if label.hasPrefix("صدر") { q.breast = nil }
        if ["الأعلى تقييمًا", "الأصغر", "الأكبر", "الأحدث إضافة"].contains(label) { q.sort = nil }
        return q
    }

    /// من JSON النموذج: كل قيمة تُتحقق من القوائم المسموحة (لا يُقبل شيء مخترع)، والأعمار لا تقل عن 18.
    public static func fromJSON(_ j: JSONObject) -> NLQuery {
        var q = NLQuery()
        func pick(_ k: String, _ ok: [String: String]) -> Set<String> { Set((j[k]?.array ?? []).compactMap { $0.string?.uppercased() }.filter { ok[$0] != nil }) }
        q.hair = pick("hair", hairAr); q.eth = pick("eth", ethAr); q.eyes = pick("eyes", eyesAr); q.countries = pick("countries", countryAr)
        func age(_ k: String) -> Int? { j[k]?.number.map { min(99, max(18, Int($0))) } }
        q.minAge = age("minAge"); q.maxAge = age("maxAge")
        q.minRating = j["minRating"]?.number.map { min(5, max(0, $0)) }
        q.minHeight = j["minHeight"]?.number.map { min(210, max(120, $0)) }; q.maxHeight = j["maxHeight"]?.number.map { min(210, max(120, $0)) }
        q.fav = j["fav"]?.bool; q.tattoos = j["tattoos"]?.bool; q.unseen = j["unseen"]?.bool
        let br = (j["breast"]?.string ?? "").uppercased(); q.breast = ["NATURAL", "FAKE"].contains(br) ? br : nil
        let so = j["sort"]?.string ?? ""; q.sort = ["rating", "young", "old", "new"].contains(so) ? so : nil
        return q
    }
}

/// تطبيع عربي للمطابقة: بلا تشكيل، أ/إ/آ ⇒ ا، ة ⇒ ه، ى ⇒ ي، أرقام عربية ⇒ لاتينية.
public func arNorm(_ s: String) -> String {
    var x = s.lowercased().replacingOccurrences(of: "[\u{064B}-\u{0652}\u{0640}]", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[أإآ]", with: "ا", options: .regularExpression).replacingOccurrences(of: "ة", with: "ه").replacingOccurrences(of: "ى", with: "ي")
    for (i, d) in "٠١٢٣٤٥٦٧٨٩".enumerated() { x = x.replacingOccurrences(of: String(d), with: String(i)) }
    return x.replacingOccurrences(of: "٫", with: ".")
}

let countryStems: [(String, String)] = [("برازيل", "BR"), ("brazil", "BR"), ("امريك", "US"), ("american", "US"), ("usa", "US"), ("روس", "RU"), ("russia", "RU"), ("اوكران", "UA"), ("ukrain", "UA"),
    ("تشيك", "CZ"), ("czech", "CZ"), ("مجر", "HU"), ("هنغار", "HU"), ("hungar", "HU"), ("فرنس", "FR"), ("french", "FR"), ("france", "FR"), ("الماني", "DE"), ("المانيا", "DE"), ("german", "DE"),
    ("اسبان", "ES"), ("spani", "ES"), ("spain", "ES"), ("ايطال", "IT"), ("ital", "IT"), ("بريطان", "GB"), ("انجليز", "GB"), ("british", "GB"), ("english", "GB"), ("كندي", "CA"), ("كندا", "CA"),
    ("canad", "CA"), ("كولومب", "CO"), ("colombia", "CO"), ("يابان", "JP"), ("japan", "JP"), ("رومان", "RO"), ("romania", "RO"), ("لاتفي", "LV"), ("latvia", "LV"), ("بولند", "PL"),
    ("polish", "PL"), ("poland", "PL"), ("استرال", "AU"), ("australia", "AU"), ("فنزويل", "VE"), ("venezuela", "VE"), ("ارجنتين", "AR"), ("argentin", "AR"), ("مكسيك", "MX"), ("mexic", "MX"),
    ("سويد", "SE"), ("swed", "SE"), ("هولند", "NL"), ("dutch", "NL"), ("netherland", "NL"), ("سلوفاك", "SK"), ("slovak", "SK"), ("بيلاروس", "BY"), ("belarus", "BY"), ("تايلند", "TH"),
    ("تايلاند", "TH"), ("thai", "TH"), ("فلبين", "PH"), ("filip", "PH"), ("philipp", "PH"), ("كوب", "CU"), ("cuba", "CU"), ("برتغال", "PT"), ("portug", "PT"), ("يونان", "GR"), ("greek", "GR"), ("greece", "GR")]

private final class Scanner_ {
    var s: String
    init(_ s: String) { self.s = s }
    func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    /// أول تطابق ومجموعاته (أو nil).
    func first(_ p: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re(p).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
    func removeFirst(_ match: String) { if let r = s.range(of: match) { s.replaceSubrange(r, with: " ") } }
    /// يحذف كل التطابقات ويعيد true إن وُجد شيء.
    func take(_ p: String) -> Bool {
        let ns = s as NSString
        guard re(p).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil else { return false }
        s = re(p).stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return true
    }
}

public func parseQuery(_ input: String) -> NLQuery {
    let sc = Scanner_(" \(arNorm(input)) ")
    var q = NLQuery()
    // التقييم أولًا (حتى لا تُقرأ أرقامه أعمارًا)
    if let m = sc.first(#"(?:تقييم\S*|نجوم|نجمات|نجمه|rating|rated|stars?)\D{0,14}?(\d(?:\.\d)?)|(\d(?:\.\d)?)\s*(?:نجوم|نجمات|نجمه|stars?|\+\s*نجوم)"#) {
        q.minRating = min(5, max(0, Double(m[1] ?? m[2] ?? "0") ?? 0)); sc.removeFirst(m[0]!)
        _ = sc.take(#"فما فوق|فاكثر|او اكثر|and up|or more"#)
    }
    if let m = sc.first(#"طول\S*\s*(?:فوق|اكثر من|over|>)\s*(\d{3})|(?:taller than|over)\s*(\d{3})\s*cm"#) { q.minHeight = Double(m[1] ?? m[2] ?? ""); sc.removeFirst(m[0]!) }
    if let m = sc.first(#"طول\S*\s*(?:تحت|اقل من|under|<)\s*(\d{3})"#) { q.maxHeight = Double(m[1] ?? ""); sc.removeFirst(m[0]!) }
    if q.minHeight == nil && sc.take(#"\s(?:طويل\S*|tall)\s"#) { q.minHeight = 170 }
    if q.maxHeight == nil && sc.take(#"\s(?:قصير\S*|petite|short)\s"#) { q.maxHeight = 160 }
    if let m = sc.first(#"(?:بين|من|between|aged?)\s*(\d{2})\s*(?:و|الي|الى|to|and|-)\s*(\d{2})|(\d{2})\s*[-–]\s*(\d{2})"#) {
        let a = Int(m[1] ?? m[3] ?? "") ?? 0, b = Int(m[2] ?? m[4] ?? "") ?? 0
        if a >= 18 && b >= 18 && a <= 99 && b <= 99 { q.minAge = min(a, b); q.maxAge = max(a, b); sc.removeFirst(m[0]!) }
    }
    if let m = sc.first(#"(?:اقل من|تحت|اصغر من|دون|under|below|younger than)\s*(\d{2})"#) { q.maxAge = Int(m[1] ?? ""); sc.removeFirst(m[0]!) }
    if let m = sc.first(#"(?:اكبر من|فوق|اكثر من|over|above|older than)\s*(\d{2})"#) { q.minAge = Int(m[1] ?? ""); sc.removeFirst(m[0]!) }
    if let m = sc.first(#"(?:عمرها|سنها|عمر|age)\s*(\d{2})"#), let a = Int(m[1] ?? "") { if q.minAge == nil { q.minAge = a }; if q.maxAge == nil { q.maxAge = a }; sc.removeFirst(m[0]!) }
    if q.minAge == nil && q.maxAge == nil && sc.take(#"\s(?:صغير\S*|شاب\S*|young|teen)\s"#) { q.maxAge = 25 }
    if q.minAge == nil && sc.take(#"\s(?:ناضج\S*|milf|mature)\s"#) { q.minAge = 35 }
    if let a = q.minAge { q.minAge = min(99, max(18, a)) }
    if let b = q.maxAge { q.maxAge = min(99, max(18, b)) }
    if sc.take(#"عيون\S*\s*زرق\S*|زرقاء العيون|blue eyes|blue-eyed"#) { q.eyes.insert("BLUE") }
    if sc.take(#"عيون\S*\s*خضر\S*|خضراء العيون|green eyes"#) { q.eyes.insert("GREEN") }
    if sc.take(#"عيون\S*\s*عسلي\S*|hazel"#) { q.eyes.insert("HAZEL") }
    if sc.take(#"عيون\S*\s*بني\S*|brown eyes"#) { q.eyes.insert("BROWN") }
    if sc.take(#"شعر\S*\s*بني\S*|بنيه الشعر|brunette|brown hair"#) { q.hair.insert("BRUNETTE") }
    if sc.take(#"شعر\S*\s*اسود|سوداء الشعر|black hair"#) { q.hair.insert("BLACK") }
    if sc.take(#"صهباء|صهب\S*|شعر\S*\s*احمر|حمراء الشعر|redhead|ginger|red hair"#) { q.hair.insert("RED") }
    if sc.take(#"\s(?:ال)?شقر\S*|blonde?s?\s"#) { q.hair.insert("BLONDE") }
    if sc.take(#"\s(?:ال)?سمر\S*|سوداء البشره|ebony|black women|\sblack\s"#) { q.eth.insert("BLACK") }
    if sc.take(#"لاتين\S*|latina?s?"#) { q.eth.insert("LATIN") }
    if sc.take(#"اسيوي\S*|asians?"#) { q.eth.insert("ASIAN") }
    if sc.take(#"هندي\S*|indian"#) { q.eth.insert("INDIAN") }
    if sc.take(#"شرق اوسطي\S*|عربي\S*|arab\S*|middle eastern"#) { q.eth.insert("MIDDLE_EASTERN") }
    if sc.take(#"\s(?:بيضاء|بيض|caucasian|white)\s"#) { q.eth.insert("CAUCASIAN") }
    for (stem, code) in countryStems { if sc.take("\\s(?:ال)?\(NSRegularExpression.escapedPattern(for: stem))\\S*") { q.countries.insert(code) } }
    if sc.take(#"(?:بدون|بلا|من غير|ما عندها|no|without)\s*(?:اي\s*)?(?:وشو?م\S*|تاتو\S*|tattoos?)"#) { q.tattoos = false }
    else if sc.take(#"وشو?م\S*|موشوم\S*|تاتو\S*|tattoo\S*|inked"#) { q.tattoos = true }
    if sc.take(#"صدر\S*\s*طبيعي\S*|طبيعي\S*|natural"#) { q.breast = "NATURAL" }
    if sc.take(#"صدر\S*\s*(?:صناعي|مكبر|معزز|سيليكون)\S*|سيليكون|fake|enhanced|implants?"#) { q.breast = "FAKE" }
    if sc.take(#"(?:من\s*)?(?:ال)?مفضل\S*|favou?rites?|favs?"#) { q.fav = true }
    if sc.take(#"(?:ما|لم)\s*(?:شاهدت|اشاهد|شفت)\s*(?:لها)?\S*|unwatched|not watched|haven.?t seen"#) { q.unseen = true }
    if sc.take(#"الاعلي تقييما|الاعلى تقييما|اعلى تقييم|top rated|best rated"#) { q.sort = "rating" }
    else if sc.take(#"الاصغر\S*|youngest"#) { q.sort = "young" }
    else if sc.take(#"الاكبر سنا|الاكبر\S*|oldest"#) { q.sort = "old" }
    else if sc.take(#"الاحدث اضافه|المضافه حديثا|احدث\S*|newest|recent"#) { q.sort = "new" }
    q.text = sc.s.replacingOccurrences(of: #"\s(?:ابي|ابغى|ابغي|ابحث|عن|اعرض|ورني|وريني|ممثل\S*|التي|اللي|الي|و|من|في|مع|ذات|لها|عندها|عمرها|سن\S*|عمر\S*|سنه|سنوات|سنة|و?بين|او|show|me|find|with|and|the|a|years?|old|girls?|women|performers?)(?=\s)"#,
                                       with: " ", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    return q
}

/// هل الممثلة تطابق؟ [f]: خصائصها الموثّقة. الخاصية المطلوبة وغير المعروفة ⇒ لا تطابق (لا تخمين). القاصر لا تظهر أبدًا.
public func nlMatch(_ q: NLQuery, _ p: Performer, _ f: Features) -> Bool {
    if p.isMinor { return false }
    func inSet(_ want: Set<String>, _ key: String) -> Bool { want.isEmpty || want.contains(f[key]?.str ?? "") }
    if !inSet(q.hair, "hair_color") || !inSet(q.eth, "ethnicity") || !inSet(q.eyes, "eye_color") { return false }
    if !q.countries.isEmpty && !q.countries.contains((p.country.isEmpty ? (f["country"]?.str ?? "") : p.country).uppercased()) { return false }
    if q.minAge != nil || q.maxAge != nil {
        guard let a = p.age ?? f["age"]?.num.map({ Int($0) }) else { return false }
        if let mn = q.minAge, a < mn { return false }
        if let mx = q.maxAge, a > mx { return false }
    }
    if let r = q.minRating, p.rating < r { return false }
    let h = f["height"]?.num ?? p.height
    if (q.minHeight != nil || q.maxHeight != nil) && h == nil { return false }
    if let mn = q.minHeight, let h, h < mn { return false }
    if let mx = q.maxHeight, let h, h > mx { return false }
    if q.fav == true && !p.fav { return false }
    if let t = q.tattoos, f["tattoos"]?.str != (t ? "yes" : "no") { return false }
    if let b = q.breast, f["breast_type"]?.str != b { return false }
    if q.unseen == true && p.watchedCount > 0 { return false }
    return true
}

public func nlSort(_ q: NLQuery, _ l: [Performer]) -> [Performer] {
    func age(_ p: Performer) -> Int { p.age ?? 999 }
    switch q.sort {
    case "rating": return l.sorted { $0.rating > $1.rating }
    case "young": return l.sorted { age($0) < age($1) }
    case "old": return l.sorted { (age($0) == 999 ? -1 : age($0)) > (age($1) == 999 ? -1 : age($1)) }
    case "new": return l.sorted { $0.added > $1.added }
    default: return l.sorted { $0.fav != $1.fav ? $0.fav : $0.rating > $1.rating }
    }
}

/// تعليمات نموذج Apple على الجهاز: JSON فقط بالقيم المسموحة.
public let nlModelInstructions = """
Convert the user's search (Arabic or English) for performers in their private library into JSON only, no prose.
Keys (omit unknown): hair [BLONDE,BRUNETTE,BLACK,RED,AUBURN,GREY], eth [CAUCASIAN,BLACK,ASIAN,INDIAN,LATIN,MIDDLE_EASTERN,MIXED], eyes [BLUE,BROWN,GREEN,HAZEL,GREY],
countries [ISO-3166 alpha-2 codes], minAge, maxAge (integers, 18 or more), minRating (0-5), minHeight, maxHeight (cm), fav (bool), tattoos (bool), unseen (bool),
breast (NATURAL|FAKE), sort (rating|young|old|new).
Example: "شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق" => {"hair":["BLONDE"],"countries":["BR"],"minAge":20,"maxAge":25,"minRating":4}
"""
