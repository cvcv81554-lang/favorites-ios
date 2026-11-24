import SwiftUI
import FavCore

/// التنقل الرئيسي: الرئيسية | المكتبة | الأعمال | اكتشف | الاستديو | المزيد.
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView().routes() }.tabItem { Label("الرئيسية", systemImage: "house.fill") }
            NavigationStack { LibraryView().routes() }.tabItem { Label("المكتبة", systemImage: "person.2.fill") }
            NavigationStack { WorksView().routes() }.tabItem { Label("الأعمال", systemImage: "film.stack") }
            NavigationStack { DiscoverView().routes() }.tabItem { Label("اكتشف", systemImage: "sparkles") }
            NavigationStack { StudioView().routes() }.tabItem { Label("الاستديو", systemImage: "photo.on.rectangle.angled") }
            NavigationStack { MoreView().routes() }.tabItem { Label("المزيد", systemImage: "ellipsis.circle") }
        }
    }
}

/// الرئيسية: نجمة اليوم، الأرقام، اختصارات، رفوف، وملاحظات الذكاء.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    /// اختيار يومي ثابت من المفضلات (التقييم 4+) ذوات الصور، وإلا من كل من لها صورة. (نفسه في الويدجت)
    static func starOfDay(_ ps: [Performer], skip: Int = 0) -> Performer? {
        let pool = ps.filter { ($0.fav || $0.rating >= 4) && !$0.cover.isEmpty }
        let all = (pool.count >= 3 ? pool : ps.filter { !$0.cover.isEmpty }).sorted { $0.id < $1.id }
        guard !all.isEmpty else { return nil }
        return all[(Int(Date().timeIntervalSince1970 / 86400) + skip) % all.count]
    }
    @State private var skip = 0

    var body: some View {
        let ps = model.performers, ws = model.works
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let star = Self.starOfDay(ps, skip: skip) { hero(star) }
                else { EmptyStateView(icon: "star.circle", title: "مكتبتك فارغة", message: "استورد نسختك الاحتياطية من «المزيد» ← «استيراد نسخة احتياطية»، أو أضف ممثلة من «المكتبة».").frame(height: 300) }
                HStack(spacing: 8) {
                    StatTile(value: "\(ps.count)", label: "ممثلة"); StatTile(value: "\(ps.filter(\.fav).count)", label: "مفضلة")
                    StatTile(value: "\(ws.count)", label: "عمل"); StatTile(value: "\(ws.filter { $0.isUpcoming() }.count)", label: "قادم")
                }.padding(.horizontal, 16)
                shortcuts
                insightCard
                PerformerShelf(title: "تابعت مؤخرًا", items: recent(ps))
                PerformerShelf(title: "الأعلى تقييمًا", items: ps.filter { $0.rating > 0 }.sorted { $0.rating > $1.rating })
                upcoming(ws)
                PerformerShelf(title: "أعياد ميلاد قريبة", items: upcomingBirthdays(ps).map(\.0)) { p in
                    upcomingBirthdays([p]).first.map { $0.1 == 0 ? "اليوم! تكمل \($0.2)" : "بعد \($0.1) يوم · \($0.2)" }
                }
                PerformerShelf(title: "بانتظار تقييمك", items: ps.filter { $0.rating == 0 })
                PerformerShelf(title: "أُضيفت حديثًا", items: ps.sorted { $0.added > $1.added })
            }
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("الرئيسية")
        .toolbar {
            NavigationLink(value: Route.find) { Image(systemName: "magnifyingglass") }
            NavigationLink(value: Route.reels) { Image(systemName: "play.rectangle.on.rectangle") }
        }
    }

    func recent(_ ps: [Performer]) -> [Performer] { ps.filter { ($0.raw["lastView"]?.number ?? 0) > 0 }.sorted { ($0.raw["lastView"]?.number ?? 0) > ($1.raw["lastView"]?.number ?? 0) } }

    func hero(_ star: Performer) -> some View {
        NavigationLink(value: Route.performer(star.id)) {
            ZStack(alignment: .bottomLeading) {
                PhotoView(ref: star.cover).frame(height: 440).frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("نجمة اليوم").font(Theme.font(13, .semibold)).foregroundStyle(Theme.gold)
                        Text(star.name).font(Theme.font(28, .bold))
                        if star.rating > 0 { Stars(value: star.rating, size: 14) }
                    }
                    Spacer()
                    Button { skip += 1 } label: { Image(systemName: "arrow.triangle.2.circlepath").padding(10).background(.ultraThinMaterial, in: Circle()) }
                }.padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
        }.buttonStyle(.plain)
    }

    var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                link("مقاطع", "play.rectangle.fill", .reels)
                link("يومياتي", "calendar", .journal)
                link("الذكاء", "brain.head.profile", .intelligence)
                link("الإحصائيات", "chart.bar.fill", .stats)
                link("الأدوات", "wrench.and.screwdriver.fill", .tools)
                link("مكتبة Stash", "server.rack", .stash)
            }.padding(.horizontal, 16)
        }
    }
    func link(_ t: String, _ i: String, _ r: Route) -> some View {
        NavigationLink(value: r) {
            Label(t, systemImage: i).font(Theme.font(13, .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }.buttonStyle(.plain)
    }

    @ViewBuilder var insightCard: some View {
        let s = samples(model.performers, model.feats)
        if s.count >= 6, let top = tasteDNA(s).strong.first {
            NavigationLink(value: Route.intelligence) {
                Card {
                    Label("من ذكاء المفضلة", systemImage: "brain.head.profile").font(Theme.font(13, .semibold)).foregroundStyle(Theme.gold)
                    Text("أقوى ما يرفع تقييمك: \(top.label)").font(Theme.font(15, .semibold))
                    Text("\(top.n) ممثلة · متوسطك لها \(String(format: "%.1f", top.mean))").font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }.buttonStyle(.plain).padding(.horizontal, 16)
        }
    }

    @ViewBuilder func upcoming(_ ws: [FavCore.WorkGroup]) -> some View {
        let l = ws.filter { $0.isUpcoming() && $0.who.contains(where: \.fav) }.sorted { $0.date < $1.date }.prefix(8)
        if !l.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("إصدارات قادمة لمفضلاتك").font(Theme.font(17, .bold))
                ForEach(Array(l)) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.buttonStyle(.plain) }
            }.padding(.horizontal, 16)
        }
    }
}
