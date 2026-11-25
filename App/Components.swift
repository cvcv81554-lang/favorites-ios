import SwiftUI
import FavCore

/// عنوان قسم مع زر «عرض الكل» اختياري.
struct SectionHeader: View {
    let title: String; var trailing: String? = nil; var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(Theme.font(17, .bold))
            Spacer()
            if let trailing, let action { Button(trailing, action: action).font(Theme.font(13)) }
        }
    }
}

/// رقاقة اختيار.
struct Chip: View {
    let text: String; var on = false; var icon: String? = nil; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { if let icon { Image(systemName: icon).font(.system(size: 11)) }; Text(text).font(Theme.font(13, on ? .semibold : .regular)) }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Theme.gold.opacity(0.22) : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.gold : Theme.line))
        }.buttonStyle(.plain)
    }
}

/// صف رقائق أفقي.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { content }.padding(.horizontal, 16).padding(.vertical, 4) } }
}

/// تخطيط ينساب أسطرًا (للوسوم).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320; var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > w { x = 0; y += row + spacing; row = 0 }; x += z.width + spacing; row = max(row, z.height) }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX
        var y = b.minY
        var row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }; s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += z.width + spacing; row = max(row, z.height) }
    }
}

/// صورة دائرية لممثلة.
struct Avatar: View {
    let p: Performer; var size: CGFloat = 44
    var body: some View {
        Group { if p.cover.isEmpty { ZStack { Theme.surface; Text(String(p.name.prefix(1))).font(Theme.font(size * 0.4, .bold)) } } else { PhotoView(ref: p.cover) } }
            .frame(width: size, height: size).clipShape(Circle())
    }
}

/// بطاقة ممثلة صغيرة لرف أفقي.
struct MiniPerformer: View {
    let p: Performer; var caption: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PhotoView(ref: p.cover).frame(width: 120, height: 160).clipShape(RoundedRectangle(cornerRadius: 14))
            Text(p.name).font(Theme.font(13, .semibold)).lineLimit(1)
            if let caption { Text(caption).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1) }
        }.frame(width: 120)
    }
}

/// رف أفقي من الممثلات.
struct PerformerShelf: View {
    let title: String; let items: [Performer]; var caption: (Performer) -> String? = { _ in nil }
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Theme.font(17, .bold)).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) { ForEach(items.prefix(14)) { p in NavigationLink(value: Route.performer(p.id)) { MiniPerformer(p: p, caption: caption(p)) }.buttonStyle(.plain) } }
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}

/// صف عمل في القوائم.
struct WorkRow: View {
    let g: FavCore.WorkGroup
    var meta: String {
        var parts: [String] = [g.who.prefix(2).map { $0.name }.joined(separator: "، "), g.s]
        if !g.date.isEmpty { parts.append(String(g.date.prefix(4))) }
        if g.du > 0 { parts.append("\(g.du) د") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 12) {
            PhotoView(ref: g.p).frame(width: 96, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(g.t).font(Theme.font(14.5, .semibold)).lineLimit(2)
                Text(meta).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if g.r > 0 { Stars(value: Double(g.r), size: 9) }
                if g.seen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok) } else if g.q { Image(systemName: "bookmark.fill").foregroundStyle(Theme.gold) }
                if let d = daysUntil(g.d), d >= 0, g.isUpcoming() { Text(d == 0 ? "اليوم" : "بعد \(d) يوم").font(Theme.font(11)).foregroundStyle(Theme.copper) }
            }
        }
        .padding(.vertical, 3)
    }
}

func daysUntil(_ d: String) -> Int? {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
    guard d.count == 10, let x = f.date(from: d) else { return nil }
    return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: x).day
}

/// شريط قيمة (0..max) مع عنوان.
struct BarRow: View {
    let label: String; let value: Double; var max: Double = 1; var text: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Theme.font(13)).frame(width: 130, alignment: .leading).lineLimit(1)
            ProgressView(value: Swift.min(Swift.max(value / (max == 0 ? 1 : max), 0), 1)).tint(Theme.gold)
            Text(text ?? String(format: "%.1f", value)).font(Theme.font(12)).foregroundStyle(Theme.muted).frame(minWidth: 34, alignment: .trailing)
        }
    }
}

/// شارة ثقة.
struct ConfidenceBadge: View {
    let value: Double
    var body: some View {
        let l = value >= 0.7 ? "ثقة عالية" : value >= 0.4 ? "ثقة متوسطة" : "ثقة منخفضة"
        Text(l).font(Theme.font(11, .semibold)).padding(.horizontal, 8).padding(.vertical, 2)
            .background((value >= 0.7 ? Theme.ok : value >= 0.4 ? Theme.gold : Theme.rose).opacity(0.2), in: Capsule())
    }
}

/// مربع رقم.
struct StatTile: View {
    let value: String; let label: String; var sub: String? = nil; var subColor: Color = Theme.muted
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.font(24, .bold)).foregroundStyle(Theme.gold)
            Text(label).font(Theme.font(12)).foregroundStyle(Theme.muted)
            if let sub { Text(sub).font(Theme.font(11)).foregroundStyle(subColor) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// مسارات التنقل داخل التطبيق.
enum Route: Hashable {
    case performer(String), work(String), candidate(RecCand), studio(String), tag(String)
    case journal, stats, tools, find, reels, network, stash, missing(String?), faces, facesAlbum(String), intelligence, sources(String?), link(String)
}

/// وجهات التنقل الموحدة.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { r in
            switch r {
            case .performer(let id): PerformerScreen(id: id)
            case .work(let k): WorkSheetView(key: k)
            case .candidate(let c): CandidateScreen(c: c)
            case .studio(let s): FilteredWorksView(title: s, filter: { norm($0.s) == norm(s) })
            case .tag(let t): FilteredWorksView(title: "#\(t)", filter: { $0.tg.contains { norm($0) == norm(t) } })
            case .journal: JournalView()
            case .stats: StatsView()
            case .tools: ToolsView()
            case .find: FindView()
            case .reels: ReelsView()
            case .network: NetworkView()
            case .stash: StashLibraryView()
            case .missing(let pid): MissingView(performerId: pid)
            case .faces: FaceSearchView()
            case .facesAlbum(let pid): FaceAlbumView(performerId: pid)
            case .intelligence: IntelligenceView()
            case .sources(let q): SourceSearchView(initial: q ?? "", linkTo: nil)
            case .link(let pid): SourceSearchView(initial: "", linkTo: pid)
            }
        }
    }
}
extension View { func routes() -> some View { modifier(RouteDestinations()) } }
