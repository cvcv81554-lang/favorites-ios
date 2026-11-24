import SwiftUI
import CoreText
import FavCore

@main
struct FavoritesApp: App {
    @State private var model = AppModel()

    init() { Theme.registerFonts() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .font(Theme.font(16))
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
    }
}

/// حالة التطبيق: المخزن المحلي والسجلات المحمّلة. كل شيء على الجهاز.
@Observable
final class AppModel {
    let store: Store
    private(set) var performers: [Performer] = []
    private(set) var works: [FavCore.WorkGroup] = []
    private(set) var lists: [JSONObject] = []
    private(set) var wlists: [JSONObject] = []
    var loadError: String?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Favorites", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var dir = base
        var v = URLResourceValues(); v.isExcludedFromBackup = true   // بياناتك تبقى على جهازك: خارج نسخ iCloud
        try? dir.setResourceValues(v)
        do { store = try Store(directory: base) }
        catch { fatalError("تعذّر فتح قاعدة البيانات: \(error)") }
        reload()
    }

    func reload() {
        performers = store.loadAll().filter { !$0.isMinor }   // بوابة +18 عند العرض أيضًا
        works = groupWorks(performers)
        lists = (store.kv("lists")?.array ?? []).compactMap { $0.object }
        wlists = (store.kv("wlists")?.array ?? []).compactMap { $0.object }
    }

    func save(_ p: Performer) {
        do { try store.save([p]); reload() } catch { loadError = error.localizedDescription }
    }

    func performer(_ id: String) -> Performer? { performers.first { $0.id == id } }
    func listName(_ id: String) -> String { lists.first { $0["id"]?.string == id }?["name"]?.text ?? id }
}
