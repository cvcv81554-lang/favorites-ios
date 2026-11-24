import SwiftUI
import Security
import FavCore

@main
struct FavoritesApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        Theme.registerFonts()
        Background.register()
    }

    var body: some Scene {
        WindowGroup {
            LockGate { RootView() }
                .environment(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .font(Theme.font(16))
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task { await model.startup() }
        }
        .onChange(of: phase) { _, p in
            model.privacy.onPhase(p)
            if p == .background { Background.schedule(); WidgetBridge.publish(model) }
        }
    }
}

/// مخزن مفاتيح API الآمن (Keychain) — لا تدخل النسخ الاحتياطية ولا المستودع.
enum Keychain {
    static let service = "com.favlib.favoritesnative.keys"
    static func get(_ k: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: k, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
    static func set(_ k: String, _ v: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: k]
        SecItemDelete(q as CFDictionary)
        if v.isEmpty { return }
        var a = q; a[kSecValueData as String] = Data(v.utf8); a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
}

/// حالة التطبيق: المخزن المحلي والسجلات ومحركات الذوق والتعلم. كل شيء على الجهاز.
@Observable
final class AppModel {
    let store: Store
    private(set) var performers: [Performer] = []
    private(set) var works: [FavCore.WorkGroup] = []
    private(set) var lists: [JSONObject] = []
    private(set) var wlists: [JSONObject] = []
    /// خصائص الممثلات الموثّقة (من المصادر، بصيغة StashDB) — مفتاحها معرّف الممثلة في مكتبتك.
    private(set) var feats: [String: Features] = [:]
    var reelSig = ReelSignals()
    var toast: String?
    var busy: String?
    let privacy = Privacy()
    var revision = 0

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Favorites", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var dir = base
        var v = URLResourceValues(); v.isExcludedFromBackup = true   // بياناتك تبقى على جهازك: خارج نسخ iCloud
        try? dir.setResourceValues(v)
        do { store = try Store(directory: base) } catch { fatalError("تعذّر فتح قاعدة البيانات: \(error)") }
        Net.shared.keys = { Keychain.get($0.rawValue) }
        reload()
        reelSig = decayReels(ReelSignals(json: store.kv("reels_sig")), today: reelDay())
    }

    @MainActor func startup() async {
        privacy.load(store)
        WidgetBridge.publish(self)
    }

    func reload() {
        performers = store.loadAll().filter { !$0.isMinor }   // بوابة +18 عند العرض أيضًا
        works = groupWorks(performers)
        lists = (store.kv("lists")?.array ?? []).compactMap { $0.object }
        wlists = (store.kv("wlists")?.array ?? []).compactMap { $0.object }
        let cache = store.kv("attr_cache")?.object ?? [:]
        var f: [String: Features] = [:]
        for p in performers { if let d = cache[p.id]?["d"]?.object { f[p.id] = featuresOf(d) } }
        feats = f
        revision += 1
    }

    // MARK: الحفظ (نقطة واحدة — ترفض القاصر دائمًا)
    @discardableResult func save(_ ps: [Performer]) -> Bool {
        do { let ok = try store.save(ps); reload(); if ok.count < ps.count { toast = "رُفض سجل: العمر أقل من 18 أو التاريخ غير صالح" }; return ok.count == ps.count }
        catch { toast = error.localizedDescription; return false }
    }
    @discardableResult func save(_ p: Performer) -> Bool { save([p]) }
    func delete(_ id: String) { try? store.delete(id); reload() }

    func performer(_ id: String) -> Performer? { performers.first { $0.id == id } }
    func listName(_ id: String) -> String { lists.first { $0["id"]?.string == id }?["name"]?.text ?? id }
    func setLists(_ l: [JSONObject]) { try? store.setKV("lists", .array(l.map { .object($0) })); reload() }
    func setWLists(_ l: [JSONObject]) { try? store.setKV("wlists", .array(l.map { .object($0) })); reload() }

    // MARK: إعدادات بسيطة (kv)
    func pref(_ k: String) -> JSONValue? { store.kv("pref_" + k) }
    func setPref(_ k: String, _ v: JSONValue) { try? store.setKV("pref_" + k, v) }

    // MARK: إشارات المقاطع
    func saveReelSig() { try? store.setKV("reels_sig", reelSig.json) }

