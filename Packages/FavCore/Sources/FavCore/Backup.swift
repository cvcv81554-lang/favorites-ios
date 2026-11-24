import Foundation
import CryptoKit
import CommonCrypto
import Security

/// النسخة الاحتياطية — نفس صيغة التطبيق السابق (وتطبيق Flutter) تمامًا في الاتجاهين:
///   {"app":"vkte-favorites","v":5,"exportedAt":ms,"lists":[],"wlists":[],"prefs":{},"items":[...]}
///   والمشفّرة {app:'vkte-enc',v:1,salt(16),iv(12),data} = AES-GCM-256 بمفتاح PBKDF2-SHA256 (200000 دورة)، والوسم (16 بايت) في آخر data.
/// مفاتيح API والرمز السري لا تُصدَّر ولا تُستورد أبدًا.
public enum BackupError: Error, Equatable, LocalizedError {
    case notJSON, notBackup, tooMany, unknownEncryption, corrupt, wrongPassword, shortPassword
    public var errorDescription: String? {
        switch self {
        case .notJSON: return "الملف ليس JSON صالحًا"
        case .notBackup: return "ليس ملف نسخة احتياطية من المفضلة"
        case .tooMany: return "عدد السجلات أكبر من المسموح"
        case .unknownEncryption: return "ملف مشفّر بصيغة غير معروفة"
        case .corrupt: return "الملف تالف"
        case .wrongPassword: return "كلمة المرور غير صحيحة أو الملف تالف"
        case .shortPassword: return "كلمة المرور 8 أحرف على الأقل"
        }
    }
}

public struct BackupFile: Sendable {
    public var items: [JSONObject]
    public var lists: [JSONObject], wlists: [JSONObject]
    public var prefs: [String: String]
    public var minorsSkipped: Int, invalid: Int
}

public enum Backup {
    public static let secretPrefs: Set<String> = ["vkte_key", "vkte_stash", "vkte_pin", "vkte_pin2"]

    public static func isEncrypted(_ text: String) -> Bool { (try? JSONValue.parse(text))?["app"]?.string == "vkte-enc" }

