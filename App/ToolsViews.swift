import SwiftUI
import FavCore

/// الأدوات.
struct ToolsView: View {
    var body: some View {
        List {
            NavigationLink { DuelView() } label: { Label("المواجهة (Elo)", systemImage: "bolt.fill") }
            NavigationLink { TiersView() } label: { Label("المستويات S·A·B·C·D", systemImage: "list.number") }
            NavigationLink { RatingSessionView() } label: { Label("جلسة تقييم", systemImage: "star.leadinghalf.filled") }
            NavigationLink { AchievementsView() } label: { Label("الإنجازات", systemImage: "trophy.fill") }
            NavigationLink { EveningView() } label: { Label("مزاج الليلة (سهرة)", systemImage: "moon.stars.fill") }
            NavigationLink { CompletenessView() } label: { Label("اكتمال المكتبة", systemImage: "checkmark.seal") }
            NavigationLink { OnThisDayView() } label: { Label("في مثل هذا اليوم", systemImage: "clock.arrow.circlepath") }
            NavigationLink { WishListView() } label: { Label("قائمة الأمنيات", systemImage: "wand.and.rays") }
            NavigationLink { ListsManager() } label: { Label("قوائمي", systemImage: "folder") }
            NavigationLink { WorkListsManager() } label: { Label("قوائم الأعمال", systemImage: "film.stack") }
            NavigationLink { SmartListsView() } label: { Label("قوائم ذكية وفلاتر محفوظة", systemImage: "line.3.horizontal.decrease.circle") }
            NavigationLink { RandomPickView() } label: { Label("سحب عشوائي", systemImage: "dice.fill") }
        }.navigationTitle("الأدوات")
    }
}

struct DuelView: View {
    @Environment(AppModel.self) private var model
    @State private var pair: (Performer, Performer)?
    @State private var last = Set<String>()
    @State private var favOnly = false
    @State private var board = false
    var pool: [Performer] { model.performers.filter { !$0.cover.isEmpty && (!favOnly || $0.fav) } }
    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $board) { Text("العب").tag(false); Text("الترتيب").tag(true) }.pickerStyle(.segmented)
            if board {
                List(Array(pool.filter { duelsOf($0) > 0 }.sorted { $0.elo > $1.elo }.prefix(100).enumerated()), id: \.element.id) { e in
                    HStack { Text("\(e.offset + 1)").frame(width: 30); Avatar(p: e.element, size: 32); Text(e.element.name); Spacer(); Text("\(Int(e.element.elo))").foregroundStyle(Theme.gold); Text("\(e.element.raw["dw"]?.int ?? 0)/\(duelsOf(e.element))").font(Theme.font(11)).foregroundStyle(Theme.muted) }
                }.scrollContentBackground(.hidden)
            } else {
                Toggle("المفضلات فقط", isOn: $favOnly)
                Text("اختر المفضلة لديك").font(Theme.font(17, .bold))
                if let pr = pair {
                    HStack(spacing: 12) { side(pr.0, pr.1); side(pr.1, pr.0) }
                    Button("تخطَّ") { next() }
                } else { Text("تحتاج ممثلتين لهما صور").foregroundStyle(Theme.muted) }
                Spacer()
            }
        }
        .padding().background(Theme.bg).navigationTitle("المواجهة")
        .onAppear { if pair == nil { next() } }
    }
    func side(_ w: Performer, _ l: Performer) -> some View {
        Button { vote(w, l) } label: {
            VStack { PhotoView(ref: w.cover).frame(height: 300).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16)); Text(w.name).font(Theme.font(14, .semibold)) }
        }.buttonStyle(.plain)
    }
    func vote(_ w: Performer, _ l: Performer) {
        let (nw, nl) = eloUpdate(winner: w.elo, loser: l.elo)
        model.save([w.with(["elo": .double(nw), "duels": .int(Int64(duelsOf(w) + 1)), "dw": .int(Int64((w.raw["dw"]?.int ?? 0) + 1))]),
                    l.with(["elo": .double(nl), "duels": .int(Int64(duelsOf(l) + 1))])])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        last = [w.id, l.id]; next()
    }
    func next() { var g = SystemRandomNumberGenerator(); pair = pickPair(pool, using: &g, last: last) }
}

