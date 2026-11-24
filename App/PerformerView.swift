import SwiftUI
import FavCore

/// صفحة الممثلة (أولية): صورها، معلوماتها، تقييمها ومعاييرها، وأعمالها.
struct PerformerView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if let p = model.performer(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TabView {
                        ForEach(Array((p.photos.isEmpty ? [p.thumb] : p.photos).enumerated()), id: \.offset) { _, ref in
                            PhotoView(ref: ref).frame(maxWidth: .infinity)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(Theme.font(26, .bold))
                            if !p.aliases.isEmpty { Text(p.aliases).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        Button { model.save(p.with(["fav": .bool(!p.fav)])) } label: {
                            Image(systemName: p.fav ? "star.fill" : "star").font(.system(size: 24)).foregroundStyle(Theme.gold)
                        }
                    }
                    if p.rating > 0 { Stars(value: p.rating, size: 16) }

                    Card {
                        info("العمر", p.age.map { "\($0) سنة" } ?? "غير معروف (غير موثّق)")
                        info("البلد", p.country)
                        info("الطول", p.height.map { "\(Int($0)) سم" } ?? "")
                        info("الأعمال", "\(p.works.count) · شاهدت \(p.watchedCount)")
                        info("المستوى", p.tier)
                    }

                    if !p.criteriaValues.isEmpty {
                        Card {
                            Text("المعايير").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                            ForEach(Performer.criteria.indices, id: \.self) { i in
                                if let v = p.criteriaValues[Performer.criteria[i].0] { bar(Performer.criteria[i].1, v) }
                            }
                        }
                    }
                    if !p.bodyValues.isEmpty {
                        Card {
                            Text("تفاصيل الجسم").font(Theme.font(15, .semibold)).foregroundStyle(Theme.gold)
                            ForEach(Performer.bodyDetails.indices, id: \.self) { i in
                                if let v = p.bodyValues[Performer.bodyDetails[i].0] { bar(Performer.bodyDetails[i].1, v) }
                            }
                        }
                    }
                    if !p.tags.isEmpty || !p.lists.isEmpty {
                        Card {
                            if !p.tags.isEmpty { Text("الوسوم: " + p.tags.joined(separator: "، ")).font(Theme.font(14)) }
                            if !p.lists.isEmpty { Text("القوائم: " + p.lists.map(model.listName).joined(separator: "، ")).font(Theme.font(14)) }
                        }
                    }
                    if !p.notes.isEmpty { Card { Text(p.notes).font(Theme.font(14)) } }

                    let ws = herWorks(p.id)
                    if !ws.isEmpty {
                        Text("أعمالها (\(ws.count))").font(Theme.font(17, .bold)).padding(.top, 6)
                        ForEach(ws) { WorkRow(g: $0) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            EmptyStateView(icon: "person.slash", title: "غير موجودة", message: "")
        }
    }

    func herWorks(_ id: String) -> [FavCore.WorkGroup] {
        let mine: [FavCore.WorkGroup] = model.works.filter { g in g.who.contains(where: { $0.id == id }) }
        return mine.sorted { $0.date > $1.date }
    }

    @ViewBuilder func info(_ k: String, _ v: String) -> some View {
        if !v.isEmpty { HStack { Text(k).foregroundStyle(Theme.muted); Spacer(); Text(v) }.font(Theme.font(14)) }
    }

    func bar(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Theme.font(13)).frame(width: 120, alignment: .leading)
            ProgressView(value: min(max(v / 5, 0), 1)).tint(Theme.gold)
            Text(String(format: "%.1f", v)).font(Theme.font(12)).foregroundStyle(Theme.muted)
        }
    }
}
