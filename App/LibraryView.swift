import SwiftUI
import FavCore

/// المكتبة: كل الممثلات — بحث، ترتيب، فلاتر ذكية، قوائم، عرض شبكة/قائمة، وتحديد متعدد.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var sort = Sort.recent
    @State private var favOnly = false
    @State private var list: String?
    @State private var smart: Smart?
    @State private var grid = true
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var adding = false
    @State private var manageLists = false
    @State private var confirmDelete = false

    enum Sort: String, CaseIterable, Identifiable { case recent = "آخر تعديل", rating = "التقييم", name = "الاسم", added = "المضافة حديثًا", works = "عدد الأعمال", youngest = "الأصغر", elo = "المواجهات"; var id: String { rawValue } }
    enum Smart: String, CaseIterable, Identifiable {
        case top = "4.5+", unrated = "بلا تقييم", unseen = "لها أعمال لم أشاهدها", upcoming = "لها جديد قادم", recent30 = "أُضيفت خلال 30 يومًا", nophoto = "بلا صور", noworks = "بلا أعمال", nobirth = "بلا تاريخ ميلاد", bday = "عيد ميلادها هذا الشهر", unlinked = "غير مرتبطة بمصدر"
        var id: String { rawValue }
    }

    func passes(_ p: Performer, _ s: Smart) -> Bool {
        switch s {
        case .top: return p.rating >= 4.5
        case .unrated: return p.rating == 0
        case .unseen: return p.works.contains { $0["w"]?.isOn != true }
        case .upcoming: return model.works.contains { g in g.isUpcoming() && g.who.contains { $0.id == p.id } }
        case .recent30: return Double(p.added) > (Date().timeIntervalSince1970 - 30 * 86400) * 1000
        case .nophoto: return p.photos.isEmpty
        case .noworks: return p.works.isEmpty
        case .nobirth: return p.birth.isEmpty
        case .bday: return p.birth.count >= 7 && Int(p.birth.dropFirst(5).prefix(2)) == Calendar.current.component(.month, from: Date())
        case .unlinked: return p.stashIds.isEmpty && p.pdbIds.isEmpty
        }
    }

    var filtered: [Performer] {
        let q = norm(query)
        var l = model.performers.filter { p in
            if favOnly && !p.fav { return false }
            if let list, !p.lists.contains(list) { return false }
            if let smart, !passes(p, smart) { return false }
            if q.isEmpty { return true }
            if [p.name, p.aliases, p.country, p.notes].contains(where: { norm($0).contains(q) }) || p.tags.contains(where: { norm($0).contains(q) }) { return true }
            return p.works.contains { norm($0["t"]?.text ?? "").contains(q) || norm($0["s"]?.text ?? "").contains(q) }
        }
        switch sort {
        case .recent: l.sort { $0.updated > $1.updated }
        case .rating: l.sort { $0.rating > $1.rating }
        case .name: l.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .added: l.sort { $0.added > $1.added }
        case .works: l.sort { $0.works.count > $1.works.count }
        case .youngest: l.sort { $0.birth > $1.birth }
        case .elo: l.sort { $0.elo > $1.elo }
        }
        return l
    }

    var body: some View {
        let items = filtered
        ScrollView {
            VStack(spacing: 10) {
                filterBar(items.count)
                if model.performers.isEmpty {
                    EmptyStateView(icon: "person.2", title: "لا ممثلات بعد", message: "أضف ممثلة (+) أو استورد نسختك الاحتياطية من «المزيد».").frame(height: 380)
                } else if grid {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(items) { p in cell(p) { PerformerCard(p: p) } }
                    }.padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 8) { ForEach(items) { p in cell(p) { PerformerRow(p: p) } } }.padding(.horizontal, 16)
                }
                if items.isEmpty && !model.performers.isEmpty { Text("لا نتائج").foregroundStyle(Theme.muted).padding(30) }
            }.padding(.bottom, 24)
        }
        .background(Theme.bg)
        .navigationTitle("المكتبة")
        .searchable(text: $query, prompt: "اسم، اسم آخر، بلد، وسم، عمل…")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { selecting.toggle(); selected = [] } label: { Text(selecting ? "تم" : "تحديد") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("الترتيب", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
                    Button(grid ? "عرض قائمة" : "عرض شبكة") { grid.toggle() }
                    Button("القوائم…") { manageLists = true }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .safeAreaInset(edge: .bottom) { if selecting && !selected.isEmpty { bulkBar } }
        .sheet(isPresented: $adding) { NavigationStack { AddChooser() } }
        .sheet(isPresented: $manageLists) { NavigationStack { ListsManager() } }
        .confirmationDialog("حذف \(selected.count) ممثلة؟ لا يمكن التراجع (إلا من نسخة احتياطية).", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { for id in selected { model.delete(id) }; selected = []; selecting = false }
        }
    }

    @ViewBuilder func cell<C: View>(_ p: Performer, @ViewBuilder _ c: () -> C) -> some View {
        if selecting {
            Button { if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) } } label: {
                c().overlay(alignment: .topLeading) { Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(Theme.gold).padding(8) }
            }.buttonStyle(.plain)
        } else { NavigationLink(value: Route.performer(p.id)) { c() }.buttonStyle(.plain) }
    }

    func filterBar(_ n: Int) -> some View {
        ChipRow {
            Text("\(n) ممثلة").font(Theme.font(13)).foregroundStyle(Theme.muted)
            Chip(text: "المفضلة ★", on: favOnly) { favOnly.toggle() }
            Menu { Button("الكل") { smart = nil }; ForEach(Smart.allCases) { s in Button(s.rawValue) { smart = s } } } label: {
                Text(smart?.rawValue ?? "قوائم ذكية").font(Theme.font(13)).padding(.horizontal, 12).padding(.vertical, 6).background(smart == nil ? Theme.surface : Theme.gold.opacity(0.22), in: Capsule())
            }
            ForEach(model.lists.indices, id: \.self) { i in
                let id = model.lists[i]["id"]?.string ?? ""
                Chip(text: model.lists[i]["name"]?.text ?? id, on: list == id) { list = list == id ? nil : id }
            }
        }
    }

    var bulkBar: some View {
        HStack(spacing: 14) {
            Text("\(selected.count)").font(Theme.font(15, .bold))
            Button("مفضلة") { model.save(selected.compactMap { model.performer($0) }.map { $0.with(["fav": true]) }) }
            Menu("إلى قائمة") { ForEach(model.lists.indices, id: \.self) { i in
                let id = model.lists[i]["id"]?.string ?? ""
                Button(model.lists[i]["name"]?.text ?? id) {
                    model.save(selected.compactMap { model.performer($0) }.map { p in p.with(["lists": .array(Array(Set(p.lists + [id])).map { .string($0) })]) })
                }
            } }
            Spacer()
            Button("حذف", role: .destructive) { confirmDelete = true }
        }
        .font(Theme.font(14)).padding(14).background(.ultraThinMaterial)
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
            HStack { if p.rating > 0 { Stars(value: p.rating, size: 10) }; Spacer(); Text(p.country).font(Theme.font(12)).foregroundStyle(Theme.muted) }
        }
    }
}

