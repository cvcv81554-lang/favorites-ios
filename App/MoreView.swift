import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import FavCore

struct MoreView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("الأقسام") {
                NavigationLink(value: Route.intelligence) { Label("ذكاء المفضلة", systemImage: "brain.head.profile") }
                NavigationLink(value: Route.reels) { Label("مقاطع", systemImage: "play.rectangle.on.rectangle") }
                NavigationLink(value: Route.find) { Label("بحث شامل وباللغة الطبيعية", systemImage: "magnifyingglass") }
                NavigationLink(value: Route.journal) { Label("يومياتي", systemImage: "book") }
                NavigationLink(value: Route.stats) { Label("الإحصائيات وملخص السنة", systemImage: "chart.bar") }
                NavigationLink(value: Route.tools) { Label("الأدوات", systemImage: "wrench.and.screwdriver") }
                NavigationLink(value: Route.faces) { Label("ابحث بصورة (الوجه)", systemImage: "face.smiling") }
                NavigationLink(value: Route.stash) { Label("مكتبة Stash", systemImage: "server.rack") }
                NavigationLink(value: Route.missing(nil)) { Label("الأعمال الناقصة", systemImage: "rectangle.badge.xmark") }
                NavigationLink(value: Route.network) { Label("الشبكة والمقاطع", systemImage: "network") }
            }
            Section("بياناتك") {
                NavigationLink { ImportView() } label: { Label("استيراد نسخة احتياطية", systemImage: "square.and.arrow.down") }
                NavigationLink { ExportView() } label: { Label("تصدير نسخة احتياطية", systemImage: "square.and.arrow.up") }
                if model.store.hasRollbackPoint { NavigationLink { RollbackView() } label: { Label("التراجع عن آخر استيراد", systemImage: "arrow.uturn.backward") } }
                backupReminder
            }
            Section("المصادر") { NavigationLink { KeysView() } label: { Label("مفاتيح ThePornDB وStashDB", systemImage: "key") } }
            Section("الخصوصية والأمان") {
                NavigationLink { PrivacySettingsView() } label: { Label("القفل والإخفاء", systemImage: "lock") }
                NavigationLink { NotificationsView() } label: { Label("التنبيهات", systemImage: "bell") }
                row("بوابة +18", "أي سجل تاريخه يقول أقل من 18 أو تاريخه غير صالح يُرفض في الحفظ والاستيراد والعرض والبحث.")
                row("بياناتك على جهازك", "لا حسابات ولا خوادم. القاعدة والصور داخل التطبيق وخارج نسخ iCloud.")
            }
            Section("عن التطبيق") {
                row("المفضلة — النسخة الأصلية للآيفون", "Swift + SwiftUI. التطبيق السابق يبقى صالحًا حتى تتحقق من النقل.")
                row("الإصدار", version)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("المزيد")
    }
    var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(v) (\(b))"
    }
    @ViewBuilder var backupReminder: some View {
        let last = model.store.kv("last_backup")?.number ?? 0
        let days = last == 0 ? -1 : Int((Date().timeIntervalSince1970 - last) / 86400)
        if days < 0 || days >= 14 {
            Text(days < 0 ? "لم تصدّر نسخة احتياطية بعد — بياناتك على هذا الجهاز فقط. صدّر نسخة مشفّرة واحفظها في «الملفات»." : "آخر نسخة احتياطية قبل \(days) يومًا — صدّر نسخة جديدة.")
                .font(Theme.font(12.5)).foregroundStyle(Theme.gold)
        }
    }
    func row(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(t).font(Theme.font(15, .semibold)); Text(s).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
    }
}