    // MARK: التشفير
    static func deriveKey(_ password: String, salt: Data) -> SymmetricKey {
        var key = [UInt8](repeating: 0, count: 32)
        let pw = Array(password.utf8)
        _ = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &key, 32)
        }
        return SymmetricKey(data: key)
    }

    public static func decrypt(_ text: String, password: String) throws -> String {
        guard let j = try? JSONValue.parse(text), j["app"]?.string == "vkte-enc", j["v"]?.int == 1,
              let salt = Data(base64Encoded: j["salt"]?.text ?? ""), let iv = Data(base64Encoded: j["iv"]?.text ?? ""),
              let data = Data(base64Encoded: j["data"]?.text ?? "") else { throw BackupError.unknownEncryption }
        if data.count < 17 || iv.count != 12 { throw BackupError.corrupt }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: data.prefix(data.count - 16), tag: data.suffix(16))
            let plain = try AES.GCM.open(box, using: deriveKey(password, salt: salt))
            guard let s = String(data: plain, encoding: .utf8) else { throw BackupError.corrupt }
            return s
        } catch { throw BackupError.wrongPassword }
    }

    public static func encrypt(_ json: String, password: String) throws -> String {
        if password.count < 8 { throw BackupError.shortPassword }
        var salt = Data(count: 16), iv = Data(count: 12)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!) }
        let box = try AES.GCM.seal(Data(json.utf8), using: deriveKey(password, salt: salt), nonce: AES.GCM.Nonce(data: iv))
        let out: JSONValue = ["app": "vkte-enc", "v": 1, "salt": .string(salt.base64EncodedString()), "iv": .string(iv.base64EncodedString()),
                              "data": .string((box.ciphertext + box.tag).base64EncodedString())]
        return String(decoding: try out.encoded(), as: UTF8.self)
    }

    // MARK: القراءة والتنقية (بلا كتابة)
    /// يقرأ الملف وينقّيه: يرفض القاصر ويعدّه، ويعدّ السجلات غير الصالحة. الحقول المجهولة تبقى كما هي.
    public static func parse(_ text: String, now: Date = Date()) throws -> BackupFile {
        guard let j = try? JSONValue.parse(text) else { throw BackupError.notJSON }
        guard let raw = j["items"]?.array else { throw BackupError.notBackup }
        if raw.count > 50_000 { throw BackupError.tooMany }
        var items: [JSONObject] = [], minors = 0, invalid = 0
        for x in raw {
            guard var m = x.object, safeId(m["id"]), let name = m["name"]?.string,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { invalid += 1; continue }
            if minorRec(m, now: now) { minors += 1; continue }
            var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.count > 300 { n = String(n.prefix(300)) }
            m["name"] = .string(n)
            m["photos"] = .array(Array((m["photos"]?.array ?? []).filter { safeImg($0) }.prefix(30)))
            if let th = m["thumb"], !th.isNull, !safeImg(th) { m["thumb"] = nil }
            m["tags"] = .array(Array((m["tags"]?.array ?? []).filter { $0.string != nil }.prefix(100)))
            m["works"] = .array(safeWorks(m["works"]))
            items.append(m)
        }
        func idName(_ v: JSONValue?) -> [JSONObject] {
            (v?.array ?? []).compactMap { $0.object }.filter { safeId($0["id"]) && $0["name"]?.string != nil }.map { ["id": $0["id"]!, "name": $0["name"]!] }
        }
        var prefs: [String: String] = [:]
        for (k, v) in j["prefs"]?.object ?? [:] where k.hasPrefix("vkte_") { if let s = v.string { prefs[k] = s } }
        for k in secretPrefs { prefs[k] = nil }   // لا مفاتيح API ولا رمز سري حتى لو وُجدت في ملف قديم
        return BackupFile(items: items, lists: idName(j["lists"]), wlists: idName(j["wlists"]), prefs: prefs, minorsSkipped: minors, invalid: invalid)
    }

    // MARK: خطة الاستيراد (معاينة قبل الكتابة)
    public enum Action: String, Sendable { case add, update, fixPhotos, keep }
    public struct PlanItem: Sendable { public let record: JSONObject; public let action: Action }
    public struct Plan: Sendable {
        public let items: [PlanItem]
        public let file: BackupFile
        public var added: Int { items.filter { $0.action == .add }.count }
        public var updated: Int { items.filter { $0.action == .update }.count }
        public var photosFixed: Int { items.filter { $0.action == .fixPhotos }.count }
        public var kept: Int { items.filter { $0.action == .keep }.count }
        public var newLists: Int = 0, newWlists: Int = 0
    }

    /// قواعد الدمج (لا حذف أبدًا): جديد ⇒ يُضاف؛ موجود ⇒ يُستبدل فقط إن كان «updated» في الملف أحدث (مع إبقاء حقول الجهاز)،
    /// وإلا تُكمل صوره الناقصة فقط، وإلا يبقى كما هو.
    public static func plan(_ f: BackupFile, current: [String: Performer], lists: [JSONObject] = [], wlists: [JSONObject] = []) -> Plan {
        var out: [PlanItem] = []
        for m in f.items {
            let id = m["id"]!.string!
            let photos = m["photos"]?.array ?? []
            guard let cur = current[id] else { out.append(PlanItem(record: m, action: .add)); continue }
            let newer = Int64(m["updated"]?.number ?? 0) > cur.updated
            if newer {
                var r = m
                for k in Performer.deviceLocal { if let v = cur.raw[k] { r[k] = v } }
                // تحسين على السابق: لا تُفقد صور موجودة إن كان الملف يحمل صورًا أقل
                if photos.count < cur.photos.count { r["photos"] = cur.raw["photos"]; if let th = cur.raw["thumb"] { r["thumb"] = th } }
                out.append(PlanItem(record: r, action: .update))
            } else if cur.photos.count < photos.count {
                var r = cur.raw; r["photos"] = .array(photos)
                if (r["thumb"]?.text ?? "").isEmpty, let th = m["thumb"] { r["thumb"] = th }
                out.append(PlanItem(record: r, action: .fixPhotos))
            } else {
                out.append(PlanItem(record: cur.raw, action: .keep))
            }
        }
        var p = Plan(items: out, file: f)
        let haveL = Set(lists.compactMap { $0["id"]?.string }), haveW = Set(wlists.compactMap { $0["id"]?.string })
        p.newLists = f.lists.filter { !haveL.contains($0["id"]?.string ?? "") }.count
        p.newWlists = f.wlists.filter { !haveW.contains($0["id"]?.string ?? "") }.count
        return p
    }

    /// دمج القوائم بالمعرّف (الموجود يبقى، الجديد يُضاف).
    public static func mergeLists(_ cur: [JSONObject], _ add: [JSONObject]) -> [JSONObject] {
        var out = cur; let have = Set(cur.compactMap { $0["id"]?.string })
        for l in add where !have.contains(l["id"]?.string ?? "") { out.append(l) }
        return out
    }

    /// دمج التفضيلات: مفاتيح القوائم (اتحاد)، والبقية فقط إن كانت فارغة حاليًا.
    public static func mergePrefs(_ cur: [String: String], _ add: [String: String]) -> [String: String] {
        let arrayKeys: Set<String> = ["vkte_rec_saved", "vkte_rec_ignored", "vkte_recent", "vkte_wish"]
        var out = cur
        for (k, v) in add where !secretPrefs.contains(k) {
            if arrayKeys.contains(k), let a = (try? JSONValue.parse(v))?.array {
                var merged = (try? JSONValue.parse(cur[k] ?? "[]"))?.array ?? []
                for x in a where !merged.contains(x) { merged.append(x) }
                if k == "vkte_recent" { merged = Array(merged.prefix(14)) }
                out[k] = String(decoding: (try? JSONValue.array(merged).encoded()) ?? Data("[]".utf8), as: UTF8.self)
            } else if (cur[k] ?? "").isEmpty { out[k] = v }
        }
        return out
    }

    // MARK: التصدير
    /// تصدير بنفس الصيغة (الصور data URI) — يُقرأ في كل نسخ التطبيق. [photoData]: يحوّل مرجع صورة محلية إلى data URI.
    public static func export(_ items: [Performer], lists: [JSONObject], wlists: [JSONObject], prefs: [String: String],
                              now: Date = Date(), photoData: (String) -> String?) throws -> String {
        var arr: [JSONValue] = []
        for p in items {
            var m = p.raw
            m["photos"] = .array(p.photos.compactMap { photoData($0) }.map { .string($0) })
            if !p.thumb.isEmpty, let t = photoData(p.thumb) { m["thumb"] = .string(t) } else { m["thumb"] = nil }
            arr.append(.object(m))
        }
        var pr = prefs; for k in secretPrefs { pr[k] = nil }
        let doc: JSONValue = ["app": "vkte-favorites", "v": 5, "exportedAt": .int(Int64(now.timeIntervalSince1970 * 1000)),
                              "lists": .array(lists.map { .object($0) }), "wlists": .array(wlists.map { .object($0) }),
                              "prefs": .object(pr.mapValues { .string($0) }), "items": .array(arr)]
        return String(decoding: try doc.encoded(), as: UTF8.self)
    }
}

