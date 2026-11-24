import SwiftUI
import FavCore

/// الأعمال: موحّدة عبر الممثلات، بتبويبات: لك / الأحدث / للمشاهدة / القادمة / شاهدتها / الأعلى تقييمًا / يومياتي / حسب الممثلة / الاستوديوهات.
struct WorksView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.forYou
    @State private var query = ""
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var evening = false

    enum Tab: String, CaseIterable, Identifiable {
        case forYou = "لك", latest = "الأحدث", queue = "للمشاهدة", upcoming = "القادمة", seen = "شاهدتها", top = "الأعلى تقييمًا", diary = "يومياتي", byPerformer = "حسب الممثلة", studios = "الاستوديوهات"
        var id: String { rawValue }
    }

    func matches(_ g: FavCore.WorkGroup, _ q: String) -> Bool {
        if q.isEmpty { return true }
        if norm(g.t).contains(q) || norm(g.s).contains(q) { return true }
        return g.who.contains(where: { norm($0.name).contains(q) }) || g.tg.contains(where: { norm($0).contains(q) })
    }

    func items(_ all: [FavCore.WorkGroup]) -> [FavCore.WorkGroup] {
        let q = norm(query)
        var l = all.filter { g in
            if !matches(g, q) { return false }
            switch tab {
            case .latest: return !g.isUpcoming()
            case .queue: return g.q && !g.seen
            case .upcoming: return g.isUpcoming()
            case .seen, .diary: return g.seen
            case .top: return g.r > 0
            default: return true
            }
        }
        switch tab {
        case .upcoming: l.sort { $0.date < $1.date }
        case .seen, .diary: l.sort { $0.wd > $1.wd }
        case .top: l.sort { $0.r > $1.r }
        default: l.sort { $0.date > $1.date }
        }
        return l
    }

    var body: some View {
        let all = model.works
        VStack(spacing: 0) {
            ChipRow { ForEach(Tab.allCases) { t in Chip(text: t.rawValue, on: tab == t) { tab = t } } }
            header(all)
            content(all)
        }
        .background(Theme.bg)
        .navigationTitle("الأعمال")
        .searchable(text: $query, prompt: "عنوان، استوديو، ممثلة، وسم…")
        .toolbar {
            Button { evening = true } label: { Image(systemName: "moon.stars.fill") }
            Button(selecting ? "تم" : "تحديد") { selecting.toggle(); selected = [] }
        }
        .sheet(isPresented: $evening) { NavigationStack { EveningView() } }
        .safeAreaInset(edge: .bottom) { if selecting && !selected.isEmpty { bulkBar } }
        .overlay { if all.isEmpty { EmptyStateView(icon: "film", title: "لا أعمال بعد", message: "تظهر هنا أعمال ممثلاتك بعد الاستيراد أو التحديث من المصدرين.") } }
    }

    func header(_ all: [FavCore.WorkGroup]) -> some View {
        let seen = all.filter(\.seen).count, released = all.filter { !$0.isUpcoming() }.count
        let pct = released == 0 ? "—" : "\(Int((Double(seen) / Double(released) * 100).rounded()))٪"
        return HStack(spacing: 8) {
            StatTile(value: "\(all.count)", label: "عمل")
            StatTile(value: pct, label: "شاهدت")
            StatTile(value: "\(all.filter { $0.q && !$0.seen }.count)", label: "للمشاهدة")
            StatTile(value: "\(all.filter { $0.isUpcoming() }.count)", label: "قادم")
        }.padding(.horizontal, 16).padding(.vertical, 6)
    }

    @ViewBuilder func content(_ all: [FavCore.WorkGroup]) -> some View {
        switch tab {
        case .forYou: ForYouList()
        case .byPerformer: ByPerformerList()
        case .studios: StudiosList()
        case .diary: DiaryList(works: items(all))
        default:
            List {
                ForEach(items(all).prefix(600)) { g in row(g) }
            }.scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder func row(_ g: FavCore.WorkGroup) -> some View {
        if selecting {
            Button { if selected.contains(g.key) { selected.remove(g.key) } else { selected.insert(g.key) } } label: {
                HStack { Image(systemName: selected.contains(g.key) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.gold); WorkRow(g: g) }
            }.buttonStyle(.plain).listRowBackground(Theme.surface)
        } else {
            NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.listRowBackground(Theme.surface)
        }
    }

    var bulkBar: some View {
        HStack(spacing: 14) {
            Text("\(selected.count)").font(Theme.font(15, .bold))
            Button("شاهدتها") { bulk { $0["w"] = 1; $0["wd"] = .string(todayStr()); $0["q"] = nil } }
            Button("للمشاهدة") { bulk { $0["q"] = 1 } }
            Menu("تقييم") { ForEach(1...5, id: \.self) { r in Button("\(r) ★") { bulk { $0["r"] = .int(Int64(r)) } } } }
            Spacer()
            Button("إلغاء المشاهدة") { bulk { $0["w"] = nil; $0["wd"] = nil } }
        }.font(Theme.font(14)).padding(14).background(.ultraThinMaterial)
    }

    /// تعديل جماعي: كل نسخ العمل عند كل ممثلاته، بحفظ واحد.
    func bulk(_ fn: @escaping (inout JSONObject) -> Void) {
        var lib = Dictionary(uniqueKeysWithValues: model.performers.map { ($0.id, $0) })
        var changed = Set<String>()
        for g in model.works where selected.contains(g.key) {
            for p in applyToGroup(g, in: lib, fn) { lib[p.id] = p; changed.insert(p.id) }
        }
        model.save(changed.compactMap { lib[$0] }); selected = []; selecting = false
    }
}

/// «لك»: أعمال لم تشاهدها مرتبة بذوقك مع أسبابها، وتقييمك المتوقع.
struct ForYouList: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let t = buildWorkTaste(model.works)
        let picks = recommendWorks(model.works, t, limit: 80)
        List {
            if !t.sufficient { Text("قيّم أو شاهد 5 أعمال على الأقل ليبدأ «لك» بالتعلم.").foregroundStyle(Theme.muted) }
            if !t.top("st:").isEmpty {
                Section("ذوقك في الأعمال") {
                    Text("استوديوهات: " + t.top("st:").map(\.label).joined(separator: "، ")).font(Theme.font(13))
                    if !t.top("tg:").isEmpty { Text("وسوم: " + t.top("tg:").map(\.label).joined(separator: "، ")).font(Theme.font(13)) }
                }
            }
            ForEach(picks, id: \.g.key) { x in pickRow(x, t) }
        }.scrollContentBackground(.hidden)
    }
    func pickRow(_ x: WorkPick, _ t: WorkTaste) -> some View {
        NavigationLink(value: Route.work(x.g.key)) {
            VStack(alignment: .leading, spacing: 4) {
                WorkRow(g: x.g)
                Text(x.why.joined(separator: " · ")).font(Theme.font(11.5)).foregroundStyle(Theme.gold)
                if let pr = predictWork(x.g, t) { Text("تقييمك المتوقع \(String(format: "%.1f", pr.rating)) ★").font(Theme.font(11)).foregroundStyle(Theme.muted) }
            }
        }.listRowBackground(Theme.surface)
    }
}

