import Foundation

// المصادر الرسمية فقط: StashDB (GraphQL) وThePornDB (REST) — عبر URLSession (شبكات Apple، تدعم HTTP/3 التي تتجاوز
// حجب مزوّد الإنترنت لـ ThePornDB بلا VPN). لا كشط، ولا تجاوز لحمايات. بوابة +18 قبل أي إضافة أو صورة.

public struct SourceError: Error, LocalizedError, Sendable {
    public let msg: String; public let status: Int?   // -1 خطأ استعلام (يُجرَّب البديل)، -2 محجوب على هذه الشبكة
    public init(_ msg: String, _ status: Int? = nil) { self.msg = msg; self.status = status }
    public var errorDescription: String? { msg }
}

/// مفاتيح API تُقرأ من مخزن الآيفون الآمن (يحددها التطبيق). لا تُحفظ في الكود ولا في النسخ الاحتياطية.
public enum APIKeyName: String, Sendable { case tpdb = "vkte_key", stash = "vkte_stash", stashURL = "stashapp_url", stashKey = "stashapp_key" }

public final class Net: @unchecked Sendable {
    public static let shared = Net()
    public var keys: (APIKeyName) -> String = { _ in "" }
    var session: URLSession
    private let lock = NSLock()
    public init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }
    /// للاختبارات: جلسة بـ URLProtocol بديل.
    public func use(_ s: URLSession) { lock.lock(); session = s; lock.unlock() }
    private func renew() {
        lock.lock(); defer { lock.unlock() }
        let old = session
        session = URLSession(configuration: old.configuration)
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { old.finishTasksAndInvalidate() }   // لا يقطع طلبات مصدر آخر جارية
    }

    /// إرسال مع إعادة المحاولة: انقطاع الاتصال ⇒ اتصال جديد (3 محاولات)؛ 429/5xx ⇒ انتظار متزايد.
    public func send(_ source: String, _ req: URLRequest) async throws -> (Data, Int) {
        var last: Error?; var lastResp: (Data, Int)?
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(700_000_000 * attempt * attempt)) }
            lock.lock(); let s = session; lock.unlock()
            do {
                let (d, r) = try await s.data(for: req)
                let code = (r as? HTTPURLResponse)?.statusCode ?? 0
                if (code == 429 || code >= 500) && attempt < 2 { lastResp = (d, code); continue }
                return (d, code)
            } catch { last = error; renew() }
        }
        if let lastResp { return lastResp }
        let t = "\(last.map { "\($0)" } ?? "")"
        let reset = looksBlocked(t)
        throw SourceError(reset ? "\(source) غير متاح على شبكتك: الاتصال يُقطع فور طلبه (غالبًا محجوب من مزوّد الإنترنت). يكمل التطبيق بالمصدر الآخر."
                                : "تعذّر الاتصال بـ \(source) — تحقّق من الإنترنت وحاول مجددًا", reset ? -2 : nil)
    }
}

/// مرشح من مصدر رسمي (قبل الإضافة للمكتبة).
public struct Candidate: Identifiable, Hashable, Sendable {
    public let source: String   // stash | tpdb
    public let id, name, aliases, birth, country, image: String
    public let height, careerStart: Int?
    public init(source: String, id: String, name: String, aliases: String = "", birth: String = "", country: String = "", image: String = "", height: Int? = nil, careerStart: Int? = nil) {
        self.source = source; self.id = id; self.name = name; self.aliases = aliases; self.birth = birth; self.country = country; self.image = image; self.height = height; self.careerStart = careerStart
    }
    public var adult: Bool { adultOk(["birth": .string(birth)]) }
}

func cut(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n)) + "…" }

/// أفضل صورة (الأكبر دقة؛ العريضة للمشاهد) — https فقط.
public func bestImage(_ imgs: JSONValue?, wide: Bool = false) -> String {
    let l = (imgs?.array ?? []).compactMap { $0.object }.filter { safeHttps($0["url"]) }
        .sorted { ($0["width"]?.number ?? 0) * ($0["height"]?.number ?? 0) > ($1["width"]?.number ?? 0) * ($1["height"]?.number ?? 0) }
    if wide, let w = l.first(where: { ($0["width"]?.number ?? 0) >= ($0["height"]?.number ?? 1) }) { return w["url"]!.text }
    return l.first?["url"]?.text ?? ""
}

// MARK: - StashDB

public enum StashDB {
    public static let url = URL(string: "https://stashdb.org/graphql")!