/// مفاتيح API في سلسلة مفاتيح الجهاز (Keychain) — لا تُصدَّر ولا تُرسل إلا للمصدر نفسه.
struct KeysView: View {
    @State private var tpdb = Keychain.get(APIKeyName.tpdb.rawValue)
    @State private var stash = Keychain.get(APIKeyName.stash.rawValue)
    @State private var msg: [String: String] = [:]
    var body: some View {
        List {
            Section("ThePornDB") {
                SecureField("API Token", text: $tpdb).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("حفظ واختبار") { Keychain.set(APIKeyName.tpdb.rawValue, tpdb.trimmingCharacters(in: .whitespacesAndNewlines)); Task { await test("t") } }
                if let m = msg["t"] { Text(m).font(Theme.font(12.5)).foregroundStyle(m.hasPrefix("✓") ? Theme.ok : Theme.rose) }
                Text("من theporndb.net ← حسابك ← API Tokens.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            Section("StashDB") {
                SecureField("API Key", text: $stash).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("حفظ واختبار") { Keychain.set(APIKeyName.stash.rawValue, stash.trimmingCharacters(in: .whitespacesAndNewlines)); Task { await test("s") } }
                if let m = msg["s"] { Text(m).font(Theme.font(12.5)).foregroundStyle(m.hasPrefix("✓") ? Theme.ok : Theme.rose) }
                Text("من stashdb.org ← حسابك ← API Key.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
        }.navigationTitle("المفاتيح")
    }
    @MainActor func test(_ w: String) async {
        msg[w] = "اختبار…"
        do {
            if w == "t" { try await TPDB.test(key: Keychain.get(APIKeyName.tpdb.rawValue)) } else { try await StashDB.test(key: Keychain.get(APIKeyName.stash.rawValue)) }
            msg[w] = "✓ يعمل"
        } catch { msg[w] = error.localizedDescription }
    }
}

struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newPin = ""
    @State private var setting = false
    var body: some View {
        @Bindable var pv = model.privacy
        List {
            Section("الرمز السري") {
                if pv.hasPin {
                    Text("الرمز مفعّل (\(pv.pinLength) أرقام)").foregroundStyle(Theme.ok)
                    Button("تغيير الرمز") { setting = true }
                    Button("إلغاء الرمز", role: .destructive) { Keychain.set("pin2", ""); pv.hasPin = false; pv.persist() }
                    Toggle("فتح بـ Face ID", isOn: $pv.bio).onChange(of: pv.bio) { _, _ in pv.persist() }
                    Picker("قفل تلقائي بعد", selection: $pv.autoLockMin) { Text("فورًا").tag(0); Text("دقيقة").tag(1); Text("5 دقائق").tag(5); Text("15 دقيقة").tag(15) }
                        .onChange(of: pv.autoLockMin) { _, _ in pv.persist() }
                } else { Button("تعيين رمز سري") { setting = true } }
            }
            Section("الإخفاء") {
                Toggle("غطاء عند مبدّل التطبيقات", isOn: $pv.cover).onChange(of: pv.cover) { _, _ in pv.persist() }
                Toggle("تمويه الصور", isOn: $pv.blur).onChange(of: pv.blur) { _, _ in pv.persist() }
                Toggle("الويدجت بلا صور ولا أسماء", isOn: $pv.widgetPrivate).onChange(of: pv.widgetPrivate) { _, _ in pv.persist(); WidgetBridge.publish(model) }
            }
        }
        .navigationTitle("القفل والإخفاء")
        .alert("رمز جديد (4–8 أرقام)", isPresented: $setting) {
            SecureField("الرمز", text: $newPin).keyboardType(.numberPad)
            Button("حفظ") { let d = newPin.filter { $0.isNumber }; if (4...8).contains(d.count) { pv.setPin(d) }; newPin = "" }
            Button("إلغاء", role: .cancel) { newPin = "" }
        }
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @State private var status = ""
    var body: some View {
        List {
            Button("السماح بالتنبيهات") { Task { await allow() } }
            if !status.isEmpty { Text(status).foregroundStyle(Theme.muted) }
            Toggle("تذكير قبل إصدار أعمال مفضلاتك بيوم", isOn: Binding(get: { model.pref("notify_release")?.bool ?? true }, set: { model.setPref("notify_release", .bool($0)) }))
            Toggle("فحص الأعمال الجديدة في الخلفية", isOn: Binding(get: { model.pref("notify_new")?.bool ?? true }, set: { model.setPref("notify_new", .bool($0)) }))
            Button("جدولة تذكيرات الإصدارات الآن") { Task { await Background.scheduleReleaseReminders(model.works); status = "✓ جُدولت" } }
            Text("iOS يقرر توقيت الفحص في الخلفية؛ قد يتأخر أو لا يحدث إن لم تفتح التطبيق كثيرًا.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
        }.navigationTitle("التنبيهات")
    }
    @MainActor func allow() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        status = ok ? "✓ مسموح" : "مرفوض — فعّلها من إعدادات iOS"
    }
}

/// الاستيراد: اختيار الملف ⇒ كلمة المرور (إن كان مشفّرًا) ⇒ معاينة بالأرقام قبل أي كتابة ⇒ نقطة استرجاع ⇒ استيراد ⇒ تقرير تحقق.
struct ImportView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var encryptedText: String?
    @State private var password = ""
    @State private var busy: String?
    @State private var plan: Backup.Plan?
    @State private var report: MigrationReport?
    @State private var error: String?

    var body: some View {
        List {
            if let report { reportSection(report) }
            else if let plan { previewSection(plan) }
            else if encryptedText != nil { passwordSection }
            else {
                Section {
                    Text("يقرأ ملفات «المفضلة» و«المفضلة 2» كما هي: JSON العادي والمشفّر (.vkte). لا يُحذف شيء، ويُحدَّث السجل فقط إن كان في الملف أحدث، وتُرفض أي ممثلة تاريخها يقول أقل من 18.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Button { picking = true } label: { Label("اختر ملف النسخة الاحتياطية", systemImage: "doc.badge.plus") }
                }
            }
            if let busy { Section { HStack { ProgressView(); Text(busy).foregroundStyle(Theme.muted) } } }
            if let error { Section { Text(error).foregroundStyle(Theme.rose) } }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("استيراد")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .data, .item]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    var passwordSection: some View {
        Section("الملف مشفّر") {
            SecureField("كلمة المرور", text: $password).textContentType(.password)
            Button("فك التشفير") {
                guard let t = encryptedText else { return }
                let pw = password
                run("فك التشفير…") { try parse(Backup.decrypt(t, password: pw)) }
            }.disabled(password.count < 8)
        }
    }

    func previewSection(_ p: Backup.Plan) -> some View {
        Section("معاينة قبل الاستيراد") {
            line("ممثلات جديدة", p.added)
            line("تُحدَّث (الملف أحدث)", p.updated)
            line("تُكمل صورها فقط", p.photosFixed)
            line("تبقى كما هي (عندك أحدث)", p.kept)
            line("رُفضت (أقل من 18 أو تاريخ غير صالح)", p.file.minorsSkipped)
            line("سجلات غير صالحة", p.file.invalid)
            line("قوائم جديدة", p.newLists + p.newWlists)
            Text("لا يُحذف أي سجل موجود. تُحفظ نقطة استرجاع قبل الاستيراد للتراجع.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            Button("استيراد الآن") { apply(p) }.font(Theme.font(16, .semibold))
            Button("إلغاء", role: .cancel) { plan = nil }
        }
    }

    func reportSection(_ r: MigrationReport) -> some View {
        Section(r.ok ? "✓ اكتمل الاستيراد وتحققنا منه" : "اكتمل الاستيراد مع ملاحظات") {
            ForEach(r.summary.indices, id: \.self) { i in HStack { Text(r.summary[i].0); Spacer(); Text(r.summary[i].1).foregroundStyle(Theme.gold) } }
            Text("تحققنا من \(r.checked) سجل: الاسم، التقييم، المعايير، القوائم، الأعمال والمشاهدة، الصور، الملاحظات — ولم يختفِ أي سجل كان موجودًا.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted)
            ForEach(r.problems, id: \.self) { Text($0).foregroundStyle(Theme.rose) }
            NavigationLink("التراجع عن هذا الاستيراد") { RollbackView() }
        }
    }

    func line(_ k: String, _ v: Int) -> some View { HStack { Text(k); Spacer(); Text("\(v)").foregroundStyle(Theme.gold) } }

    func load(_ url: URL) {
        error = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { error = "تعذّرت قراءة الملف"; return }
        if Backup.isEncrypted(text) { encryptedText = text; return }
        run("قراءة الملف…") { try parse(text) }
    }

    /// القراءة والتخطيط خارج خيط الواجهة.
    func parse(_ text: String) throws -> Backup.Plan {
        let f = try Backup.parse(text)
        let current = Dictionary(model.store.loadAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Backup.plan(f, current: current, lists: model.lists, wlists: model.wlists)
    }

    func run(_ label: String, _ work: @escaping () throws -> Backup.Plan) {
        busy = label; error = nil
        Task.detached {
            do { let p = try work(); await MainActor.run { plan = p; encryptedText = nil; busy = nil } }
            catch { await MainActor.run { self.error = error.localizedDescription; busy = nil } }
        }
    }

    func apply(_ p: Backup.Plan) {
        busy = "استيراد…"
        let store = model.store
        Task.detached {
            do {
                let r = try store.apply(p)
                await MainActor.run { report = r; plan = nil; busy = nil; model.reload() }
            } catch {
                await MainActor.run { self.error = "تعذّر الاستيراد: \(error.localizedDescription) — يمكنك التراجع من «المزيد»."; busy = nil; model.reload() }
            }
        }
    }
}

struct RollbackView: View {
    @Environment(AppModel.self) private var model
    @State private var done = false
    @State private var confirm = false
    var body: some View {
        List {
            Text("يعيد مكتبتك كما كانت قبل آخر استيراد تمامًا. ما أضفته أو عدّلته بعد الاستيراد سيضيع.").foregroundStyle(Theme.muted)
            if done { Text("✓ أُعيدت المكتبة لما قبل الاستيراد").foregroundStyle(Theme.ok) }
            else { Button("التراجع عن آخر استيراد", role: .destructive) { confirm = true } }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("التراجع")
        .confirmationDialog("متأكد؟", isPresented: $confirm) {
            Button("نعم، تراجع", role: .destructive) { try? model.store.rollback(); model.reload(); done = true }
        }
    }
}

/// التصدير: بنفس الصيغة (يُقرأ في كل نسخ التطبيق)، عادي أو مشفّر بكلمة مرور. مفاتيح API والرمز السري لا تُصدَّر أبدًا.
struct ExportView: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var file: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            Section("نسخة عادية (JSON)") { Button("إنشاء النسخة") { make(encrypted: false) } }
            Section("نسخة مشفّرة (.vkte)") {
                SecureField("كلمة مرور (8 أحرف على الأقل)", text: $password)
                Button("إنشاء نسخة مشفّرة") { make(encrypted: true) }.disabled(password.count < 8)
                Text("احفظها في «الملفات» أو iCloud Drive. لا يمكن فتحها بدون كلمة المرور.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            if busy { ProgressView() }
            if let file { Section { ShareLink(item: file) { Label("حفظ / مشاركة \(file.lastPathComponent)", systemImage: "square.and.arrow.up") } } }
            if let error { Text(error).foregroundStyle(Theme.rose) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("تصدير")
    }

    func make(encrypted: Bool) {
        busy = true; error = nil; file = nil
        let store = model.store, items = model.store.loadAll(), lists = model.lists, wlists = model.wlists, pw = password
        let prefs = (store.kv("prefs")?.object ?? [:]).compactMapValues { $0.string }
        Task.detached {
            do {
                var text = try Backup.export(items, lists: lists, wlists: wlists, prefs: prefs) { store.photoDataURI($0) }
                if encrypted { text = try Backup.encrypt(text, password: pw) }
                let day = todayStr()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(encrypted ? "favorites-backup-\(day).vkte" : "favorites-backup-\(day).json")
                try Data(text.utf8).write(to: url, options: .atomic)
                await MainActor.run { file = url; busy = false; try? store.setKV("last_backup", .double(Date().timeIntervalSince1970)) }
            } catch { await MainActor.run { self.error = error.localizedDescription; busy = false } }
        }
    }
}