struct ByPerformerList: View {
    @Environment(AppModel.self) private var model
    struct RowData: Identifiable { let p: Performer; let seen: Int; let total: Int; var id: String { p.id } }
    var rows: [RowData] {
        model.performers.compactMap { p in
            let ws = model.works.filter { g in !g.isUpcoming() && g.who.contains { $0.id == p.id } }
            return ws.isEmpty ? nil : RowData(p: p, seen: ws.filter(\.seen).count, total: ws.count)
        }.sorted { $0.total > $1.total }
    }
    var body: some View {
        List(rows) { r in
            NavigationLink(value: Route.performer(r.p.id)) {
                HStack {
                    Avatar(p: r.p, size: 40)
                    VStack(alignment: .leading) { Text(r.p.name).font(Theme.font(14, .semibold)); ProgressView(value: Double(r.seen) / Double(r.total)).tint(Theme.gold) }
                    Text("\(r.seen)/\(r.total)").font(Theme.font(12))
                }
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden)
    }
}

struct StudiosList: View {
    @Environment(AppModel.self) private var model
    struct RowData: Identifiable { let name: String; let n: Int; let seen: Int; let avg: Double; var id: String { name } }
    var rows: [RowData] {
        var by: [String: [FavCore.WorkGroup]] = [:]
        for g in model.works where !g.s.isEmpty { by[g.s, default: []].append(g) }
        return by.map { k, l in
            let r = l.filter { $0.r > 0 }
            return RowData(name: k, n: l.count, seen: l.filter(\.seen).count, avg: r.isEmpty ? 0 : Double(r.reduce(0) { $0 + $1.r }) / Double(r.count))
        }.sorted { $0.n > $1.n }
    }
    var body: some View {
        List(rows) { r in
            NavigationLink(value: Route.studio(r.name)) {
                HStack {
                    VStack(alignment: .leading) { Text(r.name).font(Theme.font(14, .semibold)); Text("\(r.n) عمل · شاهدت \(r.seen)").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    Spacer()
                    if r.avg > 0 { Text(String(format: "%.1f ★", r.avg)).font(Theme.font(12)) }
                }
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden)
    }
}

struct DiaryList: View {
    let works: [FavCore.WorkGroup]
    var body: some View {
        let months = Dictionary(grouping: works.filter { $0.wd.count >= 7 }) { String($0.wd.prefix(7)) }
        List {
            ForEach(months.keys.sorted(by: >), id: \.self) { m in
                Section("\(m) · \(months[m]!.count)") { ForEach(months[m]!) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.listRowBackground(Theme.surface) } }
            }
        }.scrollContentBackground(.hidden)
    }
}

/// أعمال مصفّاة (استوديو / وسم).
struct FilteredWorksView: View {
    @Environment(AppModel.self) private var model
    let title: String; let filter: (FavCore.WorkGroup) -> Bool
    var body: some View {
        let l = model.works.filter(filter).sorted { $0.date > $1.date }
        List { Section("\(l.count) عمل · شاهدت \(l.filter(\.seen).count)") { ForEach(l) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.listRowBackground(Theme.surface) } } }
            .scrollContentBackground(.hidden).background(Theme.bg).navigationTitle(title)
    }
}

/// ورقة العمل: المشاهدة وتاريخها، للمشاهدة، قادم، التقييم ومعاييره، أنصح به، مفضل، ملاحظة، قوائم الأعمال، الممثلات، والإعلان.
struct WorkSheetView: View {
    @Environment(AppModel.self) private var model
    let key: String
    @State private var note = ""
    @State private var playing = false

