import SwiftUI
import LocalAuthentication
import CryptoKit
import BackgroundTasks
import UserNotifications
import WidgetKit
import FavCore

/// الخصوصية: قفل برمز (مُجزّأ بملح) أو Face ID، غطاء عند مغادرة التطبيق، تمويه الصور، والوضع الخاص للويدجت.
@Observable
final class Privacy {
    var locked = true   // مقفل حتى تُحمَّل الإعدادات
    var hasPin = false
    var bio = true
    var cover = true
    var blur = false
    var widgetPrivate = false
    var autoLockMin = 0
    var showCover = false
    private var leftAt: Date?
    private weak var store: Store?
    private var fails = 0, lockedUntil: Date?

    func load(_ s: Store) {
        store = s
        let p = s.kv("privacy")?.object ?? [:]
        bio = p["bio"]?.bool ?? true; cover = p["cover"]?.bool ?? true; blur = p["blur"]?.bool ?? false
        widgetPrivate = p["wp"]?.bool ?? false; autoLockMin = p["al"]?.int ?? 0
        hasPin = !Keychain.get("pin2").isEmpty
        locked = hasPin
        // عداد المحاولات الخاطئة ومهلة القفل محفوظان في Keychain: إغلاق التطبيق لا يصفّرهما
        let f = Keychain.get("pin_fails").split(separator: ":").map(String.init)
        fails = Int(f.first ?? "") ?? 0
        if f.count > 1, let t = Double(f[1]), t > Date().timeIntervalSince1970 { lockedUntil = Date(timeIntervalSince1970: t) }
    }
    func persist() {
        try? store?.setKV("privacy", ["bio": .bool(bio), "cover": .bool(cover), "blur": .bool(blur), "wp": .bool(widgetPrivate || hasPin), "al": .int(Int64(autoLockMin))])
    }

    static func hash(_ pin: String, salt: String) -> String { SHA256.hash(data: Data("\(salt)|\(pin)".utf8)).map { String(format: "%02x", $0) }.joined() }

    func setPin(_ pin: String) {
        if pin.isEmpty { Keychain.set("pin2", ""); hasPin = false; persist(); return }
        let salt = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        Keychain.set("pin2", "\(salt):\(Self.hash(pin, salt: salt)):\(pin.count)")
        hasPin = true; widgetPrivate = true; persist()
    }
    var pinLength: Int { Int(Keychain.get("pin2").split(separator: ":").last ?? "4") ?? 4 }

    /// التحقق: بعد 5 محاولات خاطئة قفل مؤقت يتزايد (حتى 5 دقائق).
    func check(_ pin: String) -> Bool {
        if let u = lockedUntil, u > Date() { return false }
        let parts = Keychain.get("pin2").split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return false }   // رمز تالف ⇒ لا فتح
        if Self.hash(pin, salt: parts[0]) == parts[1] { fails = 0; lockedUntil = nil; saveFails(); locked = false; return true }
        fails += 1
        if fails >= 5 { lockedUntil = Date().addingTimeInterval(Double(min(300, 30 * (fails - 4)))) }
        saveFails()
        return false
    }
    private func saveFails() { Keychain.set("pin_fails", "\(fails):\(lockedUntil?.timeIntervalSince1970 ?? 0)") }
    var waitSeconds: Int { max(0, Int((lockedUntil ?? .distantPast).timeIntervalSinceNow.rounded(.up))) }

    func biometric() {
        guard hasPin, bio else { return }
        let c = LAContext(); var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        c.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "فتح المفضلة") { ok, _ in
            if ok { DispatchQueue.main.async { self.locked = false } }
        }
    }

    func onPhase(_ p: ScenePhase) {
        switch p {
        case .active:
            showCover = false
            if hasPin, let t = leftAt, Date().timeIntervalSince(t) >= Double(autoLockMin * 60) { locked = true }
            leftAt = nil
        case .inactive: if cover || hasPin { showCover = true }
        case .background: if cover || hasPin { showCover = true }; if leftAt == nil { leftAt = Date() }
        @unknown default: break
        }
    }
}

/// بوابة القفل والغطاء حول التطبيق كله.
struct LockGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content
    @State private var entry = ""
    @State private var wrong = false
    var body: some View {
        let pv = model.privacy
        ZStack {
            content
            if pv.locked { lock(pv).transition(.opacity) }
            else if pv.showCover { ZStack { Theme.bg.ignoresSafeArea(); Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Theme.gold) } }
            if let t = model.toast {
                VStack { Spacer(); Text(t).font(Theme.font(14)).padding(12).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 90) }
                    .task(id: t) { try? await Task.sleep(nanoseconds: 2_600_000_000); if model.toast == t { model.toast = nil } }
            }
            if let b = model.busy {
                VStack { HStack(spacing: 10) { ProgressView(); Text(b).font(Theme.font(13)).lineLimit(1) }.padding(10).background(.ultraThinMaterial, in: Capsule()); Spacer() }.padding(.top, 8)
            }
        }
        .onAppear { if pv.locked { pv.biometric() } }
    }

    func lock(_ pv: Privacy) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Theme.gold)
            Text(pv.waitSeconds > 0 ? "انتظر \(pv.waitSeconds) ثانية" : "أدخل الرمز").font(Theme.font(18, .semibold))
            HStack(spacing: 14) { ForEach(0..<pv.pinLength, id: \.self) { i in Circle().fill(i < entry.count ? Theme.gold : Theme.surface).frame(width: 14, height: 14) } }
                .modifier(Shake(on: wrong))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78)), count: 3), spacing: 14) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "bio", "0", "del"], id: \.self) { k in key(k, pv) }
            }
            .environment(\.layoutDirection, .leftToRight)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg.ignoresSafeArea())
    }

    @ViewBuilder func key(_ k: String, _ pv: Privacy) -> some View {
        Button {
            if k == "del" { if !entry.isEmpty { entry.removeLast() }; return }
            if k == "bio" { pv.biometric(); return }
            entry += k; wrong = false
            if entry.count == pv.pinLength { if !pv.check(entry) { wrong = true }; entry = "" }
        } label: {
            Group {
                if k == "del" { Image(systemName: "delete.left") } else if k == "bio" { Image(systemName: "faceid") } else { Text(k).font(Theme.font(28, .medium)) }
            }
            .frame(width: 72, height: 72).background(Theme.surface, in: Circle())
        }.buttonStyle(.plain)
    }
}