struct PerformerRow: View {
    let p: Performer
    var body: some View {
        HStack(spacing: 12) {
            Avatar(p: p, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(Theme.font(15, .semibold))
                Text([p.age.map { "\($0) سنة" } ?? "", p.country, "\(p.works.count) عمل", p.fav ? "★" : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            Spacer(); if p.rating > 0 { Stars(value: p.rating, size: 10) }
        }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// إضافة: من المصادر (موصى به) أو يدويًا.
struct AddChooser: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            NavigationLink { SourceSearchView(initial: "", linkTo: nil) } label: { Label("من المصادر (StashDB + ThePornDB)", systemImage: "magnifyingglass") }
            NavigationLink { EditPerformerView(existing: nil) } label: { Label("إدخال يدوي", systemImage: "square.and.pencil") }
        }
        .navigationTitle("إضافة ممثلة").toolbar { Button("إغلاق") { dismiss() } }
    }
}

/// إدارة القوائم: إنشاء، إعادة تسمية، حذف (الأعضاء يبقون).
struct ListsManager: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    var body: some View {
        List {
            Section("قائمة جديدة") {
                HStack { TextField("اسم القائمة", text: $newName); Button("إضافة") {
                    let n = newName.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
                    model.setLists(model.lists + [["id": .string("L" + UUID().uuidString.prefix(8)), "name": .string(n)]]); newName = ""
                }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            Section("قوائمي") {
                ForEach(model.lists.indices, id: \.self) { i in
                    let id = model.lists[i]["id"]?.string ?? ""
                    HStack { Text(model.lists[i]["name"]?.text ?? id); Spacer(); Text("\(model.performers.filter { $0.lists.contains(id) }.count)").foregroundStyle(Theme.muted) }
                }
                .onDelete { idx in model.setLists(model.lists.enumerated().filter { !idx.contains($0.offset) }.map(\.element)) }
            }
        }
        .navigationTitle("القوائم").toolbar { Button("تم") { dismiss() } }
    }
}
