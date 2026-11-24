import Foundation

/// سجل ممثلة — خريطة JSON كما هي (لا يضيع أي حقل مجهول)، مع قراءات مريحة بأسماء التطبيق السابق.
public struct Performer: Identifiable, Equatable, Hashable, Sendable {
    public var raw: JSONObject
    public init(_ raw: JSONObject) { self.raw = raw }

    /// حقول خاصة بالجهاز لا تُستبدل عند الاستيراد أو المزامنة.
    public static let deviceLocal: Set<String> = ["views", "lastView", "nph"]
    /// معايير التقييم الثمانية وتفاصيل الجسم الثمانية (بنفس المفاتيح والأسماء).
    public static let criteria: [(String, String)] = [("beauty", "الجمال"), ("charisma", "الكاريزما"), ("perf", "الأداء"), ("seduce", "الإغراء"),
                                                     ("body", "الجسم"), ("screen", "الحضور على الشاشة"), ("bold", "الجرأة"), ("heat", "الإثارة")]
    public static let bodyDetails: [(String, String)] = [("face", "الوجه"), ("hair", "الشعر"), ("skin", "البشرة"), ("figure", "القوام العام"),
                                                        ("chest", "الصدر"), ("waist", "الخصر"), ("hips", "الأرداف"), ("legs", "الأرجل")]

    public var id: String { raw["id"]?.string ?? "" }
    public var name: String { raw["name"]?.text ?? "" }
    public var aliases: String { raw["aliases"]?.text ?? "" }
    public var country: String { raw["country"]?.text ?? "" }
    public var birth: String { raw["birth"]?.text ?? "" }
    public var notes: String { raw["notes"]?.text ?? "" }
    public var rating: Double { raw["rating"]?.number ?? 0 }
    public var fav: Bool { raw["fav"]?.bool == true }
    public var tags: [String] { strings("tags") }
    public var lists: [String] { strings("lists") }
    public var photos: [String] { strings("photos") }
    public var thumb: String { raw["thumb"]?.text ?? "" }
    public var cover: String { photos.first ?? thumb }
    public var works: [JSONObject] { (raw["works"]?.array ?? []).compactMap { $0.object } }
    public var added: Int64 { Int64(raw["added"]?.number ?? 0) }
    public var updated: Int64 { Int64(raw["updated"]?.number ?? 0) }
    public var views: Int { raw["views"]?.int ?? 0 }
    public var tier: String { raw["tier"]?.text ?? "" }
    public var elo: Double { raw["elo"]?.number ?? 1000 }
    public var height: Double? { raw["height"]?.number }
    public var stashId: String { raw["stashId"]?.text ?? "" }
    public var pdbId: String { raw["pdbId"]?.text ?? "" }
    /// كل معرّفات StashDB / ThePornDB (قد تكون للممثلة عدة سجلات بأسماء مختلفة).
    public var stashIds: [String] { uniq([stashId] + strings("stashIds")) }
    public var pdbIds: [String] { uniq([pdbId] + strings("pdbIds")) }
    public var criteriaValues: [String: Double] { (raw["criteria"]?.object ?? [:]).compactMapValues { $0.number } }
    public var bodyValues: [String: Double] { (raw["bodyD"]?.object ?? [:]).compactMapValues { $0.number } }
    public var accounts: [(platform: String, value: String)] {
        (raw["accounts"]?.array ?? []).compactMap { a in
            guard let o = a.object, let v = o["v"]?.string, !v.isEmpty else { return nil }
            return (o["p"]?.text ?? "other", v)
        }
    }
    public var isMinor: Bool { minorRec(raw) }
    public var age: Int? { sdAge(raw["birth"]).age }
    public var watchedCount: Int { works.filter { $0["w"]?.isOn == true }.count }

    /// نسخة معدّلة (تحدّث «updated» تلقائيًا ما لم يُطلب غير ذلك).
    public func with(_ changes: JSONObject, touch: Bool = true) -> Performer {
        var r = raw
        for (k, v) in changes { if v.isNull { r[k] = nil } else { r[k] = v } }
        if touch { r["updated"] = .int(Int64(Date().timeIntervalSince1970 * 1000)) }
        return Performer(r)
    }

    func strings(_ k: String) -> [String] { (raw[k]?.array ?? []).compactMap { $0.string } }
    private func uniq(_ a: [String]) -> [String] { var s = Set<String>(); return a.filter { !$0.isEmpty && s.insert($0).inserted } }
}
