import SwiftUI
import FavCore

/// ذكاء المفضلة: كل ما يتعلمه التطبيق عن ذوقك — بالدليل والثقة والقيود — مع تحكمك الكامل.
struct IntelligenceView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            ChipRow {
                ForEach(Array(["المحلل", "Taste DNA", "الأنماط", "التغيّر", "ملاحظات", "استثناءات", "سؤال ذكي", "الذاكرة", "الدقة", "صحة المكتبة", "الرسم المعرفي", "التحكم"].enumerated()), id: \.offset) { i, t in Chip(text: t, on: tab == i) { tab = i } }
            }
            ScrollView { VStack(alignment: .leading, spacing: 12) { content }.padding(16) }
        }
        .background(Theme.bg).navigationTitle("ذكاء المفضلة")
    }

    var excluded: Set<String> { Set((model.store.kv("intel_excluded")?.array ?? []).compactMap { $0.string }) }
    var learning: Bool { model.store.kv("intel_cfg")?["learn"]?.bool ?? true }
    var s: [Sample] { samples(model.performers, model.feats, excluded: excluded) }

    @ViewBuilder var content: some View {
        if !learning && tab != 11 { Card { Text("التعلم متوقف — فعّله من «التحكم».").foregroundStyle(Theme.muted) } }
        else {
            switch tab {
            case 0: AnalystView()
            case 1: dnaTab
            case 2: archetypesAndPatterns
            case 3: ShiftsView()
            case 4: insightsTab
            case 5: anomaliesTab
            case 6: QuestionView(dna: tasteDNA(s))
            case 7: MemoryView(dna: tasteDNA(s), arch: archetypes(s))
            case 8: accuracyTab
            case 9: healthTab
            case 10: GraphView()
            default: ControlsView()
            }
        }
    }

    @ViewBuilder var dnaTab: some View {
        let dna = tasteDNA(s)
        if !dna.sufficient { Card { Text("يحتاج 6 ممثلات مقيّمات لها بيانات وصفية (لديك \(dna.count)). قيّم أكثر وحدّث بيانات مفضلاتك من «اكتشف».").foregroundStyle(Theme.muted) } }
        else {
            Text("متوسط تقييمك \(String(format: "%.2f", dna.baseline)) من \(dna.count) ممثلة. الأثر = متوسط تقييمك لمن لها الخاصية ناقص متوسطك.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            effects("تفضيلات قوية", dna.strong, Theme.ok)
            effects("تفضيلات ثانوية", dna.secondary, Theme.gold)
            effects("تقلّ معها تقييماتك", dna.negative, Theme.rose)
            if !dna.synergies.isEmpty {
                Card {
                    Text("تراكيب أقوى من مجموع أجزائها").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                    ForEach(dna.synergies.prefix(8)) { c in comboRow(c) }
                }
            }
            if !dna.boundaries.isEmpty {
                Card {
                    Text("حدود التفضيل (خاصية تنفع بشرط)").font(Theme.font(15, .semibold)).foregroundStyle(Theme.copper)
                    ForEach(dna.boundaries.prefix(6)) { c in comboRow(c) }
                }
            }
            Text("ارتباطات من تقييماتك — لا تعني سببًا مؤكدًا.").font(Theme.font(11)).foregroundStyle(Theme.muted)
        }
    }
    @ViewBuilder func effects(_ title: String, _ l: [TraitEffect], _ c: Color) -> some View {
        if !l.isEmpty {
            Card {
                Text(title).font(Theme.font(15, .semibold)).foregroundStyle(c)
                ForEach(l.prefix(8)) { e in
                    HStack { Text(e.label).font(Theme.font(13)); Spacer(); Text(String(format: "%+.1f", e.effect)).foregroundStyle(c); Text("n=\(e.n)").font(Theme.font(11)).foregroundStyle(Theme.muted); ConfidenceBadge(value: e.confidence) }
                }
            }
        }
    }
    func comboRow(_ c: ComboEffect) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.label).font(Theme.font(13, .semibold))
            Text("متوسطك \(String(format: "%.1f", c.mean)) · المتوقع \(String(format: "%.1f", c.expected)) · من \(c.n)").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder var archetypesAndPatterns: some View {
        let names = model.store.kv("intel_arch")?.object ?? [:]
        let arch = archetypes(s).filter { names[$0.id]?.string != "__dismissed" }
        Text("أنماط ذوقك (عناقيد)").font(Theme.font(17, .bold))
        if arch.isEmpty { Text("تحتاج 6 مفضلات أو تقييمات 3.5+ ببيانات وصفية.").foregroundStyle(Theme.muted) }
        ForEach(arch) { a in ArchetypeCard(a: a, name: names[a.id]?.string ?? a.name) }
        let p = hiddenPatterns(model.works)
        Text("أنماط مخفية في أعمالك").font(Theme.font(17, .bold)).padding(.top, 8)
        if p.isEmpty { Text("لا أنماط ذات دلالة بعد (تحتاج 10 أعمال مقيّمة على الأقل).").foregroundStyle(Theme.muted) }
        ForEach(p) { x in Card { Text(x.title).font(Theme.font(14, .semibold)); Text(x.evidence).font(Theme.font(12)).foregroundStyle(Theme.muted) } }
    }

    @ViewBuilder var insightsTab: some View {
        let dna = tasteDNA(s)
        let sh = preferenceShifts(lib: model.performers, feats: model.feats, works: model.works, days: 90)
        var seen = (model.store.kv("intel_insights_seen")?.object ?? [:]).compactMapValues { $0.number }
        let l = insights(dna: dna, shifts: sh, works: model.works, lib: model.performers, workTaste: buildWorkTaste(model.works), seen: seen)
        if l.isEmpty { Text("لا ملاحظات كافية بعد — كلما قيّمت وشاهدت أكثر ظهرت.").foregroundStyle(Theme.muted) }
        ForEach(l) { i in
            Card {
                HStack { Text(i.title).font(Theme.font(15, .semibold)); Spacer(); ConfidenceBadge(value: i.confidence) }
                Text(i.explanation).font(Theme.font(13))
                Text("الدليل: \(i.evidence)").font(Theme.font(12)).foregroundStyle(Theme.muted)
                Text("اكتُشفت \(Date(timeIntervalSince1970: i.discovered).formatted(date: .abbreviated, time: .omitted))").font(Theme.font(11)).foregroundStyle(Theme.muted)
                if !i.related.isEmpty { FlowLayout { ForEach(i.related.prefix(6), id: \.self) { id in if let p = model.performer(id) { NavigationLink(p.name, value: Route.performer(id)).font(Theme.font(12)) } } } }
            }
        }
        let _ = { for i in l where seen[i.id] == nil { seen[i.id] = i.discovered }; try? model.store.setKV("intel_insights_seen", .object(seen.mapValues { .double($0) })) }()
    }

    @ViewBuilder var anomaliesTab: some View {
        let a = tasteAnomalies(s)
        Text("تقييمات تخالف نمطك المعتاد — استثناءات مثيرة، لا أخطاء. كل ممثلة قورنت بنموذج لم يرها.").font(Theme.font(12)).foregroundStyle(Theme.muted)
        if a.isEmpty { Text("لا استثناءات واضحة (أو البيانات قليلة: تحتاج 10 مقيّمات).").foregroundStyle(Theme.muted) }
        ForEach(a) { x in
            NavigationLink(value: Route.performer(x.p.id)) {
                Card { HStack { Avatar(p: x.p, size: 40); VStack(alignment: .leading) { Text(x.p.name).font(Theme.font(14, .semibold)); Text("قيّمتها \(String(format: "%.1f", x.actual)) والمتوقع من نمطك \(String(format: "%.1f", x.expected))").font(Theme.font(12)).foregroundStyle(Theme.muted) } } }
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder var accuracyTab: some View {
        let log = PredictionLog(json: model.store.kv("intel_pred"))
        let m = log.metrics
        Card {
            Text("دقة تنبؤات التقييم").font(Theme.font(16, .bold))
            if m.n == 0 { Text("لا تنبؤات قورنت بتقييم فعلي بعد. افتح ممثلة غير مقيّمة لترى تنبؤها، ثم قيّمها.").foregroundStyle(Theme.muted) }
            else {
                Text("من \(m.n) تنبؤ: متوسط الخطأ \(String(format: "%.2f", m.mae)) نجمة، و\(Int((m.within05 * 100).rounded()))٪ ضمن ±0.5").font(Theme.font(13))
                if let h = m.maeHighConf, let l = m.maeLowConf { Text("المعايرة: خطأ عالية الثقة \(String(format: "%.2f", h)) مقابل منخفضة الثقة \(String(format: "%.2f", l))").font(Theme.font(12.5)) }
                if let imp = m.improving { Text(imp > 0 ? "يتحسن مع الوقت (الخطأ أقل بـ \(String(format: "%.2f", imp)))" : "لم يتحسن بعد").font(Theme.font(12.5)).foregroundStyle(imp > 0 ? Theme.ok : Theme.muted) }
            }
        }
        ForEach(log.resolved.reversed().prefix(20), id: \.id) { r in
            HStack { Text(model.performer(r.id)?.name ?? r.id).font(Theme.font(13)); Spacer(); Text("توقّع \(String(format: "%.1f", r.p)) · فعلي \(String(format: "%.1f", r.a))").font(Theme.font(12)).foregroundStyle(abs(r.p - r.a) <= 0.5 ? Theme.ok : Theme.rose) }
        }
    }

    @ViewBuilder var healthTab: some View {
        let h = libraryHealth(model.performers)
        Card {
            HStack { Text("صحة المكتبة").font(Theme.font(16, .bold)); Spacer(); Text("\(h.score)/100").font(Theme.font(24, .bold)).foregroundStyle(Theme.gold) }
            Text("اكتمال البيانات ناقص المشكلات (التكرار، التواريخ غير الصالحة، الأعمال المكررة). لا يُطبَّق أي تنظيف بلا تأكيدك.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
        }
        let dupWorks = h.issues.filter { $0.kind == "dupWorks" }
        if !dupWorks.isEmpty {
            Button("دمج الأعمال المكررة عند \(dupWorks.count) ممثلة (بلا فقد بيانات)") {
                model.save(dupWorks.compactMap { model.performer($0.performerIds[0]) }.map { p in p.with(["works": .array(dedupeWorks(p.works).list.map { .object($0) })]) })
            }.buttonStyle(.borderedProminent)
        }
        let gems = hiddenGems(model.performers, model.works)
        if !gems.isEmpty { PerformerShelf(title: "جواهر مخفية (مقيّمة عاليًا ونادرًا ما تزورها)", items: gems) }
        ForEach(h.issues.prefix(80)) { i in
            NavigationLink(value: Route.performer(i.performerIds.first ?? "")) { VStack(alignment: .leading) { Text(i.title).font(Theme.font(13.5, .semibold)); Text(i.detail).font(Theme.font(11.5)).foregroundStyle(Theme.muted) } }.buttonStyle(.plain)
        }
    }
}

struct ArchetypeCard: View {
    @Environment(AppModel.self) private var model
    let a: Archetype; let name: String
    @State private var renaming = false
    @State private var text = ""
    var body: some View {
        Card {
            HStack { Text(name).font(Theme.font(15, .bold)).foregroundStyle(Theme.gold); Spacer(); Text("\(a.members.count) · متوسط \(String(format: "%.1f", a.avgRating))").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            Text(a.traits.prefix(5).map { "\(traitLabel($0.0)) \(Int(($0.1 * 100).rounded()))٪" }.joined(separator: " · ")).font(Theme.font(12))
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(a.members.prefix(10)) { p in NavigationLink(value: Route.performer(p.id)) { Avatar(p: p, size: 36) } } } }
            HStack { Button("إعادة تسمية") { text = name; renaming = true }; Spacer(); Button("تجاهل هذا النمط", role: .destructive) { set("__dismissed") } }.font(Theme.font(12))
        }
        .alert("اسم النمط", isPresented: $renaming) { TextField("الاسم", text: $text); Button("حفظ") { set(text) }; Button("إلغاء", role: .cancel) {} }
    }
    func set(_ v: String) { var o = model.store.kv("intel_arch")?.object ?? [:]; o[a.id] = .string(v); try? model.store.setKV("intel_arch", .object(o)) }
}

struct ShiftsView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 90
    var body: some View {
        let s = preferenceShifts(lib: model.performers, feats: model.feats, works: model.works, days: days)
        VStack(alignment: .leading, spacing: 10) {
            Picker("الفترة", selection: $days) { Text("30 يومًا").tag(30); Text("90").tag(90); Text("6 أشهر").tag(180); Text("سنة").tag(365) }.pickerStyle(.segmented)
            Text("نسبة كل خاصية فيما أضفته (مفضلة أو 4+) وفيما شاهدته — الفترة الأخيرة مقابل ما قبلها.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            group("يزداد ↑", s.rising, Theme.ok); group("يقل ↓", s.falling, Theme.rose); group("جديد يظهر ✦", s.emerging, Theme.gold)
            if s.rising.isEmpty && s.falling.isEmpty && s.emerging.isEmpty { Text("لا تغيّر واضح (أو البيانات قليلة في إحدى الفترتين).").foregroundStyle(Theme.muted) }
        }
    }
    @ViewBuilder func group(_ t: String, _ l: [Shift], _ c: Color) -> some View {
        if !l.isEmpty {
            Card {
                Text(t).font(Theme.font(15, .semibold)).foregroundStyle(c)
                ForEach(l) { x in HStack { Text(x.label).font(Theme.font(13)); Spacer(); Text("\(Int((x.recent * 100).rounded()))٪ ← \(Int((x.before * 100).rounded()))٪").font(Theme.font(12)).foregroundStyle(Theme.muted) } }
                Text("الدليل: \(l[0].nRecent) مؤخرًا مقابل \(l[0].nBefore) قبل").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct QuestionView: View {
    @Environment(AppModel.self) private var model
    let dna: TasteDNA
    var body: some View {
        let answers = (model.store.kv("intel_answers")?.object ?? [:]).compactMapValues { $0.string }
        if let q = nextQuestion(dna: dna, answered: Set(answers.keys)) {
            Card {
                Text(q.text).font(Theme.font(17, .bold))
                Text(q.why).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                HStack {
                    Button("مهم جدًا") { answer(q.field, "more") }.buttonStyle(.borderedProminent)
                    Button("عادي") { answer(q.field, "same") }.buttonStyle(.bordered)
                    Button("غير مهم") { answer(q.field, "less") }.buttonStyle(.bordered)
                }
                Button("تخطَّ") { answer(q.field, "skip") }.font(Theme.font(12))
                Text("جوابك يغيّر وزن هذه الخاصية في الاقتراحات والتنبؤات (يمكنك تغييره من «التحكم»).").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
        } else { Card { Text("لا أسئلة الآن — لا شك يستحق السؤال.").foregroundStyle(Theme.muted) } }
        if !answers.isEmpty { Card { Text("إجاباتك").font(Theme.font(14, .semibold)); ForEach(answers.sorted { $0.key < $1.key }, id: \.key) { e in Text("\(fieldNames[e.key] ?? e.key): \(e.value == "more" ? "مهم جدًا" : e.value == "less" ? "غير مهم" : e.value == "skip" ? "تخطّيت" : "عادي")").font(Theme.font(12.5)) } } }
    }
    func answer(_ f: String, _ v: String) { var a = model.store.kv("intel_answers")?.object ?? [:]; a[f] = .string(v); try? model.store.setKV("intel_answers", .object(a)); model.reload() }
}

struct MemoryView: View {
    @Environment(AppModel.self) private var model
    let dna: TasteDNA; let arch: [Archetype]
    var body: some View {
        let mem = model.store.kv("intel_memory")?.object ?? [:]
        let prefs = learnedPreferences(dna: dna, archetypes: arch, memory: mem)
        Text("ما تعلّمه التطبيق عن ذوقك — مستنتج حتى تؤكده. المرفوض لا يُستخدم.").font(Theme.font(12)).foregroundStyle(Theme.muted)
        if prefs.isEmpty { Text("لا شيء متعلَّم بعد.").foregroundStyle(Theme.muted) }
        ForEach(prefs) { p in
            Card {
                HStack { Text(p.description).font(Theme.font(14, .semibold)); Spacer(); Text(p.status == "confirmed" ? "مؤكَّد ✓" : p.status == "rejected" ? "مرفوض" : "مستنتج").font(Theme.font(11)).foregroundStyle(p.status == "confirmed" ? Theme.ok : p.status == "rejected" ? Theme.rose : Theme.muted) }
                Text(p.evidence).font(Theme.font(12)).foregroundStyle(Theme.muted)
                HStack { ConfidenceBadge(value: p.confidence); Spacer(); Button("تأكيد") { set(p.id, "confirmed") }; Button("رفض") { set(p.id, "rejected") }; Button("إعادة") { set(p.id, nil) } }.font(Theme.font(12))
            }
        }
    }
    func set(_ id: String, _ status: String?) {
        var m = model.store.kv("intel_memory")?.object ?? [:]
        if let status {
            var e = m[id]?.object ?? [:]; let now = Date().timeIntervalSince1970
            if e["f"] == nil { e["f"] = .double(now) }; e["l"] = .double(now); e["s"] = .string(status)
            e["h"] = .array((e["h"]?.array ?? []) + [.string("\(status) \(Date().formatted(date: .abbreviated, time: .omitted))")])
            m[id] = .object(e)
        } else { m[id] = nil }
        try? model.store.setKV("intel_memory", .object(m)); model.reload()
    }
}

/// المحلل الشخصي: أسئلة بالعربية أو الإنجليزية ⇒ استعلام على بياناتك المحلية ⇒ جواب بمراجع حقيقية وحدود واضحة.
struct AnalystView: View {
    @Environment(AppModel.self) private var model
    @State private var q = ""
    @State private var log: [(String, AnalystAnswer)] = []
    @State private var busy = false
    let examples = ["ماذا تغيّر في ذوقي هذه السنة؟", "ما أقوى الأنماط في أعلى تقييماتي؟", "ما الناقص في مكتبتي؟", "أي تفضيلاتي أنت غير متأكد منها؟", "أي تنبؤاتك أخطأت؟", "ماذا أضفت الشهر الماضي؟", "أي الممثلات متشابهات في نمط تقييمي؟", "لماذا قيّمت الأعمال بشكل مختلف؟"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("اسأل عن مكتبتك وذوقك. الإجابات محسوبة من سجلاتك على جهازك فقط — لا أرقام مخترعة.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            FlowLayout { ForEach(examples, id: \.self) { e in Button(e) { ask(e) }.font(Theme.font(12)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.surface, in: Capsule()).buttonStyle(.plain) } }
            HStack { TextField("سؤالك…", text: $q).textFieldStyle(.roundedBorder).onSubmit { ask(q) }; Button("اسأل") { ask(q) }.disabled(q.isEmpty || busy) }
            ForEach(log.indices.reversed(), id: \.self) { i in
                Card {
                    Text(log[i].0).font(Theme.font(13, .semibold)).foregroundStyle(Theme.gold)
                    Text(log[i].1.text).font(Theme.font(13.5))
                    if !log[i].1.uncertainty.isEmpty { Text("حدود: \(log[i].1.uncertainty)").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                    if !log[i].1.refs.isEmpty { FlowLayout { ForEach(log[i].1.refs.prefix(8), id: \.self) { id in if let p = model.performer(id) { NavigationLink(p.name, value: Route.performer(id)).font(Theme.font(12)) } } } }
                }
            }
        }
    }
    func ask(_ question: String) {
        guard !question.isEmpty else { return }
        busy = true
        let ctx = AnalystContext(lib: model.performers, works: model.works, feats: model.feats, dna: tasteDNA(samples(model.performers, model.feats)), predictions: PredictionLog(json: model.store.kv("intel_pred")), workTaste: buildWorkTaste(model.works))
        Task {
            var a = analyze(question, ctx)
            // سؤال لم يُفهم ⇒ نموذج Apple على الجهاز (إن توفّر) يعيد صياغته لأحد الأسئلة المدعومة فقط
            if a.uncertainty.hasPrefix("لم أفهم"), let r = await AppleAI.ask(question, instructions: "Rewrite the user's question as exactly one of these Arabic questions, output it only: " + examples.joined(separator: " | ")),
               examples.contains(r.trimmingCharacters(in: .whitespacesAndNewlines)) {
                a = analyze(r, ctx)
            }
            await MainActor.run { log.append((question, a)); q = ""; busy = false }
        }
    }
}

struct GraphView: View {
    @Environment(AppModel.self) private var model
    @State private var a = ""
    @State private var b = ""
    var body: some View {
        let ps = model.performers.sorted { $0.name < $1.name }
        let kg = KnowledgeGraph(lib: model.performers, works: model.works, lists: model.lists)
        VStack(alignment: .leading, spacing: 10) {
            Text("ما الذي يربط ممثلتين في مكتبتك؟ (أعمال مشتركة، استوديوهات، وسوم، قوائم — من بياناتك فقط)").font(Theme.font(12)).foregroundStyle(Theme.muted)
            Picker("الأولى", selection: $a) { Text("—").tag(""); ForEach(ps) { Text($0.name).tag($0.id) } }
            Picker("الثانية", selection: $b) { Text("—").tag(""); ForEach(ps) { Text($0.name).tag($0.id) } }
            if !a.isEmpty && !b.isEmpty {
                if let path = kg.path("p:\(a)", "p:\(b)") {
                    Card { ForEach(path, id: \.self) { n in Text((n.hasPrefix("p:") ? "👤 " : n.hasPrefix("w:") ? "🎬 " : n.hasPrefix("s:") ? "🏢 " : n.hasPrefix("t:") ? "# " : "📁 ") + (kg.labels[n] ?? n)).font(Theme.font(13)) } }
                } else { Text("لا رابط بينهما في بياناتك.").foregroundStyle(Theme.muted) }
            }
        }
    }
}

struct ControlsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    var body: some View {
        let cfg = model.store.kv("intel_cfg")?.object ?? [:]
        VStack(alignment: .leading, spacing: 10) {
            Toggle("التعلم مفعّل", isOn: Binding(get: { cfg["learn"]?.bool ?? true }, set: { set("learn", $0) }))
            Toggle("إظهار تنبؤات التقييم", isOn: Binding(get: { cfg["pred"]?.bool ?? true }, set: { set("pred", $0) }))
            Toggle("الاكتشاف الاستباقي (في الخلفية)", isOn: Binding(get: { cfg["proactive"]?.bool ?? true }, set: { set("proactive", $0) }))
            Text("السجلات المستبعدة من التحليل").font(Theme.font(14, .semibold)).padding(.top, 8)
            let ex = (model.store.kv("intel_excluded")?.array ?? []).compactMap { $0.string }
            ForEach(ex, id: \.self) { id in HStack { Text(model.performer(id)?.name ?? id); Spacer(); Button("إرجاع") { setExcluded(ex.filter { $0 != id }) } } }
            Menu("استبعاد ممثلة من التحليل") { ForEach(model.performers.filter { $0.rating > 0 && !ex.contains($0.id) }) { p in Button(p.name) { setExcluded(ex + [p.id]) } } }
            Button("إعادة ضبط كل ما تعلّمه التطبيق", role: .destructive) { confirmReset = true }.padding(.top, 10)
            Text("لا يمس تقييماتك ولا سجلاتك — فقط الذاكرة المتعلَّمة والإجابات والتنبؤات.").font(Theme.font(11)).foregroundStyle(Theme.muted)
        }
        .confirmationDialog("إعادة ضبط التعلم؟", isPresented: $confirmReset) {
            Button("إعادة الضبط", role: .destructive) { for k in ["intel_memory", "intel_answers", "intel_pred", "rec_fb", "intel_arch", "intel_insights_seen"] { try? model.store.setKV(k, .object([:])) }; model.reelSig = ReelSignals(); model.saveReelSig(); model.reload() }
        }
    }
    func set(_ k: String, _ v: Bool) { var c = model.store.kv("intel_cfg")?.object ?? [:]; c[k] = .bool(v); try? model.store.setKV("intel_cfg", .object(c)); model.reload() }
    func setExcluded(_ l: [String]) { try? model.store.setKV("intel_excluded", .array(l.map { .string($0) })); model.reload() }
}
