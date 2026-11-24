import SwiftUI
import FavCore

/// حالة الاكتشاف: مرشحات من StashDB (+ من عملن مع مفضلاتك في ThePornDB)، خصائصها، تعلّمك، ومن أخفيت/حفظت.
@Observable
final class DiscoverState {
    var pool: [RecCand] = []
    var candFeats: [String: Features] = [:]
    var feedback: [String: Double] = [:]
    var hidden = Set<String>(), saved = Set<String>()
    var at: Double = 0
    var msg = ""
    var loading = false

    func load(_ s: Store) {
        pool = (s.kv("rec_pool")?.array ?? []).compactMap { RecCand(json: $0) }
        at = s.kv("rec_pool_at")?.number ?? 0
        candFeats = (s.kv("cand_attrs")?.object ?? [:]).compactMapValues { $0.object.map { featuresOf($0) } }
        feedback = (s.kv("rec_fb")?.object ?? [:]).compactMapValues { $0.number }
        hidden = Set((s.kv("rec_hidden")?.array ?? []).compactMap { $0.string }); saved = Set((s.kv("rec_saved")?.array ?? []).compactMap { $0.string })
    }
    func persist(_ s: Store) {
        try? s.setKV("rec_fb", .object(feedback.mapValues { .double($0) }))
        try? s.setKV("rec_hidden", .array(hidden.sorted().map { .string($0) })); try? s.setKV("rec_saved", .array(saved.sorted().map { .string($0) }))
    }

    /// تجديد المرشحات (من المصادر الرسمية فقط) وجلب خصائص الأفضل (حتى 30) — بوابة +18 قبل أي صورة.
    @MainActor func refresh(_ m: AppModel) async {
        loading = true; defer { loading = false }
        let seeds = m.performers.filter { $0.fav || $0.rating >= 4 }.flatMap { p in p.stashIds.prefix(1).map { ($0, seedWeight(p)) } }.sorted { $0.1 > $1.1 }.prefix(10)
        var cc: [String: Int] = [:]; for p in m.performers where !p.country.isEmpty { cc[p.country.uppercased(), default: 0] += 1 }
        do {
            var l = try await StashDB.recPool(seeds: Array(seeds), countries: cc.sorted { $0.value > $1.value }.map(\.key)) { x in Task { @MainActor in self.msg = x } }
            // ThePornDB: من عملن مع مفضلاتك هناك (يُدمج بالاسم مع StashDB)
            for p in m.performers.filter({ $0.fav }).prefix(5) {
                guard let t = p.pdbIds.first, let co = try? await TPDB.coStars(t) else { continue }
                for (id, v) in co where !l.contains(where: { norm($0.name) == norm(v.0) }) {
                    var c = RecCand(id: "tp:\(id)", name: v.0); c.withSeeds.insert(p.stashIds.first ?? p.id); c.lanes.insert("tpdb"); l.append(c)
                }
            }
            pool = l.filter(\.adult); at = Date().timeIntervalSince1970
            try? m.store.setKV("rec_pool", .array(pool.map(\.json))); try? m.store.setKV("rec_pool_at", .double(at))
            msg = "جاري جمع خصائص المرشحات…"
            let ranked = rankRecs(pool, m.performers, hidden: hidden).prefix(30)
            var cache = m.store.kv("cand_attrs")?.object ?? [:]
            for c in ranked where cache[c.id] == nil && !c.id.hasPrefix("tp:") {
                if let d = try? await StashDB.performer(c.id) { cache[c.id] = .object(d) }
            }
            try? m.store.setKV("cand_attrs", .object(cache))
            candFeats = cache.compactMapValues { $0.object.map { featuresOf($0) } }
            msg = ""
        } catch { msg = error.localizedDescription }
    }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var st = DiscoverState()
    @State private var ignore = Set<String>()