/// تقرير التحقق بعد الاستيراد: مقارنة ما في الملف بما حُفظ فعلًا (لا يُعلن النجاح لمجرد فتح التطبيق).
public struct MigrationReport: Sendable {
    public var checked = 0
    public var problems: [String] = []
    public var ok: Bool { problems.isEmpty }
    public var summary: [(String, String)] = []

    /// يتحقق أن كل سجل مُضاف أو محدَّث موجود بنفس الاسم والتقييم والمعايير والقوائم وحالة المشاهدة وعدد الصور،
    /// وأن لا سجل كان موجودًا قبل الاستيراد قد اختفى.
    public static func verify(plan: Backup.Plan, before: Set<String>, after: [String: Performer]) -> MigrationReport {
        var r = MigrationReport()
        for id in before where after[id] == nil { r.problems.append("سجل كان موجودًا واختفى: \(id)") }
        for it in plan.items where it.action != .keep {
            r.checked += 1
            let id = it.record["id"]?.string ?? ""
            guard let p = after[id] else { r.problems.append("لم يُحفظ: \(id)"); continue }
            let src = Performer(it.record)
            if p.name != src.name { r.problems.append("الاسم مختلف: \(src.name)") }
            if p.rating != src.rating { r.problems.append("التقييم مختلف: \(src.name)") }
            if p.criteriaValues != src.criteriaValues { r.problems.append("المعايير مختلفة: \(src.name)") }
            if Set(p.lists) != Set(src.lists) { r.problems.append("القوائم مختلفة: \(src.name)") }
            if p.works.count != src.works.count || p.watchedCount != src.watchedCount { r.problems.append("الأعمال أو المشاهدة مختلفة: \(src.name)") }
            if p.photos.count != src.photos.count { r.problems.append("عدد الصور مختلف: \(src.name) (\(p.photos.count) من \(src.photos.count))") }
            if p.notes != src.notes { r.problems.append("الملاحظات مختلفة: \(src.name)") }
        }
        r.summary = [("أُضيف", "\(plan.added)"), ("حُدِّث", "\(plan.updated)"), ("أُكملت صوره", "\(plan.photosFixed)"), ("بقي كما هو", "\(plan.kept)"),
                     ("قاصر رُفض", "\(plan.file.minorsSkipped)"), ("سجل غير صالح", "\(plan.file.invalid)"), ("قوائم جديدة", "\(plan.newLists + plan.newWlists)")]
        return r
    }
}
