import WidgetKit
import SwiftUI

/// ويدجت «المفضلة»: نجمة اليوم والإصدار القادم. يقرأ ملفًا صغيرًا يكتبه التطبيق في مجلد المجموعة المشتركة.
/// في الوضع الخاص (أو مع رمز سري) لا صور ولا أسماء.
struct Entry: TimelineEntry {
    let date: Date
    var priv = true, star = "", next = "", nextDate = ""
    var image: UIImage?
}

struct Provider: TimelineProvider {
    static let group = "group.com.favlib.favoritesnative"
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), priv: false, star: "نجمة اليوم", next: "إصدار قادم") }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(6 * 3600))))
    }
    func read() -> Entry {
        var e = Entry(date: Date())
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group),
              let d = try? Data(contentsOf: dir.appendingPathComponent("widget.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return e }
        e.priv = o["private"] as? Bool ?? true
        e.star = o["star"] as? String ?? ""
        e.next = o["next"] as? String ?? ""
        e.nextDate = o["nextDate"] as? String ?? ""
        if !e.priv { e.image = UIImage(contentsOfFile: dir.appendingPathComponent("star.jpg").path) }
        return e
    }
}

struct WidgetView: View {
    let e: Entry
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = e.image { Image(uiImage: img).resizable().scaledToFill() }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.priv || e.star.isEmpty ? "المفضلة" : e.star).font(.headline).foregroundStyle(.white).lineLimit(1)
                if !e.next.isEmpty { Text("\(e.next) · \(e.nextDate)").font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(2) }
            }.padding(12)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) { Color(red: 0.08, green: 0.07, blue: 0.06) }
    }
}

@main
struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FavoritesWidget", provider: Provider()) { WidgetView(e: $0) }
            .configurationDisplayName("المفضلة")
            .description("نجمة اليوم والإصدار القادم")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}
