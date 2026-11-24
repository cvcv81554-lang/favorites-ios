import SwiftUI
import Charts
import FavCore

/// صفحة الممثلة: صورها، معلوماتها، تقييمها ومعاييرها، «لماذا تحبها؟»، «مسيرتها»، تنبؤ التقييم، علاقاتها، وأعمالها.
struct PerformerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var editing = false
    @State private var viewer: Int?
    @State private var confirmDelete = false
    @State private var detective: [FieldConflict]?
    @State private var workFilter = 0
    @State private var counted = false

    var body: some View {
        if let p = model.performer(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    gallery(p)
                    header(p)
                    infoCard(p)
                    predictionCard(p)
                    ratingCards(p)
                    whyCard(p)
                    careerCard(p)
                    relatedCard(p)
                    accountsCard(p)
                    if !p.tags.isEmpty || !p.lists.isEmpty || !p.notes.isEmpty { extrasCard(p) }
                    if let d = detective { detectiveCard(d) }
                    worksSection(p)
                }.padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(p.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { menu(p) }
            .sheet(isPresented: $editing) { NavigationStack { EditPerformerView(existing: p) } }
            .fullScreenCover(item: Binding(get: { viewer.map { ViewerIndex(i: $0) } }, set: { viewer = $0?.i })) { v in PhotoViewer(p: p, start: v.i) }
            .confirmationDialog("حذف \(p.name)؟", isPresented: $confirmDelete, titleVisibility: .visible) { Button("حذف", role: .destructive) { model.delete(p.id); dismiss() } }
            .onAppear {
                if counted { return }; counted = true   // عدد الزيارات (محلي على الجهاز)
                model.save(p.with(["views": .int(Int64(p.views + 1)), "lastView": .double(Date().timeIntervalSince1970 * 1000)], touch: false))
            }
        } else { EmptyStateView(icon: "person.slash", title: "غير موجودة", message: "") }
    }

    func gallery(_ p: Performer) -> some View {
        let refs = p.photos.isEmpty ? [p.thumb] : p.photos
        return TabView {
            ForEach(Array(refs.enumerated()), id: \.offset) { i, ref in
                PhotoView(ref: ref).frame(maxWidth: .infinity).contentShape(Rectangle()).onTapGesture { viewer = i }
            }
        }
        .tabViewStyle(.page).frame(height: 470).clipShape(RoundedRectangle(cornerRadius: 22))
    }

    func header(_ p: Performer) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(Theme.font(26, .bold))
                if !p.aliases.isEmpty { Text(p.aliases).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2) }
                StarPicker(value: p.rating) { v in
                    model.save(p.with(["rating": .double(v), "tier": .string(p.tier.isEmpty ? tierFromRating(v) : p.tier)]))
                    var log = PredictionLog(json: model.store.kv("intel_pred")); log.resolve(p.id, actual: v); try? model.store.setKV("intel_pred", log.json)
                }
            }
            Spacer()
            Button { model.save(p.with(["fav": .bool(!p.fav)])) } label: { Image(systemName: p.fav ? "star.fill" : "star").font(.system(size: 26)).foregroundStyle(Theme.gold) }
        }
    }

    func infoCard(_ p: Performer) -> some View {
        Card {
            row("العمر", p.age.map { "\($0) سنة" } ?? (p.birth.isEmpty ? "غير معروف — غير موثّق" : p.birth))
            row("البلد", p.country)
            row("الطول", p.height.map { "\(Int($0)) سم" } ?? "")
            row("المسيرة", [p.raw["cs"]?.text ?? "", p.raw["ce"]?.text ?? ""].filter { !$0.isEmpty }.joined(separator: " – "))
            row("الأعمال", "\(p.works.count) · شاهدت \(p.watchedCount)")
            row("الصور", "\(p.photos.count)")
            row("المستوى", p.tier)
            row("المواجهات", p.raw["duels"] == nil ? "" : "\(Int(p.elo)) · \(p.raw["duels"]?.int ?? 0) مواجهة")
            row("المصادر", [p.stashIds.isEmpty ? "" : "StashDB ×\(p.stashIds.count)", p.pdbIds.isEmpty ? "" : "ThePornDB ×\(p.pdbIds.count)"].filter { !$0.isEmpty }.joined(separator: " · "))
            row("المصدر", p.raw["source"]?.text ?? "")
        }
    }
    @ViewBuilder func row(_ k: String, _ v: String) -> some View { if !v.isEmpty { HStack { Text(k).foregroundStyle(Theme.muted); Spacer(); Text(v).multilineTextAlignment(.trailing) }.font(Theme.font(14)) } }

    @ViewBuilder func predictionCard(_ p: Performer) -> some View {
        if p.rating == 0, let f = model.feats[p.id], let pr = predictRating(f, samples: samples(model.performers, model.feats), excludeId: p.id) {
            Card {
                HStack { Label("تقييمك المتوقع", systemImage: "wand.and.stars").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold); Spacer(); ConfidenceBadge(value: pr.confidence) }
                HStack { Stars(value: pr.rating, size: 14); Text(String(format: "%.1f", pr.rating)).font(Theme.font(15, .bold)) }
                ForEach(pr.reasons, id: \.self) { Text("• \($0)").font(Theme.font(12.5)) }
                if !pr.missing.isEmpty { Text("ينقص: \(pr.missing.joined(separator: "، "))").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                Text("تنبؤ وليس حقيقة — يُقارن بتقييمك حين تقيّمها لتحسين الدقة.").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            .onAppear { var log = PredictionLog(json: model.store.kv("intel_pred")); log.predict(p.id, pr); try? model.store.setKV("intel_pred", log.json) }
        }
    }

    @ViewBuilder func ratingCards(_ p: Performer) -> some View {
        if !p.criteriaValues.isEmpty {
            Card {
                Text("المعايير").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                ForEach(Performer.criteria.indices, id: \.self) { i in if let v = p.criteriaValues[Performer.criteria[i].0] { BarRow(label: Performer.criteria[i].1, value: v, max: 5) } }
            }
        }
        if !p.bodyValues.isEmpty {
            Card {
                Text("تفاصيل الجسم").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                ForEach(Performer.bodyDetails.indices, id: \.self) { i in if let v = p.bodyValues[Performer.bodyDetails[i].0] { BarRow(label: Performer.bodyDetails[i].1, value: v, max: 5) } }
            }
        }
    }

    @ViewBuilder func whyCard(_ p: Performer) -> some View {
        if p.fav || p.rating >= 4, let her = model.feats[p.id] {
            let others = model.performers.filter { ($0.fav || $0.rating >= 4) && $0.id != p.id }.compactMap { model.feats[$0.id] }
            let traits = sharedTraits(her, others)
            let costars = Array(Set(model.works.filter { g in g.who.contains { $0.id == p.id } }.flatMap(\.who).filter { $0.id != p.id && $0.fav }.map(\.name)))
            if !traits.isEmpty || !costars.isEmpty {
                Card {
                    Text("لماذا تحبها؟").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                    ForEach(Array(traits.prefix(6).enumerated()), id: \.offset) { _, t in BarRow(label: t.0, value: t.2, max: 1, text: "\(t.1)/\(others.count)") }
                    if !costars.isEmpty { Text("عملت مع مفضلاتك: " + costars.prefix(5).joined(separator: "، ")).font(Theme.font(12.5)) }
                    Text("من بيانات المصادر الموثّقة فقط — تشابه وليس سببًا مؤكدًا.").font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder func careerCard(_ p: Performer) -> some View {
        let c = careerOf(p)
        if !c.isEmpty {
            Card {
                Text("مسيرتها").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                Chart(c.years, id: \.year) { y in
                    BarMark(x: .value("السنة", String(y.year)), y: .value("الأعمال", y.count)).foregroundStyle(Theme.copper.opacity(0.6))
                    BarMark(x: .value("السنة", String(y.year)), y: .value("شاهدت", y.seen)).foregroundStyle(Theme.gold)
                }.frame(height: 140)
                Text(careerLine(c)).font(Theme.font(12.5))
                if !c.topStudios.isEmpty { Text("أكثر الاستوديوهات: " + c.topStudios.prefix(3).map { "\($0.0) (\($0.1))" }.joined(separator: "، ")).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
            }
        }
    }
    func careerLine(_ c: Career) -> String {
        var parts: [String] = []
        if let f = c.first { parts.append("أول سنة \(f)") }
        if let pk = c.peak { parts.append("الذروة \(pk)") }
        if let t = c.trend { parts.append(t > 0.2 ? "تقييمك لها يرتفع" : t < -0.2 ? "تقييمك لها ينخفض" : "تقييمك ثابت") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder func relatedCard(_ p: Performer) -> some View {
        let kg = KnowledgeGraph(lib: model.performers, works: model.works, lists: model.lists)
        let rel: [(Performer, String)] = kg.related(performer: p.id, k: 8).compactMap { r in model.performer(r.0).map { ($0, r.2) } }
        if !rel.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("مرتبطات بها في مكتبتك").font(Theme.font(15, .semibold))
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { ForEach(rel, id: \.0.id) { x in NavigationLink(value: Route.performer(x.0.id)) { MiniPerformer(p: x.0, caption: x.1) }.buttonStyle(.plain) } } }
            }
        }
    }

    @ViewBuilder func accountsCard(_ p: Performer) -> some View {
        let acc: [(String, URL)] = p.accounts.compactMap { a in accountURL(platform: a.platform, value: a.value).map { (platforms.first { $0.key == a.platform }?.label ?? a.platform, $0) } }
        if !acc.isEmpty {
            Card {
                Text("حساباتها").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                FlowLayout { ForEach(acc, id: \.1) { a in Link(a.0, destination: a.1).font(Theme.font(13)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.bg, in: Capsule()) } }
            }
        }
    }

    func extrasCard(_ p: Performer) -> some View {
        Card {
            if !p.tags.isEmpty { FlowLayout { ForEach(p.tags, id: \.self) { t in Text("#\(t)").font(Theme.font(12.5)).padding(.horizontal, 8).padding(.vertical, 4).background(Theme.bg, in: Capsule()) } } }
            if !p.lists.isEmpty { Text("القوائم: " + p.lists.map(model.listName).joined(separator: "، ")).font(Theme.font(13)) }
            if !p.notes.isEmpty { Text(p.notes).font(Theme.font(14)) }
        }
    }

    func detectiveCard(_ d: [FieldConflict]) -> some View {
        Card {
            Text("محقق البيانات").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
            if d.isEmpty { Text("المصدران متفقان في الحقول المتاحة.").font(Theme.font(13)) }
            ForEach(d) { c in VStack(alignment: .leading) { Text(c.field).font(Theme.font(13, .semibold)); Text("StashDB: \(c.stash) · ThePornDB: \(c.tpdb)").font(Theme.font(12.5)).foregroundStyle(Theme.muted) } }
        }
    }

    @ViewBuilder func worksSection(_ p: Performer) -> some View {
        let all = model.works.filter { g in g.who.contains { $0.id == p.id } }.sorted { $0.date > $1.date }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("أعمالها (\(all.count))").font(Theme.font(17, .bold))
                Picker("", selection: $workFilter) { Text("الكل").tag(0); Text("لم أشاهد").tag(1); Text("قادمة").tag(2); Text("قيّمتها").tag(3) }.pickerStyle(.segmented)
                ForEach(filterWorks(all).prefix(80)) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.buttonStyle(.plain) }
            }
        }
    }
    func filterWorks(_ all: [FavCore.WorkGroup]) -> [FavCore.WorkGroup] {
        switch workFilter {
        case 1: return all.filter { !$0.seen && !$0.isUpcoming() }
        case 2: return all.filter { $0.isUpcoming() }
        case 3: return all.filter { $0.r > 0 }.sorted { $0.r > $1.r }
        default: return all
        }
    }

    func menu(_ p: Performer) -> some View {
        Menu {
            Button { editing = true } label: { Label("تعديل", systemImage: "pencil") }
            Button { Task { model.toast = await model.refreshFromSources(p) } } label: { Label("تحديث من المصدرين", systemImage: "arrow.triangle.2.circlepath") }
            NavigationLink(value: Route.link(p.id)) { Label(p.stashIds.isEmpty && p.pdbIds.isEmpty ? "ربط بمصدر" : "ربط بسجل آخر", systemImage: "link") }
            if !p.stashIds.isEmpty && !p.pdbIds.isEmpty {
                Button { Task { await runDetective(p) } } label: { Label("محقق البيانات (مقارنة المصدرين)", systemImage: "magnifyingglass.circle") }
            }
            if !p.works.isEmpty { NavigationLink(value: Route.missing(p.id)) { Label("أعمالها الناقصة في خادمك", systemImage: "rectangle.stack.badge.minus") } }
            if p.photos.count >= 2 { NavigationLink(value: Route.facesAlbum(p.id)) { Label("فحص صورها بالوجه", systemImage: "face.smiling") } }
            Menu("ثقة تقييمي") {
                Button("متأكد") { model.save(p.with(["rconf": 3], touch: false)) }
                Button("جزئي") { model.save(p.with(["rconf": 2], touch: false)) }
                Button("غير متأكد") { model.save(p.with(["rconf": 1], touch: false)) }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("حذف", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    @MainActor func runDetective(_ p: Performer) async {
        model.busy = "مقارنة المصدرين…"
        let s = try? await StashDB.performer(p.stashIds[0])
        let t = try? await TPDB.performer(p.pdbIds[0])
        model.busy = nil
        detective = dataDetective(stash: s ?? nil, tpdb: t ?? nil)
    }
}

struct ViewerIndex: Identifiable { let i: Int; var id: Int { i } }

/// نجوم قابلة للضغط (أنصاف).
struct StarPicker: View {
    let value: Double; let onChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: value - Double(i) >= 1 ? "star.fill" : value - Double(i) >= 0.5 ? "star.leadinghalf.filled" : "star").font(.system(size: 20)).foregroundStyle(Theme.gold)
                    .overlay(HStack(spacing: 0) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { onChange(Double(i) + 0.5) }
                        Color.clear.contentShape(Rectangle()).onTapGesture { onChange(Double(i) + 1) }
                    })
            }
        }.environment(\.layoutDirection, .leftToRight)
    }
}

