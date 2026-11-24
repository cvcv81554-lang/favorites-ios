import SwiftUI
import FavCore

/// التنقل الرئيسي: الرئيسية | المكتبة | الأعمال | اكتشف | الاستديو | المزيد.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("الرئيسية", systemImage: "house.fill") }
            NavigationStack { LibraryView() }.tabItem { Label("المكتبة", systemImage: "person.2.fill") }
            NavigationStack { WorksView() }.tabItem { Label("الأعمال", systemImage: "film.stack") }
            NavigationStack { PendingSection(title: "اكتشف", icon: "sparkles", stage: "تحليل الذوق والاقتراحات من StashDB وThePornDB — تُنقل في المرحلة القادمة.") }
                .tabItem { Label("اكتشف", systemImage: "sparkles") }
            NavigationStack { PendingSection(title: "الاستديو", icon: "photo.on.rectangle.angled", stage: "صور الممثلات الرسمية والألبومات والفرز بالسحب — تُنقل في مرحلة قادمة.") }
                .tabItem { Label("الاستديو", systemImage: "photo.on.rectangle.angled") }
            NavigationStack { MoreView() }.tabItem { Label("المزيد", systemImage: "ellipsis.circle") }
        }
    }
}

/// قسم لم يُنقل بعد: يقول ذلك بوضوح (لا أزرار شكلية).
struct PendingSection: View {
    let title: String, icon: String, stage: String
    var body: some View {
        EmptyStateView(icon: icon, title: "\(title) — قيد النقل", message: stage)
            .background(Theme.bg)
            .navigationTitle(title)
    }
}

/// الرئيسية (أولية): «نجمة اليوم» وأرقام المكتبة.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let star = starOfDay {
                    NavigationLink(value: star.id) {
                        ZStack(alignment: .bottomLeading) {
                            PhotoView(ref: star.cover).frame(height: 420).frame(maxWidth: .infinity)
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("نجمة اليوم").font(Theme.font(13, .semibold)).foregroundStyle(Theme.gold)
                                Text(star.name).font(Theme.font(26, .bold))
                                if star.rating > 0 { Stars(value: star.rating, size: 14) }
                            }.padding(18)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                } else {
                    EmptyStateView(icon: "star.circle", title: "مكتبتك فارغة", message: "استورد نسختك الاحتياطية من «المزيد» ← «استيراد نسخة احتياطية».").frame(height: 300)
                }
                HStack(spacing: 10) {
                    stat("\(model.performers.count)", "ممثلة")
                    stat("\(model.performers.filter(\.fav).count)", "مفضلة")
                    stat("\(model.works.count)", "عمل")
                    stat("\(model.works.filter(\.seen).count)", "شاهدتها")
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("الرئيسية")
        .navigationDestination(for: String.self) { PerformerView(id: $0) }
    }

    /// اختيار يومي ثابت من المفضلات (التقييم 4+)، وإلا من كل من لها صورة.
    var starOfDay: Performer? {
        let pool = model.performers.filter { ($0.fav || $0.rating >= 4) && !$0.cover.isEmpty }
        let all = pool.count >= 3 ? pool : model.performers.filter { !$0.cover.isEmpty }
        guard !all.isEmpty else { return nil }
        let day = Int(Date().timeIntervalSince1970 / 86400)
        return all.sorted { $0.id < $1.id }[day % all.count]
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(Theme.font(20, .bold)).foregroundStyle(Theme.gold); Text(l).font(Theme.font(12)).foregroundStyle(Theme.muted) }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
