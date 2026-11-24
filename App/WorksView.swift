import SwiftUI
import FavCore

/// الأعمال (أولية): الأعمال موحّدة عبر الممثلات، بتبويبات: الأحدث / للمشاهدة / القادمة / شاهدتها / الأعلى تقييمًا.
struct WorksView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.latest
    @State private var query = ""

    enum Tab: String, CaseIterable, Identifiable {
        case latest = "الأحدث", queue = "للمشاهدة", upcoming = "القادمة", seen = "شاهدتها", top = "الأعلى تقييمًا"
        var id: String { rawValue }
    }

    var items: [FavCore.WorkGroup] {
        let q = norm(query)
        let now = Date()
        var l = model.works.filter { g in
            if !q.isEmpty && !Self.matches(g, q) { return false }
            switch tab {
            case .latest: return !g.isUpcoming(now: now)
            case .queue: return g.q && !g.seen
            case .upcoming: return g.isUpcoming(now: now)
            case .seen: return g.seen
            case .top: return g.r > 0
            }
        }
        switch tab {
        case .upcoming: l.sort { $0.date < $1.date }
        case .seen: l.sort { $0.wd > $1.wd }
        case .top: l.sort { $0.r > $1.r }
        default: l.sort { $0.date > $1.date }
        }
        return l
    }

    static func matches(_ g: FavCore.WorkGroup, _ q: String) -> Bool {
        if norm(g.t).contains(q) || norm(g.s).contains(q) { return true }
        return g.who.contains(where: { norm($0.name).contains(q) })
    }

    var body: some View {
        let l = items
        List {
            Picker("", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            Section("\(l.count) عمل") {
                ForEach(l.prefix(400)) { WorkRow(g: $0).listRowBackground(Theme.surface) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("الأعمال")
        .searchable(text: $query, prompt: "عنوان، استوديو، ممثلة…")
        .overlay { if model.works.isEmpty { EmptyStateView(icon: "film", title: "لا أعمال بعد", message: "تظهر هنا أعمال ممثلاتك بعد الاستيراد.") } }
    }
}

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
            VStack(alignment: .leading, spacing: 3) {
                Text(g.t).font(Theme.font(15, .semibold)).lineLimit(2)
                Text(meta)
                    .font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if g.r > 0 { Stars(value: Double(g.r), size: 9) }
            if g.seen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok) }
            else if g.q { Image(systemName: "bookmark.fill").foregroundStyle(Theme.gold) }
        }
        .padding(.vertical, 4)
    }
}