    var body: some View {
        let favs = model.performers.filter { $0.fav || $0.rating >= 4 }
        let fs = favs.compactMap { model.feats[$0.id] }
        let weights = favs.filter { model.feats[$0.id] != nil }.map { tasteWeight(fav: $0.fav, rating: $0.rating) }
        let profile = buildProfile(fs, total: favs.count, weights: weights, ignore: ignore)
        let ranked = rankRecs(st.pool, model.performers, hidden: st.hidden)
        let scored = scoreCandidates(ranked, feats: st.candFeats, profile: profile, feedback: st.feedback, fieldWeights: userFieldWeights((model.store.kv("intel_answers")?.object ?? [:]).compactMapValues { $0.string }))
        let pf = portfolio(scored)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileCard(profile, favs: favs.count)
                if st.pool.isEmpty {
                    Card {
                        Text("ابدأ الاكتشاف").font(Theme.font(16, .bold))
                        Text("يجمع مرشحات من StashDB (من عملن مع مفضلاتك، الوجوه الجديدة، ومن بلدانك) ومن ThePornDB، ويرتبها بذوقك.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        Button { Task { await st.refresh(model) } } label: { Label("جمع المرشحات", systemImage: "sparkles") }.buttonStyle(.borderedProminent)
                    }
                }
                lane("اختيار اليوم", dailyPick(ranked).map { Scored(c: $0, score: $0.score, confidence: 0.5, why: $0.reasons, diff: []) })
                lane("ثقة عالية", pf.highConfidence)
                lane("الأقرب لذوقك (آمن)", pf.safe)
                lane("مفاجأة ذات معنى", pf.unexpected)
                lane("أرض جديدة — خارج المألوف", pf.newTerritory)
                lane("وجوه جديدة", scored.filter { $0.c.lanes.contains("debut") })
                lane("18–21 (تاريخ كامل موثّق فقط)", scored.filter { $0.c.young18to21 })
                lane("من بلدك المفضل", scored.filter { $0.c.lanes.contains("country") })
                lane("عملن مع مفضلاتك في ThePornDB", scored.filter { $0.c.lanes.contains("tpdb") })
                if !st.saved.isEmpty { lane("محفوظة لاحقًا", scored.filter { st.saved.contains($0.id) }) }
                if !st.msg.isEmpty { Text(st.msg).font(Theme.font(12.5)).foregroundStyle(Theme.muted).padding(.horizontal, 16) }
            }.padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("اكتشف")
        .toolbar {
            NavigationLink { SimulatorView(st: st, profile: profile) } label: { Image(systemName: "slider.horizontal.3") }
            NavigationLink { TasteMapView() } label: { Image(systemName: "map") }
            Button { Task { await st.refresh(model) } } label: { st.loading ? AnyView(ProgressView()) : AnyView(Image(systemName: "arrow.clockwise")) }
        }
        .onAppear { if st.pool.isEmpty { st.load(model.store) }; ignore = Set((model.store.kv("taste_ignore")?.array ?? []).compactMap { $0.string }) }
        .environment(st)
    }

    func profileCard(_ p: TasteProfile, favs: Int) -> some View {
        Card {
            HStack { Text("ملف ذوقك").font(Theme.font(17, .bold)); Spacer(); Text("\(p.analyzed) من \(favs) مفضلة").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            if !p.sufficient {
                Text("يحتاج 3 مفضلات مرتبطة بمصدر لها بيانات وصفية.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            } else {
                ForEach(p.strongCats.prefix(6), id: \.field) { c in BarRow(label: "\(fieldNames[c.field] ?? c.field): \(attrLabel(c.field, c.top.key))", value: c.share, max: 1, text: "\(Int((c.share * 100).rounded()))٪") }
                ForEach(describeProfile(p).filter { !$0.contains("٪ من") }, id: \.self) { Text("• \($0)").font(Theme.font(12.5)) }
            }
            HStack {
                Button { Task { let n = await model.refreshAttributes(); model.toast = "حُدّثت بيانات \(n) ممثلة" } } label: { Label("تحديث بيانات مفضلاتك", systemImage: "arrow.down.circle") }.font(Theme.font(13))
                Spacer()
                NavigationLink { TasteSettingsView() } label: { Image(systemName: "gearshape") }
            }
            Text("من البيانات الموثّقة في StashDB وThePornDB فقط — لا شيء يُستنتج من الصور.").font(Theme.font(11)).foregroundStyle(Theme.muted)
        }.padding(.horizontal, 16)
    }

    @ViewBuilder func lane(_ title: String, _ l: [Scored]) -> some View {
        if !l.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Theme.font(17, .bold)).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) { ForEach(l.prefix(12)) { s in NavigationLink(value: Route.candidate(s.c)) { CandCard(s: s) }.buttonStyle(.plain) } }.padding(.horizontal, 16)
                }
            }
        }
    }
}

struct CandCard: View {
    let s: Scored
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group { if s.c.image.isEmpty { Theme.surface } else { PhotoView(ref: s.c.image) } }.frame(width: 140, height: 186).clipShape(RoundedRectangle(cornerRadius: 14))
            Text(s.c.name).font(Theme.font(13.5, .semibold)).lineLimit(1)
            Text("\(Int((s.score * 100).rounded()))٪ · \(s.c.country)").font(Theme.font(11)).foregroundStyle(Theme.gold)
            if let w = s.why.first { Text(w).font(Theme.font(10.5)).foregroundStyle(Theme.muted).lineLimit(2) }
        }.frame(width: 140)
    }
}