    public static func q(_ query: String, _ vars: JSONObject = [:], key: String? = nil) async throws -> JSONObject {
        let k = key ?? Net.shared.keys(.stash)
        if k.isEmpty { throw SourceError("أضف مفتاح StashDB من «المزيد»") }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue(k, forHTTPHeaderField: "ApiKey")
        r.httpBody = try JSONValue.object(["query": .string(query), "variables": .object(vars)]).encoded()
        let (d, code) = try await Net.shared.send("StashDB", r)
        if code == 401 || code == 403 { throw SourceError("مفتاح StashDB غير صالح", code) }
        let j = try? JSONValue.parse(d)
        if code != 200 && j?["data"]?.object == nil { throw SourceError("StashDB: خطأ \(code)", (code == 400 || code == 422) ? -1 : code) }
        if let errs = j?["errors"]?.array, !errs.isEmpty, j?["data"]?.object == nil { throw SourceError("StashDB: \(errs[0]["message"]?.text ?? "")", -1) }
        return j?["data"]?.object ?? [:]
    }

    public static func test(key: String) async throws { _ = try await q("query{me{name}}", key: key) }

    public static func search(_ term: String) async throws -> [Candidate] {
        var d: JSONObject
        do { d = try await q(#"query($t:String!){searchPerformer(term:$t,limit:12){id name aliases birth_date country height career_start_year gender images{url width height}}}"#, ["t": .string(term)]) }
        catch let e as SourceError where e.status == -1 { d = try await q(#"query($t:String!){searchPerformer(term:$t,limit:12){id name aliases birth_date country gender images{url}}}"#, ["t": .string(term)]) }
        return (d["searchPerformer"]?.array ?? []).compactMap { $0.object }.filter { $0["gender"] == nil || $0["gender"]!.isNull || $0["gender"]?.string == "FEMALE" }.map { p in
            Candidate(source: "stash", id: p["id"]!.text, name: p["name"]?.text ?? "", aliases: (p["aliases"]?.array ?? []).map(\.text).joined(separator: ", "),
                      birth: p["birth_date"]?.text ?? "", country: p["country"]?.text ?? "", image: bestImage(p["images"]), height: p["height"]?.int, careerStart: p["career_start_year"]?.int)
        }
    }

    static let sceneFieldSets: [(String, String)] = [
        ("id title release_date duration details studio{name} images{url width height} tags{name}", ",sort:DATE,direction:DESC"),
        ("id title date duration details studio{name} images{url width height}", ",sort:DATE,direction:DESC"),
        ("id title date studio{name}", ""),
    ]

    public static func scenes(_ performerId: String, maxPages: Int = 5) async throws -> [JSONObject] {
        var out: [JSONObject] = []
        for page in 1...max(1, maxPages) {
            var d: JSONObject = [:]
            for (i, f) in sceneFieldSets.enumerated() {
                do { d = try await q("query($id:ID!,$p:Int!){queryScenes(input:{performers:{value:[$id],modifier:INCLUDES},page:$p,per_page:100\(f.1)}){count scenes{\(f.0)}}}", ["id": .string(performerId), "p": .int(Int64(page))]); break }
                catch let e as SourceError { if e.status != -1 || i == sceneFieldSets.count - 1 { throw e } }
            }
            let sc = d["queryScenes"]?["scenes"]?.array ?? []
            for s in sc.compactMap({ $0.object }) {
                var w: JSONObject = ["t": .string((s["title"]?.text ?? "").trimmingCharacters(in: .whitespaces)), "s": .string(s["studio"]?["name"]?.text ?? ""),
                                     "u": .string("https://stashdb.org/scenes/\(s["id"]!.text)"), "is": .string(s["id"]!.text),
                                     "tg": .array((s["tags"]?.array ?? []).prefix(8).compactMap { $0["name"].map { JSONValue.string($0.text) } })]
                for (k, v) in ydOf((s["release_date"] ?? s["date"])?.text ?? "") { w[k] = .string(v) }
                if let du = s["duration"]?.number { w["du"] = .int(Int64((du > 180 ? du / 60 : du).rounded())) }
                if let ds = s["details"]?.text, !ds.isEmpty { w["ds"] = .string(cut(ds, 280)) }
                let img = bestImage(s["images"], wide: true); if !img.isEmpty { w["p"] = .string(img) }
                out.append(w)
            }
            if sc.count < 100 { break }
        }
        return out.filter { !($0["t"]?.text ?? "").isEmpty }
    }

    static let perfFull = "id name disambiguation aliases gender birth_date country ethnicity hair_color eye_color height cup_size band_size waist_size hip_size breast_type career_start_year career_end_year tattoos{location} piercings{location} scene_count images{url width height}"
    static let perfBasic = "id name aliases gender birth_date country height career_start_year scene_count images{url width height}"

    /// الملف المهني الكامل (بيانات وصفية موثّقة فقط).
    public static func performer(_ id: String) async throws -> JSONObject? {
        for f in [perfFull, perfBasic] {
            do { return try await q("query($id:ID!){findPerformer(id:$id){\(f)}}", ["id": .string(id)])["findPerformer"]?.object }
            catch let e as SourceError { if e.status != -1 || f == perfBasic { throw e } }
        }
        return nil
    }

    public static func images(_ p: JSONObject?) -> [String] {
        let l = (p?["images"]?.array ?? []).compactMap { $0.object }.filter { safeHttps($0["url"]) }
            .sorted { ($0["width"]?.number ?? 0) * ($0["height"]?.number ?? 0) > ($1["width"]?.number ?? 0) * ($1["height"]?.number ?? 0) }
        var seen = Set<String>(); return l.map { $0["url"]!.text }.filter { seen.insert($0).inserted }
    }

    /// مرشحات الاقتراحات: «عملت مع» بذورك، «وجوه جديدة»، «من بلدانك». القاصر يُستبعد مبكرًا.
    public static func recPool(seeds: [(String, Double)], countries: [String], progress: ((String) -> Void)? = nil) async throws -> [RecCand] {
        let fields = "id name birth_date country gender career_start_year scene_count images{url width height}"
        var byId: [String: RecCand] = [:]
        func absorb(_ list: JSONValue?, seed: String? = nil, lane: String? = nil) {
            for p in (list?.array ?? []).compactMap({ $0.object }) {
                if let g = p["gender"]?.string, g != "FEMALE" { continue }
                if !adultOk(["birth": p["birth_date"] ?? .null]) { continue }
                let id = p["id"]!.text
                var c = byId[id] ?? RecCand(id: id, name: p["name"]?.text ?? "", birth: p["birth_date"]?.text ?? "", country: p["country"]?.text ?? "",
                                            image: bestImage(p["images"]), careerStart: p["career_start_year"]?.int, scenes: p["scene_count"]?.int)
                if let s = seed { c.withSeeds.insert(s) }; if let l = lane { c.lanes.insert(l) }
                byId[id] = c
            }
        }
        for (i, s) in seeds.enumerated() {
            progress?("تحليل مكتبتك… \(i + 1)/\(seeds.count)")
            do { absorb(try await q("query($id:ID!){queryPerformers(input:{performed_with:$id,gender:FEMALE,sort:SHARED_SCENE_COUNT,direction:DESC,per_page:20}){performers{\(fields)}}}", ["id": .string(s.0)])["queryPerformers"]?["performers"], seed: s.0) }
            catch let e as SourceError { if e.status == 401 || e.status == 403 { throw e } }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        progress?("وجوه جديدة…")
        if let d = try? await q("query{queryPerformers(input:{gender:FEMALE,sort:DEBUT,direction:DESC,per_page:30}){performers{\(fields)}}}") { absorb(d["queryPerformers"]?["performers"], lane: "debut") }
        for c in countries.prefix(2) {
            progress?("من \(c)…")
            if let d = try? await q("query($c:String!){queryPerformers(input:{gender:FEMALE,country:{value:$c,modifier:EQUALS},sort:POPULARITY,direction:DESC,per_page:25}){performers{\(fields)}}}", ["c": .string(c)]) {
                absorb(d["queryPerformers"]?["performers"], lane: "country")
            }
        }
        return Array(byId.values)
    }
}

// MARK: - ThePornDB

public enum TPDB {
    public static let base = "https://api.theporndb.net"
    nonisolated(unsafe) static var blockedUntil: Double = 0
    nonisolated(unsafe) static var blockedMsg = ""
    public static var blocked: Bool { Date().timeIntervalSince1970 < blockedUntil }

    public static func get(_ path: String, key: String? = nil) async throws -> JSONObject {
        let k = key ?? Net.shared.keys(.tpdb)
        if k.isEmpty { throw SourceError("أضف مفتاح ThePornDB من «المزيد»") }
        if blocked && key == nil { throw SourceError(blockedMsg, -2) }
        guard let u = URL(string: base + path) else { throw SourceError("طلب غير صالح") }
        var r = URLRequest(url: u)
        r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        let d: Data, code: Int
        do { (d, code) = try await Net.shared.send("ThePornDB", r) }
        catch let e as SourceError { if e.status == -2 { blockedUntil = Date().timeIntervalSince1970 + 600; blockedMsg = e.msg }; throw e }
        if code == 401 || code == 403 { throw SourceError("مفتاح ThePornDB غير صالح", code) }
        if code == 429 { throw SourceError("ThePornDB: طلبات كثيرة، حاول بعد قليل", 429) }
        if code != 200 { throw SourceError("ThePornDB: خطأ \(code)", code) }
        return (try? JSONValue.parse(d))?.object ?? [:]
    }

    public static func test(key: String) async throws { _ = try await get("/performers?q=a&per_page=1", key: key) }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    public static func search(_ term: String) async throws -> [Candidate] {
        let d = try await get("/performers?q=\(enc(term))&per_page=12")
        return (d["data"]?.array ?? []).compactMap { $0.object }.filter { p in
            let g = p["extras"]?["gender"]; return g == nil || g!.isNull || g!.text.lowercased() == "female"
        }.map { p in
            let x = p["extras"]?.object ?? [:]
            return Candidate(source: "tpdb", id: p["id"]!.text, name: p["name"]?.text ?? "", aliases: (p["aliases"]?.array ?? []).map(\.text).joined(separator: ", "),
                             birth: x["birthday"]?.text ?? "", country: x["nationality"]?.text ?? "", image: (p["image"] ?? p["thumbnail"])?.text ?? "",
                             height: Int((x["height"]?.text ?? "").filter(\.isNumber)), careerStart: Int(x["career_start_year"]?.text ?? ""))
        }
    }

    public static func scenes(_ performerId: String, maxPages: Int = 5) async throws -> [JSONObject] {
        var out: [JSONObject] = []
        for page in 1...max(1, maxPages) {
            let d = try await get("/performers/\(enc(performerId))/scenes?page=\(page)&per_page=100")
            for s in (d["data"]?.array ?? []).compactMap({ $0.object }) {
                let img = (s["background"]?["large"] ?? s["posters"]?["large"] ?? s["image"])?.text ?? ""
                var w: JSONObject = ["t": .string((s["title"]?.text ?? "").trimmingCharacters(in: .whitespaces)), "s": .string(s["site"]?["name"]?.text ?? ""), "ip": .string(s["id"]!.text),
                                     "tg": .array((s["tags"]?.array ?? []).prefix(8).compactMap { $0["name"].map { JSONValue.string($0.text) } })]
                for (k, v) in ydOf(s["date"]?.text ?? "") { w[k] = .string(v) }
                if let du = s["duration"]?.number, du > 0 { w["du"] = .int(Int64((du > 180 ? du / 60 : du).rounded())) }
                if let ds = s["description"]?.text, !ds.isEmpty { w["ds"] = .string(cut(ds, 280)) }
                if safeHttps(.string(img)) { w["p"] = .string(img) }
                if let u = s["url"], safeHttps(u) { w["u"] = u }
                let tr = trailerOf(s); if !tr.isEmpty { w["tr"] = .string(tr) }
                out.append(w)
            }
            if page >= (d["meta"]?["last_page"]?.int ?? 1) { break }
        }
        return out.filter { !($0["t"]?.text ?? "").isEmpty }
    }

    public static func performer(_ id: String) async throws -> JSONObject? {
        let d = try await get("/performers/\(enc(id))")
        return d["data"]?.object ?? d
    }

    public static func images(_ p: JSONObject?) -> [String] {
        guard let p else { return [] }
        var out: [String] = []
        for x in p["posters"]?.array ?? [] { let u = x.object.map { ($0["url"] ?? $0["large"])?.text ?? "" } ?? x.text; if safeHttps(.string(u)) && !out.contains(u) { out.append(u) } }
        let img = p["image"]?.text ?? ""; if safeHttps(.string(img)) && !out.contains(img) { out.insert(img, at: 0) }
        return out
    }

    /// من عمل معها (من مشاهدها): معرّف السجل ⇒ (الاسم، عدد المشاهد المشتركة).
    public static func coStars(_ pdbId: String, pages: Int = 1) async throws -> [String: (String, Int)] {
        var out: [String: (String, Int)] = [:]
        for page in 1...max(1, pages) {
            let d = try await get("/performers/\(enc(pdbId))/scenes?page=\(page)&per_page=100")
            for s in (d["data"]?.array ?? []).compactMap({ $0.object }) {
                for p in (s["performers"]?.array ?? []).compactMap({ $0.object }) {
                    let par = p["parent"]?.object
                    let id = (par?["id"] ?? p["id"])?.text ?? "", name = (par?["name"] ?? p["name"])?.text ?? ""
                    let g = (par?["extras"]?["gender"] ?? p["extra"]?["gender"] ?? p["extras"]?["gender"])?.text.lowercased() ?? ""
                    if id.isEmpty || id == pdbId || name.isEmpty || (!g.isEmpty && g != "female") { continue }
                    out[id] = (name, (out[id]?.1 ?? 0) + 1)
                }
            }
            if page >= (d["meta"]?["last_page"]?.int ?? 1) { break }
        }
        return out
    }
}

/// رابط الإعلان الرسمي لمشهد ThePornDB (نص، أو {url}، أو قائمة) — https فقط.
public func trailerOf(_ s: JSONObject) -> String {
    for v in [s["trailer"], s["trailers"], s["media"]?["trailer"]] {
        guard let v else { continue }
        if let t = v.string, safeHttps(v) { return t }
        if let u = v["url"], safeHttps(u) { return u.text }
        for x in v.array ?? [] { if let t = x.string, safeHttps(x) { return t }; if let u = x["url"], safeHttps(u) { return u.text } }
    }
    return ""
}

/// بيانات ThePornDB الوصفية بصيغة حقول StashDB (لتحليل الذوق) — ما لا يُعرف يبقى غائبًا.
public func tpdbAsStash(_ p: JSONObject) -> JSONObject {
    let x = p["extras"]?.object ?? [:]
    func pick(_ v: JSONValue?, _ m: [(String, String)]) -> String? { let s = (v?.text ?? "").lowercased(); if s.isEmpty { return nil }; return m.first { s.contains($0.0) }?.1 }
    func yes(_ v: JSONValue?) -> Bool { let s = (v?.text ?? "").lowercased().trimmingCharacters(in: .whitespaces); return !s.isEmpty && !["none", "no", "n/a", "na", "unknown", "-", "false"].contains(s) }
    func int(_ v: JSONValue?) -> Int? { v?.int ?? Int((v?.text ?? "").filter(\.isNumber)) }
    var o: JSONObject = ["id": p["id"] ?? .null, "name": p["name"] ?? .null]
    if let g = x["gender"], !g.isNull { o["gender"] = .string(g.text.lowercased() == "female" ? "FEMALE" : "OTHER") }
    if let b = x["birthday"], !b.text.isEmpty { o["birth_date"] = b }
    if let c = x["birthplace_code"]?.text, c.count == 2 { o["country"] = .string(c) }
    if let e = pick(x["ethnicity"], [("caucas", "CAUCASIAN"), ("white", "CAUCASIAN"), ("black", "BLACK"), ("ebony", "BLACK"), ("asian", "ASIAN"), ("indian", "INDIAN"), ("latin", "LATIN"), ("hispanic", "LATIN"), ("middle", "MIDDLE_EASTERN"), ("arab", "MIDDLE_EASTERN"), ("mix", "MIXED")]) { o["ethnicity"] = .string(e) }
    if let h = pick(x["hair_colour"], [("blond", "BLONDE"), ("brunet", "BRUNETTE"), ("brown", "BRUNETTE"), ("black", "BLACK"), ("red", "RED"), ("auburn", "AUBURN"), ("grey", "GREY"), ("gray", "GREY")]) { o["hair_color"] = .string(h) }
    if let e = pick(x["eye_colour"], [("blue", "BLUE"), ("brown", "BROWN"), ("green", "GREEN"), ("hazel", "HAZEL"), ("grey", "GREY"), ("gray", "GREY")]) { o["eye_color"] = .string(e) }
    for (src, dst) in [("height", "height"), ("waist", "waist_size"), ("hips", "hip_size"), ("career_start_year", "career_start_year"), ("career_end_year", "career_end_year")] { if let v = int(x[src]) { o[dst] = .int(Int64(v)) } }
    let cup = (x["cupsize"]?.text ?? "").uppercased()
    let letters = cup.filter { ("A"..."K").contains($0) }; if !letters.isEmpty { o["cup_size"] = .string(String(letters)) }
    if let b = x["fake_boobs"]?.bool { o["breast_type"] = .string(b ? "FAKE" : "NATURAL") }
    if let t = x["tattoos"] { o["tattoos"] = .array(yes(t) ? [["location": .string(t.text)]] : []) }
    if let t = x["piercings"] { o["piercings"] = .array(yes(t) ? [["location": .string(t.text)]] : []) }
    return o
}

/// يملأ الحقول الناقصة في a من b (لا يستبدل الموجود).
public func fillFrom(_ a: JSONObject, _ b: JSONObject) -> JSONObject {
    var o = a
    for (k, v) in b { let e = o[k]; if e == nil || e!.isNull || e!.string == "" || (e!.array?.isEmpty == true && v.array?.isEmpty != true) { o[k] = v } }
    return o
}

/// دمج أعمال جديدة (قاعدة التطبيق السابق): نفس العمل ⇒ تُملأ الحقول الفارغة فقط ولا يُحذف شيء؛ الجديد يأخذ a = الآن.
public func mergeWorks(_ cur: [JSONObject], _ incoming: [JSONObject]) -> (list: [JSONObject], added: Int, filled: Int) {
    var out = cur
    var byId: [String: Int] = [:], byT: [String: [Int]] = [:]
    func index(_ i: Int) { for x in sceneIdsOf(out[i]) { byId[x] = i }; let k = normTitle(out[i]["t"]?.text ?? ""); if !(byT[k] ?? []).contains(i) { byT[k, default: []].append(i) } }
    for i in out.indices { index(i) }
    var added = 0, filled = 0
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    for w in safeWorks(.array(incoming.map { .object($0) })).compactMap({ $0.object }) {
        var i: Int? = nil
        for x in sceneIdsOf(w) where i == nil { i = byId[x] }
        if let j = i, idConflict(out[j], w) { i = nil }
        if i == nil { i = (byT[normTitle(w["t"]?.text ?? "")] ?? []).first { sameWork(out[$0], w) } }
        guard let t = i else { var n = w; if n["a"] == nil { n["a"] = .int(now) }; out.append(n); index(out.count - 1); added += 1; continue }
        var ch = false
        for (f, v) in w {
            let e = out[t][f]
            let empty = e == nil || e!.isNull || e!.string == "" || e!.array?.isEmpty == true
            let has = !v.isNull && v.string != "" && v.array?.isEmpty != true
            if empty && has { out[t][f] = v; ch = true }
        }
        if ch { filled += 1; index(t) }
    }
    return (out, added, filled)
}

public func dedupeWorks(_ ws: [JSONObject]) -> (list: [JSONObject], removed: Int) {
    let m = mergeWorks([], ws); return (m.list, ws.count - m.list.count)
}

// MARK: - المصدران معًا

func namesOf(_ name: String, _ aliases: String) -> Set<String> {
    var s: Set<String> = [norm(name)]
    for a in aliases.components(separatedBy: CharacterSet(charactersIn: ",،;/")) where norm(a).count >= 3 { s.insert(norm(a)) }
    s.remove(""); return s
}
func fullDate(_ s: String) -> String { matches(s, #"^\d{4}-\d{2}-\d{2}"#) ? String(s.prefix(10)) : "" }

/// نفس الشخص في المصدرين؟ (محافظ: الخطأ يخلط ممثلتين)
public func samePerson(_ a: Candidate, _ b: Candidate) -> Bool {
    let na = namesOf(a.name, a.aliases), nb = namesOf(b.name, b.aliases)
    if na.isDisjoint(with: nb) { return false }
    let fa = fullDate(a.birth), fb = fullDate(b.birth)
    if !fa.isEmpty && !fb.isEmpty { return fa == fb }
    let ya = matches(a.birth, #"^\d{4}"#) ? String(a.birth.prefix(4)) : "", yb = matches(b.birth, #"^\d{4}"#) ? String(b.birth.prefix(4)) : ""
    let ca = a.country.trimmingCharacters(in: .whitespaces).uppercased(), cb = b.country.trimmingCharacters(in: .whitespaces).uppercased()
    let countryOk = ca.isEmpty || cb.isEmpty || ca == cb || ca.count != cb.count
    if !ya.isEmpty && !yb.isEmpty && ya != yb { return false }
    if !countryOk { return false }
    if norm(a.name) == norm(b.name) { return true }
    func distinctive(_ n: String) -> Bool { n.split(separator: " ").count >= 2 }
    return (na.contains(norm(b.name)) && (distinctive(norm(b.name)) || nb.contains(norm(a.name))))
        || (nb.contains(norm(a.name)) && (distinctive(norm(a.name)) || na.contains(norm(b.name))))
}

/// كل سجلات الممثلة في المصدرين: يبحث باسمها وأسمائها الأخرى (حتى 6) ويقبل ما يطابقها بمطابقة محافظة.
public func findAllRecords(_ c: Candidate, progress: ((String) -> Void)? = nil) async -> (stash: [Candidate], tpdb: [Candidate]) {
    var names: [String] = []
    for n in ([c.name] + c.aliases.components(separatedBy: CharacterSet(charactersIn: ",،;/")).map { $0.trimmingCharacters(in: .whitespaces) }) where n.count >= 3 && !names.contains(where: { norm($0) == norm(n) }) { names.append(n) }
    var stash: [String: Candidate] = c.source == "stash" ? [c.id: c] : [:], tpdb: [String: Candidate] = c.source == "tpdb" ? [c.id: c] : [:]
    let hasS = !Net.shared.keys(.stash).isEmpty, hasT = !Net.shared.keys(.tpdb).isEmpty
    for n in names.prefix(6) {
        progress?("البحث عن «\(n)» في المصدرين…")
        async let s: [Candidate] = hasS ? ((try? await StashDB.search(n)) ?? []) : []
        async let t: [Candidate] = hasT ? ((try? await TPDB.search(n)) ?? []) : []
        for x in await s where x.adult && ((x.id == c.id && c.source == "stash") || samePerson(c, x)) { if stash[x.id] == nil { stash[x.id] = x } }
        for x in await t where x.adult && ((x.id == c.id && c.source == "tpdb") || samePerson(c, x)) { if tpdb[x.id] == nil { tpdb[x.id] = x } }
    }
    return (Array(stash.values), Array(tpdb.values))
}

public struct DualProfile: Sendable {
    public var info: JSONObject = [:], images: [String] = [], works: [JSONObject] = [], errors: [String] = [], sources: [String] = []
    public var stashIds: [String] = [], pdbIds: [String] = [], minor = false
    public var attrs: JSONObject = [:]   // بيانات وصفية بصيغة StashDB (لتحليل الذوق)
}

/// يجلب من كل سجلاتها في المصدرين: المعلومات ⇒ بوابة +18 (لكل السجلات) ⇒ ثم كل الأعمال وكل الصور، مدمجة بلا تكرار.
public func fetchBoth(stashIds sIds: [String], pdbIds tIds: [String], maxPages: Int = 40) async -> DualProfile {
    var out = DualProfile()
    let hasS = !Net.shared.keys(.stash).isEmpty, hasT = !Net.shared.keys(.tpdb).isEmpty
    var sp: [String: JSONObject] = [:], tp: [String: JSONObject] = [:]
    if hasS { for id in sIds where !id.isEmpty { do { if let v = try await StashDB.performer(id) { sp[id] = v } } catch { out.errors.append("StashDB: \(error.localizedDescription)") } } }
    if hasT { for id in tIds where !id.isEmpty { do { if let v = try await TPDB.performer(id) { tp[id] = v } } catch { out.errors.append("ThePornDB: \(error.localizedDescription)") } } }
    let births = sp.values.map { $0["birth_date"]?.text ?? "" } + tp.values.map { $0["extras"]?["birthday"]?.text ?? "" }
    // البوابة: أي سجل يقول أقل من 18 أو تاريخ غير صالح ⇒ رفض كامل قبل أي صورة أو عمل
    if births.filter({ !$0.isEmpty }).contains(where: { !adultOk(["birth": .string($0)]) }) { out.minor = true; return out }
    let sMain = sIds.first.flatMap { sp[$0] } ?? sp.values.first, tMain = tIds.first.flatMap { tp[$0] } ?? tp.values.first
    if let b = births.first(where: { !$0.isEmpty }) { out.info["birth"] = .string(b) }
    let country = ([sMain?["country"]] + sp.values.map { $0["country"] } + [tMain?["extras"]?["nationality"], tMain?["extras"]?["birthplace_code"]]).compactMap { $0?.text }.first { !$0.isEmpty }
    if let c = country { out.info["country"] = .string(c) }
    if let h = ([sMain?["height"]] + sp.values.map { $0["height"] } + tp.values.map { $0["extras"]?["height"] }).compactMap({ $0?.int ?? Int($0?.text.filter(\.isNumber) ?? "") }).first { out.info["height"] = .int(Int64(h)) }
    if let cs = ([sMain?["career_start_year"]] + sp.values.map { $0["career_start_year"] } + tp.values.map { $0["extras"]?["career_start_year"] }).compactMap({ $0?.int ?? Int($0?.text ?? "") }).first { out.info["cs"] = .int(Int64(cs)) }
    var al: [String] = []
    for p in Array(sp.values) + Array(tp.values) { for a in (p["aliases"]?.array ?? []).map(\.text) + [p["name"]?.text ?? ""] where !a.trimmingCharacters(in: .whitespaces).isEmpty && !al.contains(a) { al.append(a) } }
    if !al.isEmpty { out.info["aliases"] = .string(al.joined(separator: ", ")) }
    if !sp.isEmpty { out.sources.append("StashDB") }; if !tp.isEmpty { out.sources.append("ThePornDB") }
    var attrs = sMain ?? [:]; if let t = tMain { attrs = attrs.isEmpty ? tpdbAsStash(t) : fillFrom(attrs, tpdbAsStash(t)) }
    out.attrs = attrs
    var works: [JSONObject] = []
    for id in sp.keys { do { works = mergeWorks(works, try await StashDB.scenes(id, maxPages: maxPages)).list } catch { out.errors.append("أعمال StashDB: \(error.localizedDescription)") } }
    for id in tp.keys { do { works = mergeWorks(works, try await TPDB.scenes(id, maxPages: maxPages)).list } catch { out.errors.append("أعمال ThePornDB: \(error.localizedDescription)") } }
    out.works = works
    var imgs: [String] = []
    for p in ([sMain].compactMap { $0 } + Array(sp.values)) { for u in StashDB.images(p) where !imgs.contains(u) { imgs.append(u) } }
    for p in ([tMain].compactMap { $0 } + Array(tp.values)) { for u in TPDB.images(p) where !imgs.contains(u) { imgs.append(u) } }
    out.images = imgs; out.stashIds = Array(sp.keys); out.pdbIds = Array(tp.keys)
    return out
}

// MARK: - الاقتراحات

/// مرشحة اقتراح (من StashDB الرسمي) مع أسبابها — كل سبب له مصدر.
public struct RecCand: Identifiable, Hashable, Sendable {
    public let id, name, birth, country, image: String
    public let careerStart, scenes: Int?
    public var withSeeds: Set<String> = [], lanes: Set<String> = []
    public var score = 0.0, reasons: [String] = []
    public init(id: String, name: String, birth: String = "", country: String = "", image: String = "", careerStart: Int? = nil, scenes: Int? = nil) {
        self.id = id; self.name = name; self.birth = birth; self.country = country; self.image = image; self.careerStart = careerStart; self.scenes = scenes
    }
    public var adult: Bool { adultOk(["birth": .string(birth)]) }
    public var age: Int? { sdAge(birth).age }
    public var young18to21: Bool { verifiedYoungAdult(birth) != nil }
    public var json: JSONValue {
        ["id": .string(id), "name": .string(name), "birth": .string(birth), "country": .string(country), "image": .string(image), "cs": careerStart.map { .int(Int64($0)) } ?? .null,
         "sc": scenes.map { .int(Int64($0)) } ?? .null, "w": .array(withSeeds.sorted().map { .string($0) }), "l": .array(lanes.sorted().map { .string($0) })]
    }
    public init?(json j: JSONValue) {
        guard let id = j["id"]?.string else { return nil }
        self.init(id: id, name: j["name"]?.text ?? "", birth: j["birth"]?.text ?? "", country: j["country"]?.text ?? "", image: j["image"]?.text ?? "", careerStart: j["cs"]?.int, scenes: j["sc"]?.int)
        withSeeds = Set((j["w"]?.array ?? []).compactMap { $0.string }); lanes = Set((j["l"]?.array ?? []).compactMap { $0.string })
    }
}

public func seedWeight(_ p: Performer) -> Double { p.rating / 5 + (p.fav ? 0.6 : 0) + min(0.4, Double(p.views) * 0.05) + (p.tier == "S" ? 0.3 : p.tier == "A" ? 0.15 : 0) }

/// يرتّب المرشحات ويكتب أسبابًا مفهومة. [lib] مكتبتك (بعد البوابة)، [hidden] من أخفيتها.
public func rankRecs(_ pool: [RecCand], _ lib: [Performer], hidden: Set<String> = []) -> [RecCand] {
    let inLib = Set(lib.flatMap(\.stashIds)), names = Set(lib.map { norm($0.name) })
    var seedW: [String: Double] = [:], seedName: [String: String] = [:]
    for p in lib { for s in p.stashIds { seedW[s] = seedWeight(p); seedName[s] = p.name } }
    var cc: [String: Int] = [:]; for p in lib where !p.country.isEmpty { cc[p.country.uppercased(), default: 0] += 1 }
    let ccTotal = max(1, cc.values.reduce(0, +))
    let ages = lib.compactMap(\.age).sorted(); let medAge = ages.isEmpty ? nil : ages[ages.count / 2]
    var out: [RecCand] = []
    for var c in pool {
        if !c.adult || inLib.contains(c.id) || names.contains(norm(c.name)) || hidden.contains(c.id) { continue }
        let ws = c.withSeeds.filter { seedW[$0] != nil }.sorted { seedW[$0]! > seedW[$1]! }
        let co = ws.reduce(0) { $0 + seedW[$1]! }
        let ccShare = c.country.isEmpty ? 0 : Double(cc[c.country.uppercased()] ?? 0) / Double(ccTotal)
        let ageFit = (medAge == nil || c.age == nil) ? 0 : max(0, 1 - Double(abs(c.age! - medAge!)) / 10)
        let pop = c.scenes.map { min(1, log(1 + Double($0)) / log(400)) } ?? 0
        c.score = 0.55 * min(1, co / 2.5) + 0.2 * ccShare + 0.12 * ageFit + 0.13 * pop
        var r: [String] = []
        if !ws.isEmpty { r.append("عملت مع \(ws.prefix(2).compactMap { seedName[$0] }.joined(separator: " و"))\(ws.count > 2 ? " و\(ws.count - 2) أخريات" : "") من مكتبتك") }
        if ccShare >= 0.15 { r.append("من \(c.country) مثل \(cc[c.country.uppercased()]!) من مكتبتك") }
        if c.lanes.contains("debut"), let cs = c.careerStart { r.append("بدأت مسيرتها \(cs)") }
        if ageFit > 0.7 { r.append("قريبة من الفئة العمرية التي تفضّلها") }
        c.reasons = r
        out.append(c)
    }
    return out.sorted { $0.score > $1.score }
}

/// اختيار ثابت طوال اليوم، بحد للبلد الواحد كي يتنوّع.
public func dailyPick(_ ranked: [RecCand], n: Int = 8, perCountry: Int = 2, day: Date = Date()) -> [RecCand] {
    let t = ymd(day)
    var rng = SeededRandom(seed: UInt64(t.0 * 10000 + t.1 * 100 + t.2))
    var top = Array(ranked.prefix(max(n * 3, 24))); top.shuffle(using: &rng)
    var cnt: [String: Int] = [:], out: [RecCand] = []
    for c in top { let k = c.country.isEmpty ? "?" : c.country; if cnt[k, default: 0] >= perCountry { continue }; cnt[k, default: 0] += 1; out.append(c); if out.count >= n { break } }
    return out.sorted { $0.score > $1.score }
}