/// عارض الصور: تمرير، تكبير بإصبعين، تعيين رئيسية، حذف.
struct PhotoViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let p: Performer; let start: Int
    @State private var i = 0
    @State private var scale: CGFloat = 1
    var body: some View {
        let refs = model.performer(p.id)?.photos ?? p.photos
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $i) {
                ForEach(Array(refs.enumerated()), id: \.offset) { k, ref in
                    PhotoView(ref: ref).scaledToFit().scaleEffect(scale)
                        .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } }).tag(k)
                }
            }.tabViewStyle(.page)
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle()) }
                Spacer()
                Text("\(min(i + 1, refs.count))/\(refs.count)").font(Theme.font(13))
                Spacer()
                Menu {
                    Button("تعيينها رئيسية") { setMain(refs) }
                    Button("حذف الصورة", role: .destructive) { remove(refs) }
                } label: { Image(systemName: "ellipsis").padding(12).background(.ultraThinMaterial, in: Circle()) }
            }.padding()
        }
        .onAppear { i = start }
    }
    func setMain(_ refs: [String]) {
        guard i < refs.count, let cur = model.performer(p.id) else { return }
        var l = refs; let x = l.remove(at: i); l.insert(x, at: 0)
        model.save(cur.with(["photos": .array(l.map { .string($0) }), "thumb": .string(x)])); i = 0
    }
    func remove(_ refs: [String]) {
        guard i < refs.count, let cur = model.performer(p.id) else { return }
        var l = refs; l.remove(at: i)
        model.save(cur.with(["photos": .array(l.map { .string($0) }), "thumb": .string(l.first ?? "")])); i = max(0, i - 1)
    }
}
