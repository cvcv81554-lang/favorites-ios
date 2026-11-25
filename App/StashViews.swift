import SwiftUI
import FavCore

/// «الشبكة والمقاطع»: حالة المصادر، خادم Stash، مواقع التضمين، الجودة، المقاطع المحفوظة والتحميل المسبق، وحالة الخوادم.
struct NetworkView: View {
    @Environment(AppModel.self) private var model
    @State private var cfg = ReelsCfg(nil)
    @State private var url = ""
    @State private var key = ""
    @State private var stashMsg = ""
    @State private var srcStatus: [String: String] = [:]
    @State private var cache = (0, Int64(0))
    @State private var embedMsg = ""

    var body: some View {
        List {
            Section("المصادر الرسمية") {
                status("StashDB", srcStatus["s"]); status("ThePornDB", srcStatus["t"])
                Button("فحص الاتصال") { Task { await check() } }
                Text("ThePornDB يعمل عبر شبكات Apple (HTTP/3) دون VPN على شبكتك. إن قُطع، يكمل التطبيق بالمصدر الآخر.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            Section("خادم Stash الخاص بك") {
                TextField("العنوان، مثل 192.168.1.10:9999", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key (إن كان للخادم كلمة مرور)", text: $key)
                Button("حفظ واختبار") { Task { await testStash() } }
                Toggle("إظهار مقاطعه في «مقاطع»", isOn: Binding(get: { cfg.server }, set: { cfg.server = $0; saveCfg() }))
                if !stashMsg.isEmpty { Text(stashMsg).font(Theme.font(12.5)).foregroundStyle(stashMsg.hasPrefix("متصل") ? Theme.ok : Theme.gold) }
                Text("ثبّت Stash على حاسوبك وأضف مجلد فيديوهاتك ← اربط ممثلاتك بـ StashDB داخله ← انسخ العنوان والـ API Key من Settings ← Security. يعمل والجوال على نفس شبكة المنزل.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            Section("مواقع التضمين الرسمية (بلا تنزيل)") {
                ForEach(embedSources, id: \.id) { s in
                    Toggle(s.name, isOn: Binding(get: { cfg.emb.contains(s.id) }, set: { on in if on { cfg.emb.append(s.id) } else { cfg.emb.removeAll { $0 == s.id } }; saveCfg() }))
                }
                Button("جلب فيديوهات مفضلاتك منها") { Task { await fetchEmbeds() } }
                if !embedMsg.isEmpty { Text(embedMsg).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                Text("مطابقة بالاسم الكامل فقط، ومشغّل التضمين الرسمي لكل موقع. محجوبة على بعض الشبكات (تعمل مع VPN تشغّله أنت).").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            Section("الجودة والتشغيل") {
                Toggle("إعلانات حقيقية فقط (تخطّي المعاينات الصامتة وما دون 480p)", isOn: Binding(get: { cfg.hqOnly }, set: { cfg.hqOnly = $0; saveCfg() }))
                Toggle("الصوت مفعّل افتراضيًا", isOn: Binding(get: { cfg.sound }, set: { cfg.sound = $0; saveCfg() }))
                Toggle("تمرير تلقائي", isOn: Binding(get: { cfg.auto }, set: { cfg.auto = $0; saveCfg() }))
            }
            Section("المقاطع المحفوظة والتحميل المسبق") {
                HStack { Text("محفوظة على جهازك"); Spacer(); Text("\(cache.0) · \(ByteCountFormatter.string(fromByteCount: cache.1, countStyle: .file))").foregroundStyle(Theme.muted) }
                Toggle("تحميل مسبق على Wi-Fi", isOn: Binding(get: { cfg.prefetch }, set: { cfg.prefetch = $0; saveCfg() }))
                Stepper("عدد المقاطع: \(cfg.count)", value: Binding(get: { cfg.count }, set: { cfg.count = $0; saveCfg() }), in: 10...300, step: 10)
                Stepper("الحد: \(cfg.gb) GB", value: Binding(get: { cfg.gb }, set: { cfg.gb = $0; saveCfg() }), in: 1...20)
                Toggle("تحميل ليلي أثناء الشحن (iOS يقرر التوقيت)", isOn: Binding(get: { cfg.night }, set: { cfg.night = $0; saveCfg() }))
                Button("تفريغ المقاطع المحفوظة", role: .destructive) { ClipCache.prune(limitGB: 0); cache = ClipCache.stats() }
            }
            Section("الخوادم على شبكتك") {
                let hosts = (model.store.kv("reel_hosts")?.object ?? [:]).sorted { $0.key < $1.key }
                if hosts.isEmpty { Text("تُسجَّل هنا الخوادم عند التشغيل.").foregroundStyle(Theme.muted) }
                ForEach(hosts, id: \.key) { e in HStack { Text(e.key).font(Theme.font(12.5)); Spacer(); Text(e.value["ok"]?.bool == false ? "محجوب" : "يعمل").foregroundStyle(e.value["ok"]?.bool == false ? Theme.rose : Theme.ok).font(Theme.font(12)) } }
                if !hosts.isEmpty { Button("إعادة فحص الكل (يُعاد تشغيلها)") { try? model.store.setKV("reel_hosts", .object([:])) } }
            }
        }
        .navigationTitle("الشبكة والمقاطع")
        .onAppear { cfg = ReelsCfg(model.store.kv("reels_cfg")); url = Keychain.get(APIKeyName.stashURL.rawValue); key = Keychain.get(APIKeyName.stashKey.rawValue); cache = ClipCache.stats() }
    }
    func status(_ n: String, _ s: String?) -> some View { HStack { Text(n); Spacer(); Text(s ?? "—").font(Theme.font(12)).foregroundStyle(s == "يعمل ✓" ? Theme.ok : Theme.muted) } }
    func saveCfg() { try? model.store.setKV("reels_cfg", cfg.json) }

    @MainActor func check() async {
        srcStatus = ["s": "…", "t": "…"]
        do { try await StashDB.test(key: Keychain.get(APIKeyName.stash.rawValue)); srcStatus["s"] = "يعمل ✓" } catch { srcStatus["s"] = error.localizedDescription }
        do { try await TPDB.test(key: Keychain.get(APIKeyName.tpdb.rawValue)); srcStatus["t"] = "يعمل ✓" } catch { srcStatus["t"] = error.localizedDescription }
    }
    @MainActor func testStash() async {
        stashMsg = "اختبار الاتصال…"
        do {
            let v = try await StashServer.test(url: url, key: key)
            Keychain.set(APIKeyName.stashURL.rawValue, StashServer.normalize(url)); Keychain.set(APIKeyName.stashKey.rawValue, key)
            try? model.store.setKV("stash_local_map", .object([:]))
            stashMsg = "متصل ✓ — Stash \(v). افتح «مقاطع» أو «مكتبة Stash»."
        } catch { stashMsg = error.localizedDescription }
    }
    /// جلب فيديوهات المفضلات من مواقع التضمين المفعّلة (بوابة +18 قبل أي طلب) إلى ذاكرة محلية.
    @MainActor func fetchEmbeds() async {
        var cache = model.store.kv("embed_cache")?.object ?? [:]
        var n = 0
        for s in embedSources where cfg.emb.contains(s.id) {
            for p in model.performers.filter({ $0.fav && !$0.isMinor }).prefix(25) {
                embedMsg = "\(s.name): \(p.name)…"
                let l = await searchEmbeds(s, p)
                let mine = (cache[p.id]?.array ?? []).filter { !($0["k"]?.text ?? "").hasPrefix("emb:\(s.id):") }
                cache[p.id] = .array(mine + l.prefix(15).map { g in .object(["k": .string(g.key), "t": .string(g.t), "p": .string(g.p), "tr": .string(g.tr), "du": .int(Int64(g.du))]) })
                n += l.count
            }
        }
        try? model.store.setKV("embed_cache", .object(cache))
        embedMsg = n == 0 ? "لا نتائج — المواقع قد تكون محجوبة على شبكتك" : "وُجد \(n) فيديو"
    }
}

/// «مكتبة Stash»: كل فيديوهات خادمك — بحث، ترتيب، «ممثلاتي فقط»، ممثلات الخادم، و«تابع المشاهدة».
struct StashLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var q = ""
    @State private var sort = "random"
    @State private var mine = false
    @State private var performer: (String, String)?
    @State private var items: [(FavCore.WorkGroup, StashExtra)] = []
    @State private var count = 0
    @State private var page = 0
    @State private var perfs: [StashServer.ServerPerformer] = []
    @State private var resume: [(FavCore.WorkGroup, StashExtra)] = []
    @State private var msg = ""
    @State private var playing: PlayItem?
    @State private var seed = Int.random(in: 1...9_999_999)

    struct PlayItem: Identifiable { let g: FavCore.WorkGroup; let ex: StashExtra; var id: String { g.key } }
    let sorts = [("random", "عشوائي"), ("date", "الأحدث"), ("created_at", "أُضيف حديثًا"), ("play_count", "الأكثر مشاهدة"), ("last_played_at", "آخر ما شاهدته"), ("title", "العنوان")]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("الفيديوهات (\(count))").tag(0); Text("الممثلات").tag(1); Text("تابع المشاهدة (\(resume.count))").tag(2) }.pickerStyle(.segmented).padding()
            if !StashServer.configured { EmptyStateView(icon: "server.rack", title: "خادم Stash غير مضبوط", message: "أضف عنوانه من «الشبكة والمقاطع».") }
            else if tab == 0 { scenes } else if tab == 1 { performersList } else { resumeList }
        }
        .background(Theme.bg).navigationTitle("مكتبة Stash")
        .searchable(text: $q, prompt: "ابحث في خادمك…").onSubmit(of: .search) { Task { await reload() } }
        .task { await reload(); await loadResume(); perfs = (try? await StashServer.performers().0) ?? [] }
        .fullScreenCover(item: $playing) { it in FullVideoView(url: it.g.tr, title: it.g.t, stash: it.ex) }
    }

    var localMap: [String: Performer] {
        let map = (model.store.kv("stash_local_map")?.object ?? [:]).compactMapValues { $0.string }
        return Dictionary(model.performers.compactMap { p in map[p.id].flatMap { $0.isEmpty ? nil : ($0, p) } }, uniquingKeysWith: { a, _ in a })
    }

    var scenes: some View {
        VStack(spacing: 0) {
            ChipRow {
                if let p = performer { Chip(text: p.1, on: true, icon: "xmark") { performer = nil; Task { await reload() } } }
                else { Chip(text: "ممثلاتي فقط", on: mine) { mine.toggle(); Task { await reload() } } }
                ForEach(sorts, id: \.0) { s in Chip(text: s.1, on: sort == s.0) { sort = s.0; seed += 1; Task { await reload() } } }
            }
            if !msg.isEmpty { Text(msg).font(Theme.font(12.5)).foregroundStyle(Theme.gold).padding(6) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(items, id: \.0.key) { it in
                        Button { playing = PlayItem(g: it.0, ex: it.1) } label: { sceneCard(it.0, it.1) }.buttonStyle(.plain)
                            .onAppear { if it.0.key == items.last?.0.key { Task { await more() } } }
                    }
                }.padding(10)
            }
        }
    }
    func sceneCard(_ g: FavCore.WorkGroup, _ ex: StashExtra) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                PhotoView(ref: g.p).aspectRatio(16 / 9, contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 10))
                Text([g.du > 0 ? "\(g.du) د" : "", ex.height >= 2000 ? "4K" : ex.height >= 1000 ? "HD" : "", ex.direct ? "" : "HLS", ex.plays > 0 ? "👁 \(ex.plays)" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.font(10.5)).padding(4).background(.black.opacity(0.6), in: Capsule()).padding(4)
            }
            Text(g.t).font(Theme.font(12.5, .semibold)).lineLimit(1)
            Text(g.who.prefix(2).map(\.name).joined(separator: "، ")).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
            if ex.resume > 10 && g.du > 0 { ProgressView(value: min(1, ex.resume / Double(g.du * 60))).tint(Theme.gold) }
        }
    }
    var performersList: some View {
        List(perfs) { p in
            Button { performer = (p.id, p.name); tab = 0; Task { await reload() } } label: {
                HStack { PhotoView(ref: p.image).frame(width: 44, height: 44).clipShape(Circle()); VStack(alignment: .leading) { Text(p.name); Text("\(p.scenes) فيديو\(localMap[p.id] != nil ? " · في مكتبتك" : "")").font(Theme.font(12)).foregroundStyle(Theme.muted) } }
            }
        }.scrollContentBackground(.hidden)
    }
    var resumeList: some View {
        List(resume, id: \.0.key) { it in
            Button { playing = PlayItem(g: it.0, ex: it.1) } label: {
                HStack { PhotoView(ref: it.0.p).frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading) { Text(it.0.t).lineLimit(1); if it.0.du > 0 { ProgressView(value: min(1, it.1.resume / Double(it.0.du * 60))).tint(Theme.gold) } } }
            }
        }.scrollContentBackground(.hidden).overlay { if resume.isEmpty { Text("لا فيديوهات متوقفة في منتصفها").foregroundStyle(Theme.muted) } }
    }

    @MainActor func reload() async { page = 0; items = []; count = 0; await more() }
    @MainActor func more() async {
        if page > 0 && items.count >= count { return }
        do {
            let r = try await StashServer.browse(query: q, sort: sort == "random" ? "random_\(seed)" : sort, desc: sort != "title", page: page + 1,
                                                  performer: performer?.0, mine: mine && performer == nil ? Array(localMap.keys) : nil, byLocal: localMap)
            page += 1; items += r.0; count = r.1; msg = ""
        } catch { msg = error.localizedDescription }
    }
    @MainActor func loadResume() async { resume = (try? await StashServer.browse(sort: "last_played_at", perPage: 60, mode: "resume", byLocal: localMap).0) ?? [] }
}