    // MARK: تحديث من المصدرين
    /// يجمع كل سجلاتها بكل أسمائها من StashDB وThePornDB: معلومات، أعمال، صور — بلا تكرار، وبوابة +18 أولًا.
    @MainActor func refreshFromSources(_ p: Performer) async -> String {
        busy = "جمع سجلاتها من المصدرين…"; defer { busy = nil }
        var sIds = p.stashIds, tIds = p.pdbIds
        if !p.birth.isEmpty || !sIds.isEmpty || !tIds.isEmpty {
            let c = Candidate(source: sIds.isEmpty ? "tpdb" : "stash", id: sIds.first ?? tIds.first ?? "", name: p.name, aliases: p.aliases, birth: p.birth, country: p.country)
            let all = await findAllRecords(c) { m in Task { @MainActor in self.busy = m } }
            for x in all.stash where !sIds.contains(x.id) { sIds.append(x.id) }
            for x in all.tpdb where !tIds.contains(x.id) { tIds.append(x.id) }
        }
        if sIds.isEmpty && tIds.isEmpty { return "اربطها بمصدر أولًا (ابحث عنها من «ربط بمصدر»)" }
        busy = "جلب المعلومات والأعمال والصور…"
        let d = await fetchBoth(stashIds: sIds, pdbIds: tIds)
        if d.minor { return "رُفضت: أحد المصادر يقول إن عمرها أقل من 18 أو تاريخها غير صالح" }
        guard let cur = performer(p.id) else { return "" }
        var ch: JSONObject = [:]
        for (k, v) in d.info where (cur.raw[k]?.text ?? "").isEmpty { ch[k] = v }
        if let al = d.info["aliases"]?.text {
            var set = cur.aliases.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for a in al.components(separatedBy: ", ") where !set.contains(where: { norm($0) == norm(a) }) && norm(a) != norm(cur.name) { set.append(a) }
            ch["aliases"] = .string(set.joined(separator: ", "))
        }
        let merged = mergeWorks(cur.works, d.works)
        ch["works"] = .array(merged.list.map { .object($0) })
        ch["stashIds"] = .array(d.stashIds.map { .string($0) }); ch["pdbIds"] = .array(d.pdbIds.map { .string($0) })
        if cur.stashId.isEmpty, let s = d.stashIds.first { ch["stashId"] = .string(s) }
        if cur.pdbId.isEmpty, let t = d.pdbIds.first { ch["pdbId"] = .string(t) }
        var photos = cur.photos
        for u in d.images where photos.count < 30 && !photos.contains(u) { photos.append(u) }
        ch["photos"] = .array(photos.map { .string($0) })
        if cur.thumb.isEmpty, let f = photos.first { ch["thumb"] = .string(f) }
        ch["worksAt"] = .int(Int64(Date().timeIntervalSince1970 * 1000))
        save(cur.with(ch))
        if !d.attrs.isEmpty { cacheAttrs(p.id, d.attrs) }
        let errs = d.errors.isEmpty ? "" : " — " + d.errors.prefix(2).joined(separator: "؛ ")
        return "تم من \(d.sources.joined(separator: " + ")): \(merged.added) عمل جديد، \(photos.count - cur.photos.count) صورة جديدة\(errs)"
    }

    func cacheAttrs(_ id: String, _ d: JSONObject) {
        var cache = store.kv("attr_cache")?.object ?? [:]
        cache[id] = ["t": .double(Date().timeIntervalSince1970 * 1000), "d": .object(d)]
        try? store.setKV("attr_cache", .object(cache)); reload()
    }

    /// جمع البيانات الوصفية للمفضلات المرتبطة (للتحليل) — مع ذاكرة 14 يومًا.
    @MainActor func refreshAttributes(limit: Int = 40) async -> Int {
        var cache = store.kv("attr_cache")?.object ?? [:]
        let now = Date().timeIntervalSince1970 * 1000
        var n = 0
        for p in performers where (p.fav || p.rating > 0) && (!p.stashIds.isEmpty || !p.pdbIds.isEmpty) {
            if let t = cache[p.id]?["t"]?.number, now - t < 14 * 86_400_000 { continue }
            if n >= limit { break }
            busy = "بيانات \(p.name)…"
            var d: JSONObject? = nil
            if let s = p.stashIds.first { d = try? await StashDB.performer(s) }
            if let t = p.pdbIds.first, let tp = try? await TPDB.performer(t) { d = d.map { fillFrom($0, tpdbAsStash(tp)) } ?? tpdbAsStash(tp) }
            if let d { cache[p.id] = ["t": .double(now), "d": .object(d)]; n += 1 }
        }
        busy = nil
        try? store.setKV("attr_cache", .object(cache)); reload()
        return n
    }
}
