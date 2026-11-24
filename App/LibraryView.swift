import SwiftUI
import FavCore

/// المكتبة: كل الممثلات — بحث، ترتيب، المفضلة، والقوائم.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var sort = Sort.recent
    @State private var favOnly = false
    @State private var list: String? = nil

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "آخر تعديل", rating = "التقييم", name = "الاسم", added = "المضافة حديثًا", works = "عدد الأعمال", youngest = "الأصغر"
        var id: String { rawValue }
    }

    var filtered: [Performer] {
        let q = norm(query)
        var l = model.performers.filter { p in
            if favOnly && !p.fav { return false }
            if let list, !p.lists.contains(list) { return false }
            if q.isEmpty { return true }
            return [p.name, p.aliases, p.country, p.notes].contains { norm($0).contains(q) } || p.tags.contains { norm($0).contains(q) }
                || p.works.contains { norm($0["t"]?.text ?? "").contains(q) || norm($0["s"]?.text ?? "").contains(q) }
        }
        switch sort {
        case .recent: l.sort { $0.updated > $1.updated }
        case .rating: l.sort { $0.rating > $1.rating }
        case .name: l.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .added: l.sort { $0.added > $1.added }
        case .works: l.sort { $0.works.count > $1.works.count }
        case .youngest: l.sort { $0.birth > $1.birth }
        }
        return l
    }

    var body: some View {
        let items = filtered
        ScrollView {
            if model.performers.isEmpty {
                EmptyStateView(icon: "person.2", title: "لا ممثلات بعد", message: "استورد نسختك الاحتياطية من «المزيد».").frame(height: 400)
            } else {
                filterBar
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(items) { p in NavigationLink(value: p.id) { PerformerCard(p: p) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                if items.isEmpty { Text("لا نتائج").foregroundStyle(Theme.muted).padding(30) }
            }
        }
        .background(Theme.bg)
        .navigationTitle("المكتبة")
        .searchable(text: $query, prompt: "اسم، اسم آخر، بلد، وسم، عمل…")
        .navigationDestination(for: String.self) { PerformerView(id: $0) }
        .toolbar {
            Menu {
                Picker("الترتيب", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }
        }
    }

    var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(filtered.count) ممثلة").font(Theme.font(13)).foregroundStyle(Theme.muted)
                chip("المفضلة ★", on: favOnly) { favOnly.toggle() }
                ForEach(model.lists.indices, id: \.self) { i in
                    let id = model.lists[i]["id"]?.string ?? ""
                    chip(model.lists[i]["name"]?.text ?? id, on: list == id) { list = list == id ? nil : id }
                }
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    func chip(_ t: String, on: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(t).font(Theme.font(13, on ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Theme.gold.opacity(0.22) : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.gold : Theme.line))
        }.buttonStyle(.plain)
    }
}

struct PerformerCard: View {
    let p: Performer
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PhotoView(ref: p.cover).frame(height: 210).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                if p.fav { Image(systemName: "star.fill").foregroundStyle(Theme.gold).padding(8).background(.black.opacity(0.45), in: Circle()).padding(6) }
            }
            Text(p.name).font(Theme.font(15, .semibold)).lineLimit(1)
            HStack {
                if p.rating > 0 { Stars(value: p.rating, size: 10) }
                Spacer()
                Text(p.country).font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
    }
}