    var g: FavCore.WorkGroup? { model.works.first { $0.key == key } }

    var body: some View {
        if let g {
            List {
                infoSection(g)
                stateSection(g)
                ratingSection(g)
                Section("ملاحظة") {
                    TextField("ملاحظتك", text: $note, axis: .vertical)
                    Button("حفظ الملاحظة") { apply { $0["n"] = .string(note) } }
                }
                if !model.wlists.isEmpty { listsSection(g) }
                Section("الممثلات") { ForEach(g.who) { p in NavigationLink(value: Route.performer(p.id)) { HStack { Avatar(p: p, size: 36); Text(p.name) } } } }
                if !g.s.isEmpty || !g.tg.isEmpty {
                    Section("استكشف") {
                        if !g.s.isEmpty { NavigationLink(value: Route.studio(g.s)) { Label("أعمال \(g.s)", systemImage: "building.2") } }
                        ForEach(g.tg.prefix(6), id: \.self) { t in NavigationLink(value: Route.tag(t)) { Text("#\(t)") } }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("العمل").navigationBarTitleDisplayMode(.inline)
            .onAppear { note = g.n }
            .fullScreenCover(isPresented: $playing) { FullVideoView(url: g.tr, title: g.t) }
        } else { EmptyStateView(icon: "film", title: "العمل غير موجود", message: "") }
    }

    func infoSection(_ g: FavCore.WorkGroup) -> some View {
        Section {
            PhotoView(ref: g.p).frame(height: 200).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 14)).listRowInsets(EdgeInsets())
            Text(g.t).font(Theme.font(19, .bold))
            Text([g.s, g.date, g.du > 0 ? "\(g.du) دقيقة" : ""].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(Theme.muted)
            if !g.ds.isEmpty { Text(g.ds).font(Theme.font(13)) }
            if !g.tr.isEmpty { Button { playing = true } label: { Label("تشغيل الإعلان", systemImage: "play.circle.fill") } }
            if g.u.hasPrefix("https://"), let u = URL(string: g.u) { Link(destination: u) { Label("صفحته في المصدر", systemImage: "safari") } }
        }
    }

    func stateSection(_ g: FavCore.WorkGroup) -> some View {
        Section("حالتي") {
            Toggle("شاهدته", isOn: bind({ $0.seen }) { on, w in if on { w["w"] = 1; w["wd"] = .string(todayStr()); w["q"] = nil } else { w["w"] = nil; w["wd"] = nil } })
            if g.seen { Text("تاريخ المشاهدة: \(g.wd)").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            Toggle("للمشاهدة 🔖", isOn: bind({ $0.q }) { on, w in w["q"] = on ? 1 : nil })
            Toggle("قادم", isOn: bind({ $0.upc }) { on, w in w["upc"] = on ? 1 : nil })
            Toggle("أنصح به", isOn: bind({ $0.rec }) { on, w in w["rec"] = on ? 1 : nil })
            Toggle("مفضل", isOn: bind({ $0.fav }) { on, w in w["fav"] = on ? 1 : nil })
        }
    }

    func ratingSection(_ g: FavCore.WorkGroup) -> some View {
        Section("تقييمي") {
            HStack { Text("التقييم"); Spacer(); StarPicker(value: Double(g.r)) { v in apply { $0["r"] = .int(Int64(v.rounded(.up))) } } }
            if g.r == 0, let pr = predictWork(g, buildWorkTaste(model.works)) {
                Text("المتوقع \(String(format: "%.1f", pr.rating)) ★ — \(pr.reasons.first ?? "")").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            criterion("perf", "الأداء", g); criterion("photo", "التصوير", g); criterion("story", "القصة", g)
        }
    }
    func criterion(_ k: String, _ l: String, _ g: FavCore.WorkGroup) -> some View {
        HStack { Text(l); Spacer(); StarPicker(value: Double(g.rc[k] ?? 0)) { v in apply { w in var rc = w["rc"]?.object ?? [:]; rc[k] = .int(Int64(v.rounded(.up))); w["rc"] = .object(rc) } } }
    }

    func listsSection(_ g: FavCore.WorkGroup) -> some View {
        Section("قوائم الأعمال") {
            ForEach(model.wlists.indices, id: \.self) { i in
                let id = model.wlists[i]["id"]?.string ?? ""
                Toggle(model.wlists[i]["name"]?.text ?? id, isOn: Binding(get: { g.ls.contains(id) }, set: { on in apply { w in
                    var l = (w["ls"]?.array ?? []).compactMap { $0.string }
                    if on { if !l.contains(id) { l.append(id) } } else { l.removeAll { $0 == id } }
                    w["ls"] = .array(l.map { .string($0) })
                } }))
            }
        }
    }

    func bind(_ get: @escaping (FavCore.WorkGroup) -> Bool, _ set: @escaping (Bool, inout JSONObject) -> Void) -> Binding<Bool> {
        Binding(get: { g.map(get) ?? false }, set: { on in apply { set(on, &$0) } })
    }
    /// يطبّق التعديل على كل نسخ العمل عند كل ممثلاته.
    func apply(_ fn: @escaping (inout JSONObject) -> Void) {
        guard let g else { return }
        model.save(applyToGroup(g, in: Dictionary(uniqueKeysWithValues: model.performers.map { ($0.id, $0) }), fn))
    }
}

/// «سهرة»: مزاج ومدة ⇒ 3 أعمال لم تشاهدها من ممثلات مختلفات، بأسبابها.
struct EveningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mood = EveningMood.taste
    @State private var minutes = 0
    @State private var seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    var body: some View {
        let picks = eveningPicks(model.works, buildWorkTaste(model.works), mood: mood, maxMinutes: minutes, seed: seed)
        List {
            Section("المزاج") { Picker("المزاج", selection: $mood) { ForEach(EveningMood.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden() }
            Section("الوقت") { Picker("", selection: $minutes) { Text("أي مدة").tag(0); Text("20 د").tag(20); Text("40 د").tag(40); Text("ساعة").tag(60) }.pickerStyle(.segmented) }
            Section("أفضل 3 لليلة") {
                if picks.isEmpty { Text("لا أعمال مناسبة — جرّب مزاجًا أو مدة أخرى.").foregroundStyle(Theme.muted) }
                ForEach(picks, id: \.g.key) { x in
                    NavigationLink(value: Route.work(x.g.key)) { VStack(alignment: .leading) { WorkRow(g: x.g); Text(x.why.joined(separator: " · ")).font(Theme.font(11.5)).foregroundStyle(Theme.gold) } }
                }
                Button { seed &+= 1 } label: { Label("غيّرها", systemImage: "shuffle") }
            }
        }
        .navigationTitle("سهرة").routes().toolbar { Button("إغلاق") { dismiss() } }
    }
}