/// «الأعمال الناقصة»: أعمال ممثلاتك في المصادر الرسمية التي لا تملكها في خادمك — معلومات فقط.
struct MissingView: View {
    @Environment(AppModel.self) private var model
    let performerId: String?
    struct RowData: Identifiable { let p: Performer; let missing: [JSONObject]; let have: Int; let total: Int; let linked: Bool; var id: String { p.id } }
    @State private var rows: [RowData]?
    @State private var msg = ""
    var body: some View {
        List {
            if let rows {
                if performerId == nil { Text("ينقصك \(rows.reduce(0) { $0 + ($1.linked ? $1.missing.count : 0) }) عملًا لـ\(rows.count) ممثلة").font(Theme.font(14, .semibold)) }
                Text("مقارنة أعمالها في StashDB وThePornDB بما في خادمك (بالمعرّف، وإلا العنوان والاستوديو والتاريخ). القادمة لا تُحسب.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
                ForEach(rows) { r in
                    DisclosureGroup {
                        ForEach(r.missing.indices, id: \.self) { i in
                            let w = r.missing[i]
                            HStack { PhotoView(ref: w["p"]?.text ?? "").frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading) { Text(w["t"]?.text ?? "").lineLimit(1); Text([w["s"]?.text ?? "", w["d"]?.text ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(11)).foregroundStyle(Theme.muted) } }
                        }
                    } label: {
                        HStack { Avatar(p: r.p, size: 38); VStack(alignment: .leading) { Text(r.p.name)
                            Text(r.linked ? "لديك \(r.have) من \(r.total)\(r.missing.isEmpty ? " ✓" : " · ينقص \(r.missing.count)")" : "غير موجودة في خادمك").font(Theme.font(12)).foregroundStyle(Theme.muted) } }
                    }
                }
            } else { HStack { ProgressView(); Text(msg) } }
        }
        .navigationTitle("الأعمال الناقصة")
        .task { await load() }
    }
    @MainActor func load() async {
        guard StashServer.configured else { rows = []; msg = "اضبط خادم Stash أولًا"; return }
        var map = (model.store.kv("stash_local_map")?.object ?? [:]).compactMapValues { $0.string }
        let want = model.performers.filter { !$0.isMinor && !$0.works.isEmpty && (performerId == nil ? ($0.fav || $0.rating >= 4) : $0.id == performerId) }
        for p in want where map[p.id] == nil { msg = "ربط \(p.name)…"; map[p.id] = (try? await StashServer.localPerformer(p)) ?? "" }
        try? model.store.setKV("stash_local_map", .object(map.mapValues { .string($0) }))
        let owned = (try? await StashServer.owned(want.compactMap { map[$0.id].flatMap { $0.isEmpty ? nil : $0 } })) ?? [:]
        rows = want.map { p in
            let l = map[p.id] ?? ""
            let m = missingWorks(p.works, owned: l.isEmpty ? [] : owned[l] ?? [])
            return RowData(p: p, missing: m.missing, have: m.have, total: m.total, linked: !l.isEmpty)
        }.sorted { $0.missing.count > $1.missing.count }
    }
}
