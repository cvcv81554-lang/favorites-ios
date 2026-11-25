import SwiftUI
import PhotosUI
import FavCore

/// نموذج الإضافة/التعديل: كل الحقول، الصور من المعرض، المعايير الثمانية وتفاصيل الجسم، الحسابات، القوائم، الأعمال.
/// الحفظ يرفض العمر الأقل من 18 أو التاريخ غير الصالح، ويطلب تأكيد البلوغ للإضافة اليدوية.
struct EditPerformerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: Performer?
    @State private var name = ""
    @State private var aliases = ""
    @State private var country = ""
    @State private var birth = ""
    @State private var notes = ""
    @State private var tags = ""
    @State private var worksText = ""
    @State private var rating = 0.0
    @State private var fav = false
    @State private var useCriteria = false
    @State private var useBody = false
    @State private var crit: [String: Double] = [:]
    @State private var bodyMap: [String: Double] = [:]
    @State private var accounts: [(String, String)] = []
    @State private var lists = Set<String>()
    @State private var adult = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var newPhotos: [Data] = []
    @State private var error: String?

    var body: some View {
        Form {
            Section("الأساسي") {
                TextField("الاسم (مطلوب)", text: $name)
                TextField("أسماء أخرى (مفصولة بفاصلة)", text: $aliases)
                TextField("البلد", text: $country)
                TextField("تاريخ الميلاد YYYY-MM-DD", text: $birth).keyboardType(.numbersAndPunctuation)
                Toggle("مفضلة ★", isOn: $fav)
            }
            Section("التقييم") {
                Toggle("بالمعايير الثمانية", isOn: $useCriteria)
                if useCriteria {
                    ForEach(Performer.criteria.indices, id: \.self) { i in slider(Performer.criteria[i].1, key: Performer.criteria[i].0, map: $crit) }
                    Text("التقييم العام = متوسط المعايير: \(String(format: "%.1f", applyRatings(criteria: crit, body: useBody ? bodyMap : [:]).rating))").font(Theme.font(12)).foregroundStyle(Theme.muted)
                } else {
                    HStack { Text("التقييم"); Spacer(); StarPicker(value: rating) { rating = $0 } }
                }
                Toggle("تفاصيل الجسم (اختياري)", isOn: $useBody)
                if useBody { ForEach(Performer.bodyDetails.indices, id: \.self) { i in slider(Performer.bodyDetails[i].1, key: Performer.bodyDetails[i].0, map: $bodyMap) } }
            }
            Section("الصور") {
                PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .images) { Label("إضافة من المعرض", systemImage: "photo.on.rectangle") }
                if !newPhotos.isEmpty { Text("\(newPhotos.count) صورة جديدة").foregroundStyle(Theme.muted) }
            }
            Section("الحسابات") {
                ForEach(accounts.indices, id: \.self) { i in
                    HStack {
                        Picker("", selection: Binding(get: { accounts[i].0 }, set: { accounts[i].0 = $0 })) { ForEach(platforms, id: \.key) { Text($0.label).tag($0.key) } }.labelsHidden()
                        TextField("اسم المستخدم أو الرابط", text: Binding(get: { accounts[i].1 }, set: { accounts[i].1 = $0 })).textInputAutocapitalization(.never)
                    }
                }.onDelete { accounts.remove(atOffsets: $0) }
                Button("إضافة حساب") { accounts.append(("instagram", "")) }
            }
            Section("الوسوم والقوائم") {
                TextField("وسوم (مفصولة بفاصلة)", text: $tags)
                ForEach(model.lists.indices, id: \.self) { i in
                    let id = model.lists[i]["id"]?.string ?? ""
                    Toggle(model.lists[i]["name"]?.text ?? id, isOn: Binding(get: { lists.contains(id) }, set: { if $0 { lists.insert(id) } else { lists.remove(id) } }))
                }
            }
            Section("أعمال (لصق: عنوان | موقع | سنة — سطر لكل عمل)") { TextEditor(text: $worksText).frame(minHeight: 80) }
            Section("ملاحظات") { TextEditor(text: $notes).frame(minHeight: 70) }
            if existing == nil { Section { Toggle("أؤكد أنها بالغة (18+)", isOn: $adult) } }
            if let error { Text(error).foregroundStyle(Theme.rose) }
        }
        .navigationTitle(existing == nil ? "ممثلة جديدة" : "تعديل")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("حفظ") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onAppear(perform: load)
        .onChange(of: picked) { _, items in Task { for it in items { if let d = try? await it.loadTransferable(type: Data.self) { newPhotos.append(d) } }; picked = [] } }
    }

    func slider(_ label: String, key: String, map: Binding<[String: Double]>) -> some View {
        HStack {
            Text(label).font(Theme.font(13)).frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { map.wrappedValue[key] ?? 0 }, set: { map.wrappedValue[key] = ($0 * 2).rounded() / 2 }), in: 0...5, step: 0.5)
            Text(String(format: "%.1f", map.wrappedValue[key] ?? 0)).font(Theme.font(12)).frame(width: 30)
        }
    }

    func load() {
        guard let p = existing, name.isEmpty else { return }
        name = p.name; aliases = p.aliases; country = p.country; birth = p.birth; notes = p.notes; tags = p.tags.joined(separator: ", ")
        rating = p.rating; fav = p.fav; crit = p.criteriaValues; bodyMap = p.bodyValues; useCriteria = !crit.isEmpty; useBody = !bodyMap.isEmpty
        accounts = p.accounts.map { ($0.platform, $0.value) }; lists = Set(p.lists)
    }

    func save() {
        let b = birth.trimmingCharacters(in: .whitespaces)
        if !b.isEmpty { let a = sdAge(b); if a.invalid || (a.age ?? 0) < 18 { error = "التاريخ غير صالح أو العمر أقل من 18 — لا يُحفظ"; return } }
        if existing == nil && !adult { error = "أكّد أنها بالغة (18+)"; return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if existing == nil, model.performers.contains(where: { norm($0.name) == norm(n) }) { error = "يوجد سجل بنفس الاسم — افتحه وعدّله بدل التكرار"; return }
        let id = existing?.id ?? "p-" + UUID().uuidString.lowercased()
        var photos = existing?.photos ?? []
        for (i, d) in newPhotos.enumerated() where photos.count < 30 {
            let uri = "data:image/jpeg;base64," + d.base64EncodedString()
            if let ref = model.store.storeImage(uri, id: id, index: Int(Date().timeIntervalSince1970) % 100000 + i) { photos.append(ref) }
        }
        var rat = rating
        var cr: [String: Double] = [:]
        if useCriteria { let r = applyRatings(criteria: crit, body: useBody ? bodyMap : [:]); cr = r.criteria; rat = r.rating }
        var ch: JSONObject = ["id": .string(id), "name": .string(n), "aliases": .string(aliases), "country": .string(country), "birth": .string(b), "notes": .string(notes),
                              "fav": .bool(fav), "rating": .double(rat), "tags": .array(tags.components(separatedBy: CharacterSet(charactersIn: ",،")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { .string($0) }),
                              "lists": .array(lists.sorted().map { .string($0) }), "photos": .array(photos.map { .string($0) }),
                              "accounts": .array(accounts.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map { .object(["p": .string($0.0), "v": .string($0.1)]) })]
        ch["criteria"] = useCriteria ? .object(cr.mapValues { .double($0) }) : .null
        ch["bodyD"] = useBody ? .object(bodyMap.filter { $0.value > 0 }.mapValues { .double($0) }) : .null
        if (existing?.thumb ?? "").isEmpty, let f = photos.first { ch["thumb"] = .string(f) }
        var works = existing?.works ?? []
        if !worksText.isEmpty {
            let parsed = safeWorks(.array(worksText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { .string($0) })).compactMap { $0.object }
            works = mergeWorks(works, parsed).list
        }
        ch["works"] = .array(works.map { .object($0) })
        if existing == nil { ch["source"] = "إدخال يدوي"; ch["added"] = .double(Date().timeIntervalSince1970 * 1000) }
        let p = (existing ?? Performer(["id": .string(id)])).with(ch)
        if model.save(p) { dismiss() } else { error = "رُفض الحفظ" }
    }
}

/// البحث في المصدرين (StashDB + ThePornDB): إضافة ممثلة جديدة، أو ربط سجل موجود.
struct SourceSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let initial: String; let linkTo: String?
    @State private var q = ""
    @State private var results: [Candidate] = []
    @State private var msg = ""
    @State private var busy = false

    var body: some View {
        List {
            Section {
                HStack { TextField("اسم الممثلة", text: $q).onSubmit { Task { await search() } }; Button("بحث") { Task { await search() } }.disabled(q.count < 2 || busy) }
                if !msg.isEmpty { Text(msg).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
            }
            ForEach(results) { c in
                Button { Task { await pick(c) } } label: {
                    HStack(spacing: 12) {
                        Group { if c.image.isEmpty { Theme.surface } else { PhotoView(ref: c.image) } }.frame(width: 56, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(Theme.font(15, .semibold))
                            Text([c.source == "stash" ? "StashDB" : "ThePornDB", c.birth, c.country].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12)).foregroundStyle(Theme.muted)
                            if !c.aliases.isEmpty { Text(c.aliases).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1) }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle(linkTo == nil ? "إضافة من المصادر" : "ربط بمصدر")
        .onAppear { if q.isEmpty { q = initial.isEmpty ? (linkTo.flatMap { model.performer($0)?.name } ?? "") : initial } }
    }

    @MainActor func search() async {
        busy = true; msg = "البحث في StashDB وThePornDB…"; results = []
        async let s = (try? await StashDB.search(q)) ?? []
        async let t = (try? await TPDB.search(q)) ?? []
        let all = (await s) + (await t)
        results = all.filter(\.adult)   // بوابة +18 قبل عرض أي صورة
        let hidden = all.count - results.count
        msg = results.isEmpty ? "لا نتائج (تأكد من مفاتيح المصادر في «المزيد»)" : "\(results.count) نتيجة" + (hidden > 0 ? " · \(hidden) مستبعدة (أقل من 18 أو تاريخ غير صالح)" : "")
        busy = false
    }

    @MainActor func pick(_ c: Candidate) async {
        if let pid = linkTo, let p = model.performer(pid) {
            var ch: JSONObject = [:]
            if c.source == "stash" { ch["stashIds"] = .array(Array(Set(p.stashIds + [c.id])).map { .string($0) }); if p.stashId.isEmpty { ch["stashId"] = .string(c.id) } }
            else { ch["pdbIds"] = .array(Array(Set(p.pdbIds + [c.id])).map { .string($0) }); if p.pdbId.isEmpty { ch["pdbId"] = .string(c.id) } }
            if p.birth.isEmpty && !c.birth.isEmpty { ch["birth"] = .string(c.birth) }
            model.save(p.with(ch))
            model.toast = await model.refreshFromSources(model.performer(pid)!)
            dismiss(); return
        }
        if model.performers.contains(where: { norm($0.name) == norm(c.name) }) { msg = "موجودة في مكتبتك مسبقًا"; return }
        let id = "p-" + UUID().uuidString.lowercased()
        var r: JSONObject = ["id": .string(id), "name": .string(c.name), "aliases": .string(c.aliases), "birth": .string(c.birth), "country": .string(c.country),
                             "source": .string(c.source == "stash" ? "StashDB" : "ThePornDB"), "added": .double(Date().timeIntervalSince1970 * 1000)]
        if c.source == "stash" { r["stashId"] = .string(c.id) } else { r["pdbId"] = .string(c.id) }
        if let h = c.height { r["height"] = .int(Int64(h)) }
        if !c.image.isEmpty { r["photos"] = [.string(c.image)]; r["thumb"] = .string(c.image) }
        guard model.save(Performer(r)) else { msg = "رُفضت (العمر أقل من 18 أو التاريخ غير صالح)"; return }
        model.toast = await model.refreshFromSources(model.performer(id)!)
        dismiss()
    }
}
