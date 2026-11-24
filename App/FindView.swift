import SwiftUI
import FavCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// نموذج Apple اللغوي على الجهاز (iOS 26 + Apple Intelligence). لا يُرسل شيء خارج الجهاز. غير متوفر ⇒ nil بهدوء.
enum AppleAI {
    static var status: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "available"
            case .unavailable(let r):
                switch r { case .deviceNotEligible: return "جهازك لا يدعم Apple Intelligence"; case .appleIntelligenceNotEnabled: return "فعّل Apple Intelligence من الإعدادات"; case .modelNotReady: return "النموذج يُنزَّل"; @unknown default: return "غير متوفر" }
            @unknown default: return "غير متوفر"
            }
        }
        #endif
        return "يحتاج iOS 26"
    }
    static func ask(_ prompt: String, instructions: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: instructions)
            return try? await session.respond(to: prompt).content
        }
        #endif
        return nil
    }
    /// يحوّل البحث إلى فلاتر؛ القيم تُتحقق من القوائم المسموحة (NLQuery.fromJSON).
    static func parse(_ text: String) async -> NLQuery? {
        guard let r = await ask(text, instructions: nlModelInstructions), let a = r.firstIndex(of: "{"), let b = r.lastIndex(of: "}"),
              let o = (try? JSONValue.parse(String(r[a...b])))?.object else { return nil }
        let q = NLQuery.fromJSON(o); return q.isEmpty ? nil : q
    }
}

/// البحث الشامل: ممثلات وأعمال واستوديوهات ووسوم معًا، أو وصف باللغة الطبيعية («شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق»).
struct FindView: View {
    @Environment(AppModel.self) private var model
    @State private var q = ""
    @State private var nl = NLQuery()
    @State private var byAI = false
    @State private var aiTask: Task<Void, Never>?

    var body: some View {
        let nq = norm(q)
        let nlMode = !nl.isEmpty
        let perf = performers(nq, nlMode)
        let works = worksFound(nq, nlMode)
        let studios = studiosFound(nq, nlMode)
        let tags = tagsFound(nq, nlMode)
        List {
            if nlMode {
                Section(byAI ? "✨ فهمت (بنموذج Apple على جهازك)" : "فهمت") {
                    FlowLayout { ForEach(nl.labels, id: \.self) { l in Button { nl = nl.without(l) } label: { Label(l, systemImage: "xmark.circle.fill").font(Theme.font(12.5)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.surface, in: Capsule()) }.buttonStyle(.plain) } }
                    let missing = model.performers.filter { model.feats[$0.id] == nil }.count
                    if missing > 0 && (!nl.hair.isEmpty || !nl.eth.isEmpty || !nl.eyes.isEmpty || nl.tattoos != nil || nl.breast != nil) {
                        Text("\(missing) ممثلة بلا بيانات وصفية بعد فلا تظهر — حدّث بيانات مفضلاتك من «اكتشف».").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
            if !perf.isEmpty { Section("الممثلات (\(perf.count))") { ForEach(perf.prefix(60)) { p in NavigationLink(value: Route.performer(p.id)) { PerformerRow(p: p) } } } }
            if !works.isEmpty { Section("الأعمال (\(works.count))") { ForEach(works.prefix(40)) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) } } } }
            if !studios.isEmpty { Section("الاستوديوهات") { ForEach(studios.prefix(20), id: \.self) { s in NavigationLink(value: Route.studio(s)) { Text(s) } } } }
            if !tags.isEmpty { Section("الوسوم") { ForEach(tags.prefix(20), id: \.self) { t in NavigationLink(value: Route.tag(t)) { Text("#\(t)") } } } }
            if q.isEmpty { Section { Text("اكتب اسمًا أو عملًا أو استوديو أو وسمًا… أو صف ما تريد: «شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق».").foregroundStyle(Theme.muted) } }
            else if perf.isEmpty && works.isEmpty && studios.isEmpty && tags.isEmpty { Text("لا نتائج").foregroundStyle(Theme.muted) }
        }
        .navigationTitle("بحث")
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "اسم، عمل، استوديو… أو وصف")
        .onChange(of: q) { _, v in update(v) }
    }

    func performers(_ nq: String, _ nlMode: Bool) -> [Performer] {
        if nlMode {
            let t = norm(nl.text)
            let l = model.performers.filter { p in nlMatch(nl, p, model.feats[p.id] ?? [:]) && (t.isEmpty || norm(p.name).contains(t)) }
            return nlSort(nl, l)
        }
        if nq.isEmpty { return [] }
        return model.performers.filter { p in
            if norm(p.name).contains(nq) || norm(p.aliases).contains(nq) || norm(p.country).contains(nq) { return true }
            return p.tags.contains { norm($0).contains(nq) }
        }
    }
    func worksFound(_ nq: String, _ nlMode: Bool) -> [FavCore.WorkGroup] {
        if nlMode || nq.isEmpty { return [] }
        return model.works.filter { norm($0.t).contains(nq) || norm($0.s).contains(nq) }.sorted { $0.date > $1.date }
    }
    func studiosFound(_ nq: String, _ nlMode: Bool) -> [String] {
        if nlMode || nq.isEmpty { return [] }
        return Array(Set(model.works.map { $0.s }.filter { !$0.isEmpty && norm($0).contains(nq) })).sorted()
    }
    func tagsFound(_ nq: String, _ nlMode: Bool) -> [String] {
        if nlMode || nq.isEmpty { return [] }
        return Array(Set(model.works.flatMap { $0.tg }.filter { norm($0).contains(nq) })).sorted()
    }

    func update(_ v: String) {
        // اسم موجود في مكتبتك ⇒ بحث بالاسم، لا وصف
        let nv = norm(v)
        let isName = nv.count >= 3 && model.performers.contains { norm($0.name).contains(nv) || norm($0.aliases).contains(nv) }
        nl = isName ? NLQuery() : parseQuery(v); byAI = false
        aiTask?.cancel()
        guard !isName, v.split(separator: " ").count >= 2, AppleAI.status == "available" else { return }
        aiTask = Task { try? await Task.sleep(nanoseconds: 700_000_000); if Task.isCancelled { return }
            if let a = await AppleAI.parse(v), !Task.isCancelled { await MainActor.run { nl = a; byAI = true } } }
    }
}