struct TiersView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Button("تعيين تلقائي من التقييم (لمن بلا مستوى)") { model.save(model.performers.filter { $0.tier.isEmpty && $0.rating > 0 }.map { $0.with(["tier": .string(tierFromRating($0.rating))]) }) }
            ForEach(["S", "A", "B", "C", "D", ""], id: \.self) { t in
                let l = model.performers.filter { $0.tier == t }
                if !l.isEmpty {
                    Section(t.isEmpty ? "بلا مستوى (\(l.count))" : "المستوى \(t) (\(l.count))") {
                        ForEach(l) { p in
                            HStack { Avatar(p: p, size: 34); Text(p.name); Spacer()
                                Menu(p.tier.isEmpty ? "—" : p.tier) { ForEach(["S", "A", "B", "C", "D"], id: \.self) { x in Button(x) { model.save(p.with(["tier": .string(x)])) } }; Button("بلا") { model.save(p.with(["tier": .null])) } }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("المستويات")
    }
}

struct RatingSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var queue: [String] = []
    var body: some View {
        VStack(spacing: 14) {
            if let id = queue.first, let p = model.performer(id) {
                Text("جلسة تقييم · \(queue.count)").foregroundStyle(Theme.muted)
                PhotoView(ref: p.cover).frame(height: 420).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 20))
                Text(p.name).font(Theme.font(22, .bold))
                StarPicker(value: p.rating) { v in model.save(p.with(["rating": .double(v)])); queue.removeFirst() }
                HStack { Button(p.fav ? "★ مفضلة" : "☆ مفضلة") { model.save(p.with(["fav": .bool(!p.fav)])) }; Spacer(); NavigationLink("افتح", value: Route.performer(p.id)); Spacer(); Button("تخطَّ") { queue.removeFirst() } }
            } else { EmptyStateView(icon: "checkmark.circle", title: "لا ممثلات بلا تقييم", message: "") }
            Spacer()
        }
        .padding().background(Theme.bg).navigationTitle("جلسة تقييم")
        .onAppear { if queue.isEmpty { queue = model.performers.filter { $0.rating == 0 && $0.criteriaValues.isEmpty }.map(\.id).shuffled() } }
    }
}

struct AchievementsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List(achievements(model.performers, model.works, lists: model.lists.count + model.wlists.count), id: \.title) { a in
            HStack {
                Image(systemName: a.icon).foregroundStyle(a.reached > 0 ? Theme.gold : Theme.muted).frame(width: 30)
                VStack(alignment: .leading) {
                    Text(a.title).font(Theme.font(15, .semibold))
                    Text(a.next.map { "\(a.value) / \($0)" } ?? "اكتمل (\(a.value)) 🏆").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    ProgressView(value: Double(a.value), total: Double(a.next ?? max(1, a.value))).tint(Theme.gold)
                }
                Text(String(repeating: "★", count: a.reached)).foregroundStyle(Theme.gold)
            }
        }.navigationTitle("الإنجازات")
    }
}

struct CompletenessView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let h = libraryHealth(model.performers)
        List {
            Section { HStack { Text("صحة المكتبة"); Spacer(); Text("\(h.score)/100").font(Theme.font(20, .bold)).foregroundStyle(Theme.gold) } }
            Section("الأقل اكتمالًا") {
                ForEach(model.performers.map { ($0, completeness($0)) }.sorted { $0.1.filter(\.1).count < $1.1.filter(\.1).count }.prefix(40), id: \.0.id) { x in
                    NavigationLink(value: Route.performer(x.0.id)) { VStack(alignment: .leading) { Text(x.0.name); Text("ينقص: " + x.1.filter { !$0.1 }.map(\.0).joined(separator: "، ")).font(Theme.font(11.5)).foregroundStyle(Theme.muted) } }
                }
            }
        }.navigationTitle("اكتمال المكتبة")
    }
}

struct OnThisDayView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let d = onThisDay(model.works)
        let b = upcomingBirthdays(model.performers, days: 0)
        List {
            if !b.isEmpty { Section("أعياد ميلاد اليوم") { ForEach(b, id: \.0.id) { x in Text("\(x.0.name) — تكمل \(x.2)") } } }
            Section("شاهدته في مثل هذا اليوم") { ForEach(d.watched) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) } }; if d.watched.isEmpty { Text("لا شيء").foregroundStyle(Theme.muted) } }
            Section("صدر في مثل هذا اليوم") { ForEach(d.released.prefix(30)) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) } } }
        }.navigationTitle("في مثل هذا اليوم")
    }
}