/// صفحة مرشحة: معلوماتها، أسباب الاقتراح، الاختلافات، تقييمك المتوقع، وإضافة/حفظ/ليست ذوقي.
struct CandidateScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let c: RecCand
    @State private var st = DiscoverState()
    @State private var busy = false

    var body: some View {
        let f = st.candFeats[c.id] ?? [:]
        let pred = f.isEmpty ? nil : predictRating(f, samples: samples(model.performers, model.feats))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Group { if c.image.isEmpty { Theme.surface } else { PhotoView(ref: c.image) } }.frame(height: 420).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 22))
                Text(c.name).font(Theme.font(26, .bold))
                Text([c.age.map { "\($0) سنة" } ?? "", c.country, c.careerStart.map { "منذ \($0)" } ?? "", c.scenes.map { "\($0) مشهد" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(Theme.muted)
                Text(c.id.hasPrefix("tp:") ? "المصدر: ThePornDB" : "المصدر: StashDB").font(Theme.font(12)).foregroundStyle(Theme.muted)
                if !c.reasons.isEmpty { Card { Text("لماذا اقترحناها").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold); ForEach(c.reasons, id: \.self) { Text("• \($0)").font(Theme.font(13)) } } }
                if let pred {
                    Card {
                        HStack { Text("تقييمك المتوقع").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold); Spacer(); ConfidenceBadge(value: pred.confidence) }
                        HStack { Stars(value: pred.rating, size: 14); Text(String(format: "%.1f", pred.rating)).font(Theme.font(15, .bold)) }
                        ForEach(pred.reasons, id: \.self) { Text("• \($0)").font(Theme.font(12.5)) }
                        if !pred.missing.isEmpty { Text("بيانات ناقصة: \(pred.missing.joined(separator: "، "))").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                    }
                }
                HStack(spacing: 10) {
                    Button { Task { await add(f) } } label: { Label("إضافة لمكتبتي", systemImage: "plus.circle.fill") }.buttonStyle(.borderedProminent).disabled(busy || !c.adult)
                    Button { st.saved.insert(c.id); st.persist(model.store); model.toast = "حُفظت لاحقًا" } label: { Label("لاحقًا", systemImage: "bookmark") }.buttonStyle(.bordered)
                    Button(role: .destructive) { st.hidden.insert(c.id); st.feedback = learn(st.feedback, f, -0.3); st.persist(model.store); dismiss() } label: { Text("ليست ذوقي") }.buttonStyle(.bordered)
                }
            }.padding(16)
        }
        .background(Theme.bg).navigationTitle(c.name).navigationBarTitleDisplayMode(.inline)
        .onAppear { st.load(model.store) }
    }

    @MainActor func add(_ f: Features) async {
        guard c.adult else { return }
        if model.performers.contains(where: { norm($0.name) == norm(c.name) }) { model.toast = "موجودة في مكتبتك"; return }
        busy = true
        let id = "p-" + UUID().uuidString.lowercased()
        var r: JSONObject = ["id": .string(id), "name": .string(c.name), "birth": .string(c.birth), "country": .string(c.country), "fav": true,
                             "source": .string("\(c.id.hasPrefix("tp:") ? "ThePornDB" : "StashDB") (اقتراح ذكي)"), "added": .double(Date().timeIntervalSince1970 * 1000),
                             "notes": .string("تمت الإضافة بناءً على اقتراح ذكي (\(c.reasons.first ?? ""))")]
        if c.id.hasPrefix("tp:") { r["pdbId"] = .string(String(c.id.dropFirst(3))) } else { r["stashId"] = .string(c.id) }
        if !c.image.isEmpty { r["photos"] = [.string(c.image)]; r["thumb"] = .string(c.image) }
        guard model.save(Performer(r)) else { busy = false; return }
        st.feedback = learn(st.feedback, f, 0.3); st.persist(model.store)
        model.toast = await model.refreshFromSources(model.performer(id)!)
        busy = false
    }
}

/// ضبط التحليل: الخصائص التي تُحسب.
struct TasteSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var ignore = Set<String>()
    var body: some View {
        List {
            Section("الخصائص المحسوبة في تحليل ذوقك") {
                ForEach(catFields + numFields, id: \.self) { k in
                    Toggle(fieldNames[k] ?? k, isOn: Binding(get: { !ignore.contains(k) }, set: { if $0 { ignore.remove(k) } else { ignore.insert(k) }; try? model.store.setKV("taste_ignore", .array(ignore.sorted().map { .string($0) })) }))
                }
            }
        }
        .navigationTitle("ضبط التحليل")
        .onAppear { ignore = Set((model.store.kv("taste_ignore")?.array ?? []).compactMap { $0.string }) }
    }
}