struct Shake: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { content.offset(x: on ? 8 : 0).animation(on ? .default.repeatCount(3, autoreverses: true).speed(4) : .default, value: on) }
}

/// المهام الخلفية (iOS يقرر التوقيت — بلا ضمان): فحص أعمال جديدة لمفضلاتك وإشعار عام بلا أسماء.
enum Background {
    static let refreshId = "com.favlib.favoritesnative.refresh"
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshId, using: nil) { task in
            schedule()
            let work = Task {
                let n = await checkNewWorks()
                if n > 0 { await notify("أعمال جديدة لمفضلاتك", "\(n) عمل جديد — افتح المفضلة") }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: refreshId); r.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }
    static func notify(_ title: String, _ body: String) async {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    /// أول صفحة من أعمال كل مفضلة مرتبطة (حتى 12) — تُدمج بلا تكرار ولا حذف.
    static func checkNewWorks() async -> Int {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Favorites", isDirectory: true)
        guard let store = try? Store(directory: base) else { return 0 }
        Net.shared.keys = { Keychain.get($0.rawValue) }
        var added = 0, changed: [Performer] = []
        for p in store.loadAll().filter({ $0.fav && !$0.isMinor }).prefix(12) {
            var incoming: [JSONObject] = []
            if let s = p.stashIds.first, let w = try? await StashDB.scenes(s, maxPages: 1) { incoming += w }
            if let t = p.pdbIds.first, let w = try? await TPDB.scenes(t, maxPages: 1) { incoming += w }
            let m = mergeWorks(p.works, incoming)
            if m.added > 0 { added += m.added; changed.append(p.with(["works": .array(m.list.map { .object($0) })])) }
        }
        if !changed.isEmpty { _ = try? store.save(changed) }
        return added
    }
    /// تذكير بإصدارات المفضلات (مساء اليوم السابق) — إشعارات محلية بلا إنترنت، بنص عام.
    static func scheduleReleaseReminders(_ works: [FavCore.WorkGroup]) async {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: (0..<40).map { "rel\($0)" })
        let soon = works.filter { $0.isUpcoming() && !$0.d.isEmpty && $0.who.contains(where: \.fav) }.sorted { $0.d < $1.d }.prefix(40)
        for (i, g) in soon.enumerated() {
            guard let y = Int(g.d.prefix(4)), let m = Int(g.d.dropFirst(5).prefix(2)), let d = Int(g.d.dropFirst(8).prefix(2)) else { continue }
            var dc = DateComponents(year: y, month: m, day: d, hour: 20); dc.day = d - 1
            let content = UNMutableNotificationContent(); content.title = "إصدار غدًا"; content.body = "عمل جديد لإحدى مفضلاتك يصدر غدًا"
            try? await c.add(UNNotificationRequest(identifier: "rel\(i)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)))
        }
    }
}

/// بيانات الويدجت في حاوية مجموعة التطبيق (إن توفرت): «نجمة اليوم» وأقرب إصدار. الوضع الخاص بلا صورة ولا اسم.
enum WidgetBridge {
    static let group = "group.com.favlib.favoritesnative"
    static func publish(_ m: AppModel) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let priv = m.privacy.widgetPrivate || m.privacy.hasPin
        let star = HomeView.starOfDay(m.performers)
        let next = m.works.filter { $0.isUpcoming() && !$0.d.isEmpty && $0.who.contains(where: \.fav) }.min { $0.d < $1.d }
        var o: JSONObject = ["private": .bool(priv), "at": .double(Date().timeIntervalSince1970)]
        if !priv, let s = star {
            o["star"] = .string(s.name)
            if let ref = s.photos.first(where: { $0.hasPrefix("file:") }), let u = m.store.photoURL(ref), let img = UIImage(contentsOfFile: u.path),
               let small = img.preparingThumbnail(of: CGSize(width: 400, height: 400))?.jpegData(compressionQuality: 0.8) {
                try? small.write(to: dir.appendingPathComponent("star.jpg"))
            }
        }
        if let n = next { o["next"] = .string(priv ? "إصدار قادم" : n.t); o["nextDate"] = .string(n.d) }
        try? JSONValue.object(o).encoded().write(to: dir.appendingPathComponent("widget.json"))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
