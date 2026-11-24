import Foundation

/// خادم Stash الخاص بك (برنامج Stash على حاسوبك): فيديوهاتك عبر واجهته الرسمية (GraphQL) على شبكة المنزل.
/// العنوان والمفتاح في المخزن الآمن. بوابة +18 على تواريخ الخادم قبل عرض أي مشهد.
public enum StashServer {
    public static func normalize(_ u: String) -> String {
        var s = u.trimmingCharacters(in: .whitespacesAndNewlines); if s.isEmpty { return "" }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    public static var url: String { normalize(Net.shared.keys(.stashURL)) }
    public static var key: String { Net.shared.keys(.stashKey).trimmingCharacters(in: .whitespaces) }
    public static var configured: Bool { !url.isEmpty }

    public static func q(_ query: String, _ vars: JSONObject = [:], url u: String? = nil, key k: String? = nil) async throws -> JSONObject {
        let base = u.map(normalize) ?? url, apiKey = k ?? key
        guard !base.isEmpty, let endpoint = URL(string: base + "/graphql") else { throw SourceError("أضف عنوان خادم Stash من «الشبكة والمقاطع»") }
        var r = URLRequest(url: endpoint); r.httpMethod = "POST"; r.timeoutInterval = 12
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); if !apiKey.isEmpty { r.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        r.httpBody = try JSONValue.object(["query": .string(query), "variables": .object(vars)]).encoded()
        let d: Data, code: Int
        do { (d, code) = try await Net.shared.send("Stash", r) }
        catch { throw SourceError("لا يصل خادم Stash على \(base) — تأكد أنه يعمل وأن الجوال على نفس شبكة المنزل") }
        if code == 401 || code == 403 { throw SourceError("خادم Stash رفض المفتاح — انسخ «API Key» من إعداداته (Security)", code) }
        if code != 200 { throw SourceError("خادم Stash: خطأ \(code)", code) }
        let j = try? JSONValue.parse(d)
        if let errs = j?["errors"]?.array, !errs.isEmpty, j?["data"]?.object == nil { throw SourceError("خادم Stash: \(errs[0]["message"]?.text ?? "")", -1) }
        return j?["data"]?.object ?? [:]
    }

    public static func test(url: String, key: String) async throws -> String {
        try await q("query{version{version}}", url: url, key: key)["version"]?["version"]?.text ?? "?"
    }

    /// رابط يحمل المفتاح (Stash يقبل ?apikey= في روابط البث والصور).
    public static func withKey(_ u: String, _ key: String) -> String {
        guard !key.isEmpty, !u.isEmpty, var c = URLComponents(string: u) else { return u }
        var items = (c.queryItems ?? []).filter { $0.name != "apikey" }; items.append(URLQueryItem(name: "apikey", value: key)); c.queryItems = items
        return c.string ?? u
    }

    /// معرّف الممثلة في خادمك: بمعرّف StashDB أولًا، وإلا بالاسم أو الاسم البديل المطابق حرفيًا.
    public static func localPerformer(_ p: Performer) async throws -> String? {
        for sid in p.stashIds {
            let d = try await q(#"query($e:String!,$id:String!){findPerformers(performer_filter:{stash_id_endpoint:{endpoint:$e,stash_id:$id,modifier:EQUALS}},filter:{per_page:5}){performers{id name}}}"#,
                                ["e": "https://stashdb.org/graphql", "id": .string(sid)])
            if let id = d["findPerformers"]?["performers"]?.array?.first?["id"]?.text { return id }
        }
        let d = try await q(#"query($q:String!){findPerformers(filter:{q:$q,per_page:5}){performers{id name alias_list}}}"#, ["q": .string(p.name)])
        for x in (d["findPerformers"]?["performers"]?.array ?? []).compactMap({ $0.object }) {
            let names = Set([norm(x["name"]?.text ?? "")] + (x["alias_list"]?.array ?? []).map { norm($0.text) })
            if names.contains(norm(p.name)) { return x["id"]?.text }
        }
        return nil
    }

    public static let sceneFields = "id title date play_count resume_time files{duration width height format video_codec} paths{stream preview screenshot vtt sprite} scene_markers{id title seconds end_seconds primary_tag{name}} performers{id name birthdate} studio{name}"
    public static let iosContainers: Set<String> = ["mp4", "mov", "m4v"], iosCodecs: Set<String> = ["h264", "hevc", "h265"]

    /// مشهد ⇒ «عمل» + بياناته الإضافية. أي ممثلة في المشهد تاريخها يقول أقل من 18 (أو غير صالح) ⇒ يُستبعد المشهد كله.
    /// [libraryOnly]: ممثلات مكتبتك فقط (الخلاصة)؛ وإلا كل ممثلات المشهد.
    public static func parseScene(_ s: JSONObject, key: String, byLocal: [String: Performer], libraryOnly: Bool = false) -> (WorkGroup, StashExtra)? {
        let paths = s["paths"]?.object ?? [:]
        let stream = paths["stream"]?.text ?? ""; if stream.isEmpty { return nil }
        let ps = (s["performers"]?.array ?? []).compactMap { $0.object }
        if ps.contains(where: { !adultOk(["birthRaw": $0["birthdate"] ?? .string("")]) }) { return nil }
        var who: [Performer] = []
        for pp in ps {
            let lid = pp["id"]?.text ?? ""
            if let lp = byLocal[lid] { who.append(lp) }
            else if !libraryOnly {
                var r: JSONObject = ["id": .string("stashp:\(lid)"), "name": .string(pp["name"]?.text ?? "")]
                if let b = pp["birthdate"]?.string, !b.isEmpty { r["birth"] = .string(b) }
                who.append(Performer(r))
            }
        }
        if (libraryOnly && who.isEmpty) || who.contains(where: \.isMinor) { return nil }
        let f = (s["files"]?.array ?? []).first?.object
        var g = WorkGroup(key: "stash:\(s["id"]!.text)")
        let title = (s["title"]?.text ?? "").trimmingCharacters(in: .whitespaces)
        g.t = title.isEmpty ? "مقطع من خادمك" : title
        g.s = s["studio"]?["name"]?.text ?? ""
        g.d = s["date"]?.text ?? ""; g.y = g.d.count >= 4 ? String(g.d.prefix(4)) : ""
        g.p = withKey(paths["screenshot"]?.text ?? "", key); g.tr = withKey(stream, key)
        g.du = Int(((f?["duration"]?.number ?? 0) / 60).rounded())
        g.who = who
        let fmt = (f?["format"]?.text ?? "").lowercased(), vc = (f?["video_codec"]?.text ?? "").lowercased()
        let markers = (s["scene_markers"]?.array ?? []).compactMap { $0.object }.compactMap { m -> StashMarker? in
            guard let at = m["seconds"]?.number else { return nil }
            let t = (m["title"]?.text ?? "").trimmingCharacters(in: .whitespaces)
            return StashMarker(at: at, end: m["end_seconds"]?.number, label: t.isEmpty ? (m["primary_tag"]?["name"]?.text ?? "") : t)
        }
        let ex = StashExtra(id: s["id"]!.text, vtt: withKey(paths["vtt"]?.text ?? "", key), resume: s["resume_time"]?.number ?? 0, plays: s["play_count"]?.int ?? 0,
                            markers: markers, direct: f == nil || (iosContainers.contains(fmt) && iosCodecs.contains(vc)), height: f?["height"]?.int ?? 0)
        return (g, ex)
    }

    /// مقاطع ممثلاتك في خادمك (عشوائية) للخلاصة.
    public static func scenes(byLocal: [String: Performer], page: Int = 1) async throws -> [(WorkGroup, StashExtra)] {
        if byLocal.isEmpty { return [] }
        let d = try await q("query($ids:[ID!],$p:Int!){findScenes(scene_filter:{performers:{value:$ids,modifier:INCLUDES}},filter:{per_page:100,page:$p,sort:\"random\"}){count scenes{\(sceneFields)}}}",
                            ["ids": .array(byLocal.keys.map { .string($0) }), "p": .int(Int64(page))])
        return (d["findScenes"]?["scenes"]?.array ?? []).compactMap { $0.object }.compactMap { parseScene($0, key: key, byLocal: byLocal, libraryOnly: true) }
    }

    /// مكتبة Stash كاملة: بحث وترتيب وتصفية وصفحات. [mode] = "resume" لـ«تابع المشاهدة».
    public static func browse(query: String = "", sort: String = "random", desc: Bool = true, page: Int = 1, perPage: Int = 40, performer: String? = nil,
                              mine: [String]? = nil, mode: String = "", byLocal: [String: Performer] = [:]) async throws -> ([(WorkGroup, StashExtra)], Int) {
        let ids = performer.map { [$0] } ?? mine
        var filter: [String] = []
        if let ids, !ids.isEmpty { filter.append("performers:{value:$ids,modifier:INCLUDES}") }
        if mode == "resume" { filter.append("resume_time:{value:10,modifier:GREATER_THAN}") }
        let idsVar = (ids?.isEmpty == false) ? ",$ids:[ID!]" : ""
        var vars: JSONObject = ["q": .string(query), "p": .int(Int64(page)), "n": .int(Int64(perPage)), "s": .string(sort), "dir": .string(desc ? "DESC" : "ASC")]
        if let ids, !ids.isEmpty { vars["ids"] = .array(ids.map { .string($0) }) }
        let d = try await q("query($q:String,$p:Int!,$n:Int!,$s:String,$dir:SortDirectionEnum\(idsVar)){findScenes(scene_filter:{\(filter.joined(separator: ","))},filter:{q:$q,page:$p,per_page:$n,sort:$s,direction:$dir}){count scenes{\(sceneFields)}}}", vars)
        let r = d["findScenes"]
        return ((r?["scenes"]?.array ?? []).compactMap { $0.object }.compactMap { parseScene($0, key: key, byLocal: byLocal) }, r?["count"]?.int ?? 0)
    }

    public struct ServerPerformer: Identifiable, Sendable { public let id, name, image: String; public let scenes: Int; public let fav: Bool }

    /// ممثلات الخادم (بوابة +18 على تواريخهن).
    public static func performers(query: String = "", page: Int = 1, perPage: Int = 60) async throws -> ([ServerPerformer], Int) {
        let d = try await q(#"query($q:String,$p:Int!,$n:Int!){findPerformers(performer_filter:{scene_count:{value:0,modifier:GREATER_THAN}},filter:{q:$q,page:$p,per_page:$n,sort:"scenes_count",direction:DESC}){count performers{id name birthdate image_path scene_count favorite}}}"#,
                            ["q": .string(query), "p": .int(Int64(page)), "n": .int(Int64(perPage))])
        let r = d["findPerformers"]
        let l = (r?["performers"]?.array ?? []).compactMap { $0.object }.filter { adultOk(["birthRaw": $0["birthdate"] ?? .string("")]) }.map {
            ServerPerformer(id: $0["id"]!.text, name: $0["name"]?.text ?? "", image: withKey($0["image_path"]?.text ?? "", key), scenes: $0["scene_count"]?.int ?? 0, fav: $0["favorite"]?.bool == true)
        }
        return (l, r?["count"]?.int ?? 0)
    }

    /// بث HLS بديل (sceneStreams) لصيغة لا يشغّلها الآيفون أو عند فشل المباشر.
    public static func hls(_ id: String) async -> String? {
        guard let d = try? await q(#"query($id:ID){sceneStreams(id:$id){url mime_type label}}"#, ["id": .string(id)]) else { return nil }
        let h = (d["sceneStreams"]?.array ?? []).compactMap { $0.object }.first { ($0["mime_type"]?.text ?? "").contains("mpegurl") || ($0["label"]?.text ?? "").uppercased().contains("HLS") }
        return h.map { withKey($0["url"]!.text, key) }
    }

    /// مزامنة مكان التوقف ومدة المشاهدة مع Stash، وتسجيل «مشاهدة».
    public static func saveActivity(_ id: String, resume: Double, played: Double) async {
        _ = try? await q(#"mutation($id:ID!,$r:Float,$d:Float){sceneSaveActivity(id:$id,resume_time:$r,playDuration:$d)}"#, ["id": .string(id), "r": .double(resume), "d": .double(played)])
    }
    public static func addPlay(_ id: String) async { _ = try? await q(#"mutation($id:ID!){sceneAddPlay(id:$id){count}}"#, ["id": .string(id)]) }

    /// ما تملكه لكل ممثلة (بمعرّفها في الخادم) بصيغة «عمل» للمقارنة.
    public static func owned(_ localIds: [String]) async throws -> [String: [JSONObject]] {
        var out = Dictionary(uniqueKeysWithValues: localIds.map { ($0, [JSONObject]()) })
        if localIds.isEmpty { return out }
        let d = try await q(#"query($ids:[ID!]){findScenes(scene_filter:{performers:{value:$ids,modifier:INCLUDES}},filter:{per_page:-1}){scenes{id title date studio{name} stash_ids{endpoint stash_id} performers{id}}}}"#,
                            ["ids": .array(localIds.map { .string($0) })])
        for s in (d["findScenes"]?["scenes"]?.array ?? []).compactMap({ $0.object }) {
            let w = sceneAsWork(s)
            for pp in s["performers"]?.array ?? [] { if let id = pp["id"]?.text, out[id] != nil { out[id]!.append(w) } }
        }
        return out
    }

    public static func sceneAsWork(_ s: JSONObject) -> JSONObject {
        func idFor(_ host: String) -> String { (s["stash_ids"]?.array ?? []).first { ($0["endpoint"]?.text ?? "").contains(host) }?["stash_id"]?.text ?? "" }
        var w: JSONObject = ["t": .string(s["title"]?.text ?? ""), "s": .string(s["studio"]?["name"]?.text ?? ""), "d": .string(s["date"]?.text ?? ""), "sid": .string(s["id"]?.text ?? "")]
        let a = idFor("stashdb.org"), b = idFor("theporndb"); if !a.isEmpty { w["is"] = .string(a) }; if !b.isEmpty { w["ip"] = .string(b) }
        return w
    }

    /// ملف VTT للصور المصغرة.
    public static func thumbs(_ vttURL: String) async -> [VttCue] {
        guard let u = URL(string: vttURL), let res = try? await Net.shared.send("Stash", URLRequest(url: u)), res.1 == 200 else { return [] }
        return parseVtt(String(decoding: res.0, as: UTF8.self), base: vttURL)
    }
}

public struct StashMarker: Sendable, Equatable { public let at: Double; public let end: Double?; public let label: String
    public init(at: Double, end: Double?, label: String) { self.at = at; self.end = end; self.label = label } }

public struct StashExtra: Sendable {
    public let id, vtt: String; public var resume: Double; public let plays: Int; public let markers: [StashMarker]; public let direct: Bool; public let height: Int
}

/// مقاطع قصيرة من العلامات: الطول من نهاية العلامة أو 30 ث، بين 8 و90، بلا تداخل، [max] كحد.
public func markerSegments(_ ms: [StashMarker], durationSec: Int, max mx: Int = 3) -> [(start: Int, len: Int, label: String)] {
    var out: [(Int, Int, String)] = []
    for m in ms.sorted(by: { $0.at < $1.at }) {
        let s = Int(m.at.rounded(.down)); if s < 0 || (durationSec > 0 && s >= durationSec - 5) { continue }
        var len = m.end.map { $0 > m.at ? Int(($0 - m.at).rounded()) : 30 } ?? 30
        len = min(90, max(8, len))
        if durationSec > 0 && s + len > durationSec { len = durationSec - s }
        if let last = out.last, s < last.0 + last.1 { continue }
        out.append((s, len, m.label)); if out.count >= mx { break }
    }
    return out.map { ($0.0, $0.1, $0.2) }
}

/// مقطع قصير ثابت لكل فيديو (من معرّفه): بداية بين 10٪ و80٪ وطول 45 ثانية.
public func shortSegment(key: String, durationSec: Int, len: Int = 45) -> (start: Int, len: Int) {
    if durationSec <= len + 20 { return (0, 0) }
    var h: UInt64 = 1469598103934665603; for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    var rng = SeededRandom(seed: h)
    let start = Int((Double(durationSec) * (0.1 + rng.unit() * 0.7)).rounded())
    return (min(max(0, start), durationSec - len), len)
}

public struct VttCue: Sendable { public let start, end: Double; public let url: String; public let x, y, w, h: Int }

func vttTime(_ t: String) -> Double { t.trimmingCharacters(in: .whitespaces).split(separator: ":").reduce(0) { $0 * 60 + (Double($1.replacingOccurrences(of: ",", with: ".")) ?? 0) } }

/// يقرأ ملف WebVTT للمصغرات، والرابط النسبي يُحل نسبةً لملف VTT (مع المفتاح).
public func parseVtt(_ text: String, base: String) -> [VttCue] {
    let lines = text.components(separatedBy: .newlines)
    let b = URL(string: base); let key = URLComponents(string: base)?.queryItems?.first { $0.name == "apikey" }?.value ?? ""
    var out: [VttCue] = []
    for i in 0..<max(0, lines.count - 1) where lines[i].contains("-->") {
        let t = lines[i].components(separatedBy: "-->")
        let ref = lines[i + 1].trimmingCharacters(in: .whitespaces)
        guard let hash = ref.range(of: "#xywh=") else { continue }
        let nums = ref[hash.upperBound...].split(separator: ",").compactMap { Int($0) }; guard nums.count == 4 else { continue }
        var u = String(ref[..<hash.lowerBound])
        if let abs = URL(string: u, relativeTo: b)?.absoluteURL, var c = URLComponents(url: abs, resolvingAgainstBaseURL: true) {
            c.queryItems = (c.queryItems ?? []).filter { $0.name != "apikey" }; if c.queryItems?.isEmpty == true { c.queryItems = nil }
            u = StashServer.withKey(c.string ?? u, key)
        }
        out.append(VttCue(start: vttTime(t[0]), end: vttTime(String(t[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "")), url: u, x: nums[0], y: nums[1], w: nums[2], h: nums[3]))
    }
    return out
}
public func cueAt(_ cues: [VttCue], _ sec: Double) -> VttCue? {
    if let c = cues.first(where: { sec >= $0.start && sec < $0.end }) { return c }
    return cues.last.flatMap { sec >= $0.end ? $0 : nil }
}

/// «الأعمال الناقصة»: أعمالها المنشورة في المصادر الرسمية التي لا تملكها في خادمك (القادمة لا تُعد).
public func missingWorks(_ works: [JSONObject], owned: [JSONObject], now: Date = Date()) -> (missing: [JSONObject], have: Int, total: Int) {
    let today = todayStr(now)
    let released = works.filter { let d = $0["d"]?.text ?? ""; return d.isEmpty || d <= today }
    let missing = released.filter { w in !owned.contains { sameWork(w, $0) } }.sorted { ($0["d"]?.text ?? "") > ($1["d"]?.text ?? "") }
    return (missing, released.count - missing.count, released.count)
}

// MARK: - مواقع التضمين الرسمية (اختيارية، بلا تنزيل)

public struct EmbedSource: Sendable { public let id, name, host: String }
public let embedSources = [EmbedSource(id: "ph", name: "Pornhub", host: "www.pornhub.com"), EmbedSource(id: "rt", name: "RedTube", host: "api.redtube.com"), EmbedSource(id: "ep", name: "Eporner", host: "www.eporner.com")]

/// هل الفيديو لها فعلًا؟ اسمها الكامل كلمةً كاملةً في العنوان أو قائمة الممثلات/الوسوم.
public func embedMatches(_ p: Performer, title: String, names: [String]) -> Bool {
    var want: Set<String> = [norm(p.name)]
    for a in p.aliases.components(separatedBy: ",") where norm(a).split(separator: " ").count >= 2 { want.insert(norm(a)) }
    want.remove("")
    if names.contains(where: { want.contains(norm($0)) }) { return true }
    let t = " " + norm(title).replacingOccurrences(of: #"[^\p{L}\p{N} ]"#, with: " ", options: .regularExpression) + " "
    return want.contains { $0.split(separator: " ").count >= 2 && t.contains(" \($0) ") }
}

func secs(_ v: JSONValue?) -> Int {
    if let n = v?.number { return Int(n) }
    return (v?.text ?? "").split(separator: ":").reduce(0) { $0 * 60 + (Int($1.trimmingCharacters(in: .whitespaces)) ?? 0) }
}

public func searchEmbeds(_ s: EmbedSource, _ p: Performer) async -> [WorkGroup] {
    if p.isMinor { return [] }   // بوابة +18 قبل أي طلب
    let q = p.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? p.name
    let url: String
    switch s.id {
    case "ph": url = "https://www.pornhub.com/webmasters/search?search=\(q)&ordering=mostviewed&thumbsize=large"
    case "rt": url = "https://api.redtube.com/?data=redtube.Videos.searchVideos&output=json&search=\(q)&ordering=mostviewed&thumbsize=big"
    default: url = "https://www.eporner.com/api/v2/video/search/?query=\(q)&per_page=30&page=1&thumbsize=big&order=most-popular&gay=0&lq=0&format=json"
    }
    guard let u = URL(string: url), let res = try? await Net.shared.send(s.name, URLRequest(url: u)), res.1 == 200, let j = try? JSONValue.parse(res.0) else { return [] }
    func group(_ id: String, _ title: String, _ thumb: String, _ embed: String, _ sec: Int) -> WorkGroup {
        var g = WorkGroup(key: "emb:\(s.id):\(id)"); g.t = title; g.p = thumb; g.tr = embed; g.du = Int((Double(sec) / 60).rounded()); g.who = [p]; return g
    }
    var out: [WorkGroup] = []
    for x in j["videos"]?.array ?? [] {
        let v = s.id == "rt" ? (x["video"] ?? x) : x
        switch s.id {
        case "ph":
            let id = v["video_id"]?.text ?? ""; if id.isEmpty { continue }
            let names = (v["pornstars"]?.array ?? []).map { $0["pornstar_name"]?.text ?? $0.text }
            if embedMatches(p, title: v["title"]?.text ?? "", names: names) { out.append(group(id, v["title"]?.text ?? "", (v["default_thumb"] ?? v["thumb"])?.text ?? "", "https://www.pornhub.com/embed/\(id)", secs(v["duration"]))) }
        case "rt":
            let id = v["video_id"]?.text ?? ""; if id.isEmpty { continue }
            let names = (v["pornstars"]?.array ?? []).map { $0["pornstar_name"]?.text ?? $0.text }
            if embedMatches(p, title: v["title"]?.text ?? "", names: names) { out.append(group(id, v["title"]?.text ?? "", (v["default_thumb"] ?? v["thumb"])?.text ?? "", "https://embed.redtube.com/?id=\(id)", secs(v["duration"]))) }
        default:
            let id = v["id"]?.text ?? ""; if id.isEmpty { continue }
            let names = (v["keywords"]?.text ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if embedMatches(p, title: v["title"]?.text ?? "", names: names) { out.append(group(id, v["title"]?.text ?? "", v["default_thumb"]?["src"]?.text ?? "", v["embed"]?.string ?? "https://www.eporner.com/embed/\(id)/", secs(v["length_sec"]))) }
        }
    }
    return out
}