/// محاكي «ماذا لو؟»: أوزان مؤقتة للخصائص وأثرها على الترتيب — لا يُحفظ شيء إلا إن اخترت.
struct SimulatorView: View {
    @Environment(AppModel.self) private var model
    let st: DiscoverState; let profile: TasteProfile
    @State private var w: [String: Double] = [:]
    var body: some View {
        let base = userFieldWeights((model.store.kv("intel_answers")?.object ?? [:]).compactMapValues { $0.string })
        let trial = base.merging(w) { _, b in b }
        let res = simulate(rankRecs(st.pool, model.performers, hidden: st.hidden), feats: st.candFeats, profile: profile, base: base, trial: trial)
        List {
            Section("أوزان مؤقتة (ماذا لو؟)") {
                ForEach(catFields + ["height", "age"], id: \.self) { k in
                    HStack { Text(fieldNames[k] ?? k).frame(width: 110, alignment: .leading); Slider(value: Binding(get: { w[k] ?? base[k] ?? 1 }, set: { w[k] = $0 }), in: 0...2); Text(String(format: "×%.1f", w[k] ?? base[k] ?? 1)).font(Theme.font(12)) }
                }
                Button("حفظ كأوزاني") {
                    var a = (model.store.kv("intel_answers")?.object ?? [:])
                    for (k, v) in w { a[k] = .string(v >= 1.3 ? "more" : v <= 0.6 ? "less" : "same") }
                    try? model.store.setKV("intel_answers", .object(a)); model.toast = "حُفظت"
                }.disabled(w.isEmpty)
                Button("إعادة") { w = [:] }
            }
            Section("الترتيب بعد المحاكاة") {
                if res.isEmpty { Text("اجمع المرشحات من «اكتشف» أولًا.").foregroundStyle(Theme.muted) }
                ForEach(res.prefix(25), id: \.c.id) { r in
                    HStack { Text("\(r.after + 1).").frame(width: 30); Text(r.c.name); Spacer()
                        let d = r.before - r.after
                        Text(d > 0 ? "↑\(d)" : d < 0 ? "↓\(-d)" : "—").foregroundStyle(d > 0 ? Theme.ok : d < 0 ? Theme.rose : Theme.muted)
                    }.font(Theme.font(13))
                }
            }
        }
        .navigationTitle("ماذا لو؟")
    }
}

/// خريطة الذوق: مفضلاتك في بعدين (تحليل المكوّنات الرئيسية) — المتقاربات خصائصًا متقاربات في الخريطة.
struct TasteMapView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let ps = model.performers.filter { ($0.fav || $0.rating >= 4) && model.feats[$0.id] != nil }
        let pts = tasteMap(ps.map { model.feats[$0.id]! })
        let years = tasteOverTime(model.performers, model.works, model.feats)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if ps.count < 3 { EmptyStateView(icon: "map", title: "لا تكفي البيانات", message: "تحتاج 3 مفضلات لها بيانات وصفية.").frame(height: 300) }
                else {
                    GeometryReader { geo in
                        ZStack {
                            ForEach(ps.indices, id: \.self) { i in
                                NavigationLink(value: Route.performer(ps[i].id)) { Avatar(p: ps[i], size: 34) }
                                    .position(x: geo.size.width / 2 + CGFloat(pts[i].0) * (geo.size.width / 2 - 24), y: geo.size.height / 2 + CGFloat(pts[i].1) * (geo.size.height / 2 - 24))
                            }
                        }
                    }.frame(height: 380).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                Text("ذوقك عبر الزمن").font(Theme.font(17, .bold))
                ForEach(years, id: \.year) { y in
                    Card {
                        Text("\(y.year)").font(Theme.font(15, .bold)).foregroundStyle(Theme.gold)
                        Text("أضفت \(y.added) · شاهدت \(y.watched)").font(Theme.font(12.5))
                        if !y.traits.isEmpty { Text("الغالب: " + y.traits.joined(separator: "، ")).font(Theme.font(12.5)) }
                        if !y.studios.isEmpty { Text("استوديوهات: " + y.studios.joined(separator: "، ")).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    }
                }
            }.padding(16)
        }.background(Theme.bg).navigationTitle("خريطة الذوق")
    }
}