struct WishListView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [String] = []
    @State private var name = ""
    var body: some View {
        List {
            HStack { TextField("اسم تضيفه لاحقًا", text: $name); Button("إضافة") { add() }.disabled(name.isEmpty) }
            ForEach(items, id: \.self) { n in NavigationLink { SourceSearchView(initial: n, linkTo: nil) } label: { Text(n) } }.onDelete { items.remove(atOffsets: $0); persist() }
        }
        .navigationTitle("قائمة الأمنيات")
        .onAppear { items = ((try? JSONValue.parse((model.store.kv("prefs")?["vkte_wish"]?.string) ?? "[]"))?.array ?? []).compactMap { $0["n"]?.string ?? $0.string }.filter { n in !model.performers.contains { norm($0.name) == norm(n) } } }
    }
    func add() { if !model.performers.contains(where: { norm($0.name) == norm(name) }) && !items.contains(name) { items.append(name) }; name = ""; persist() }
    func persist() {
        var prefs = model.store.kv("prefs")?.object ?? [:]
        prefs["vkte_wish"] = .string(String(decoding: (try? JSONValue.array(items.map { .object(["n": .string($0), "t": .double(Date().timeIntervalSince1970 * 1000)]) }).encoded()) ?? Data(), as: UTF8.self))
        try? model.store.setKV("prefs", .object(prefs))
    }
}

struct WorkListsManager: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    var body: some View {
        List {
            HStack { TextField("قائمة أعمال جديدة", text: $newName); Button("إضافة") { model.setWLists(model.wlists + [["id": .string("W" + UUID().uuidString.prefix(8)), "name": .string(newName)]]); newName = "" }.disabled(newName.isEmpty) }
            ForEach(model.wlists.indices, id: \.self) { i in
                let id = model.wlists[i]["id"]?.string ?? ""
                NavigationLink { FilteredWorksView(title: model.wlists[i]["name"]?.text ?? "", filter: { $0.ls.contains(id) }) } label: { HStack { Text(model.wlists[i]["name"]?.text ?? id); Spacer(); Text("\(model.works.filter { $0.ls.contains(id) }.count)").foregroundStyle(Theme.muted) } }
            }.onDelete { idx in model.setWLists(model.wlists.enumerated().filter { !idx.contains($0.offset) }.map(\.element)) }
        }.navigationTitle("قوائم الأعمال")
    }
}

/// قوائم ذكية: شرط محفوظ (بحث باللغة الطبيعية) تتحدث عضويته تلقائيًا.
struct SmartListsView: View {
    @Environment(AppModel.self) private var model
    @State private var lists: [(String, String)] = []
    @State private var name = "", rule = ""
    var body: some View {
        List {
            Section("قائمة ذكية جديدة") {
                TextField("الاسم", text: $name)
                TextField("الشرط، مثل: شقراء تقييمها 4 فما فوق", text: $rule)
                if !rule.isEmpty { Text("فهمت: " + parseQuery(rule).labels.joined(separator: "، ")).font(Theme.font(12)).foregroundStyle(Theme.gold) }
                Button("حفظ") { lists.append((name, rule)); persist(); name = ""; rule = "" }.disabled(name.isEmpty || parseQuery(rule).isEmpty)
            }
            Section("قوائمي الذكية") {
                ForEach(lists.indices, id: \.self) { i in
                    let q = parseQuery(lists[i].1)
                    let members = nlSort(q, model.performers.filter { nlMatch(q, $0, model.feats[$0.id] ?? [:]) })
                    NavigationLink { List(members) { p in NavigationLink(value: Route.performer(p.id)) { PerformerRow(p: p) } }.navigationTitle(lists[i].0) } label: {
                        HStack { VStack(alignment: .leading) { Text(lists[i].0); Text(q.labels.joined(separator: "، ")).font(Theme.font(11)).foregroundStyle(Theme.muted) }; Spacer(); Text("\(members.count)") }
                    }
                }.onDelete { lists.remove(atOffsets: $0); persist() }
            }
        }
        .navigationTitle("قوائم ذكية")
        .onAppear { lists = (model.store.kv("smart_lists")?.array ?? []).compactMap { x in x["n"]?.string.map { ($0, x["r"]?.text ?? "") } } }
    }
    func persist() { try? model.store.setKV("smart_lists", .array(lists.map { .object(["n": .string($0.0), "r": .string($0.1)]) })) }
}

struct RandomPickView: View {
    @Environment(AppModel.self) private var model
    @State private var pick: FavCore.WorkGroup?
    @State private var favOnly = true
    var body: some View {
        VStack(spacing: 16) {
            Toggle("من المفضلات فقط", isOn: $favOnly)
            if let g = pick { NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.buttonStyle(.plain) }
            Button { draw() } label: { Label("اسحب عملًا لم تشاهده", systemImage: "dice.fill") }.buttonStyle(.borderedProminent)
            Spacer()
        }.padding().navigationTitle("سحب عشوائي")
    }
    func draw() { pick = model.works.filter { !$0.seen && !$0.isUpcoming() && (!favOnly || $0.who.contains(where: \.fav)) }.randomElement() }
}
