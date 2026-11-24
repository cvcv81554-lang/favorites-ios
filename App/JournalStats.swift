import SwiftUI
import Charts
import FavCore

let arMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]

/// «يومياتي»: ملخص الشهر، الأهداف والمراحل، وتقويم المشاهدة.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var month = Calendar.current.dateComponents([.year, .month], from: Date())
    @State private var goal = 0
    @State private var editGoal = false
    @State private var goalText = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("ملخص الشهر").tag(0); Text("الأهداف").tag(1); Text("التقويم").tag(2) }.pickerStyle(.segmented).padding()
            ScrollView { VStack(alignment: .leading, spacing: 14) { if tab == 0 { monthTab } else if tab == 1 { goalsTab } else { calendarTab } }.padding(16) }
        }
        .background(Theme.bg).navigationTitle("يومياتي")
        .onAppear { goal = model.store.kv("watch_goal")?.int ?? 0 }
        .alert("هدف الشهر", isPresented: $editGoal) {
            TextField("عدد الأعمال (0 = بلا هدف)", text: $goalText).keyboardType(.numberPad)
            Button("حفظ") { goal = min(999, max(0, Int(goalText) ?? 0)); try? model.store.setKV("watch_goal", .int(Int64(goal))) }
            Button("إلغاء", role: .cancel) {}
        }
    }

    var monthTab: some View {
        let y = month.year!, m = month.month!
        let r = monthReview(model.works, model.performers, year: y, month: m)
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.right") }
                Spacer(); Text("\(arMonths[m - 1]) \(y)").font(Theme.font(20, .bold)); Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.left") }.disabled(y == now.year && m == now.month)
            }
            HStack(spacing: 8) {
                StatTile(value: "\(r.watched)", label: "شاهدت", sub: r.prevWatched == 0 && r.watched == 0 ? nil : r.delta == 0 ? "مثل السابق" : r.delta > 0 ? "▲ \(r.delta)" : "▼ \(-r.delta)", subColor: r.delta >= 0 ? Theme.ok : Theme.rose)
                StatTile(value: "\(r.activeDays)", label: "يوم مشاهدة")
                StatTile(value: "\(r.added)", label: "أضفت")
                StatTile(value: r.rated == 0 ? "—" : String(format: "%.1f", r.avgRating), label: "متوسطك")
            }
            if goal > 0 && y == now.year && m == now.month { goalBar(r.watched) }
            if !r.topPerformers.isEmpty {
                SectionHeader(title: "الأكثر مشاهدة")
                ForEach(r.topPerformers, id: \.0.id) { x in NavigationLink(value: Route.performer(x.0.id)) { HStack { Avatar(p: x.0, size: 36); Text(x.0.name); Spacer(); Text("\(x.1)").foregroundStyle(Theme.gold) } }.buttonStyle(.plain) }
            }
            if !r.firstTime.isEmpty { SectionHeader(title: "اكتشافات الشهر (أول مرة)"); FlowLayout { ForEach(r.firstTime) { p in NavigationLink(value: Route.performer(p.id)) { Text(p.name).font(Theme.font(13)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.surface, in: Capsule()) }.buttonStyle(.plain) } } }
            if !r.topStudios.isEmpty { SectionHeader(title: "الاستوديوهات"); ForEach(r.topStudios, id: \.0) { s in BarRow(label: s.0, value: Double(s.1), max: Double(r.topStudios[0].1), text: "\(s.1)") } }
            if !r.topTags.isEmpty { SectionHeader(title: "الطابع الغالب"); FlowLayout { ForEach(r.topTags, id: \.0) { t in Text("\(t.0) · \(t.1)").font(Theme.font(12.5)).padding(.horizontal, 10).padding(.vertical, 5).background(Theme.surface, in: Capsule()) } } }
            if r.bestDayCount > 1 { Text("أنشط يوم: \(r.bestDay) — \(r.bestDayCount) أعمال").font(Theme.font(13)).foregroundStyle(Theme.muted) }
            if r.watched == 0 { Text("لا مشاهدات مسجلة في هذا الشهر").foregroundStyle(Theme.muted) }
        }
    }
    func shift(_ d: Int) { var m = month.month! + d, y = month.year!; if m < 1 { m = 12; y -= 1 }; if m > 12 { m = 1; y += 1 }; month = DateComponents(year: y, month: m) }
    func goalBar(_ cur: Int) -> some View {
        VStack(alignment: .leading) { Text(cur >= goal ? "🎯 حققت هدف الشهر (\(cur)/\(goal))" : "هدف الشهر: \(cur) من \(goal)").font(Theme.font(14, .semibold)); ProgressView(value: min(1, Double(cur) / Double(goal))).tint(Theme.gold) }
    }

    var goalsTab: some View {
        let total = model.works.filter(\.seen).count
        let ms = nextMilestone(total)
        let cur = monthReview(model.works, model.performers, year: Calendar.current.component(.year, from: Date()), month: Calendar.current.component(.month, from: Date())).watched
        let st = streaks(model.works.filter(\.seen).map(\.wd))
        return VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack { Text("هدف الشهر").font(Theme.font(16, .bold)); Spacer(); Button(goal > 0 ? "تغيير" : "حدّد هدفًا") { goalText = goal > 0 ? "\(goal)" : ""; editGoal = true } }
                if goal > 0 { goalBar(cur) } else { Text("حدّد عدد الأعمال التي تريد مشاهدتها كل شهر.").font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            Card {
                Text("المرحلة التالية").font(Theme.font(16, .bold))
                Text("شاهدت \(total) — باقي \(ms.next - total) على \(ms.next)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                ProgressView(value: Double(total - ms.prev) / Double(ms.next - ms.prev)).tint(Theme.gold)
                Text("🔥 سلسلتك الحالية: \(st.current) يوم · الأطول: \(st.best) يوم").font(Theme.font(13)).foregroundStyle(Theme.gold)
            }
            SectionHeader(title: "إكمال أعمال مفضلاتك")
            ForEach(performerMilestones(model.works, model.performers).prefix(40), id: \.p.id) { m in
                NavigationLink(value: Route.performer(m.p.id)) {
                    HStack { Avatar(p: m.p, size: 36); VStack(alignment: .leading) { Text(m.p.name); ProgressView(value: Double(m.seen) / Double(m.total)).tint(Theme.gold) }; Text(m.seen == m.total ? "✓ \(m.total)" : "\(m.seen)/\(m.total)").font(Theme.font(12)) }
                }.buttonStyle(.plain)
            }
        }
    }

    var calendarTab: some View {
        let weeks = 26
        let hm = watchHeatmap(model.works, days: weeks * 7)
        let maxV = max(1, hm.values.max() ?? 1)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 6 - (cal.component(.weekday, from: today) % 7), to: today)!
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: end)!
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(hm.values.reduce(0, +)) عملًا في آخر ستة أشهر · \(hm.count) يوم مشاهدة").font(Theme.font(14, .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { d in
                                let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                                let v = hm[todayStr(day)] ?? 0
                                RoundedRectangle(cornerRadius: 3).fill(day > today ? Color.clear : v == 0 ? Theme.surface : Theme.gold.opacity(0.3 + 0.7 * Double(v) / Double(maxV))).frame(width: 14, height: 14)
                            }
                        }
                    }
                }.environment(\.layoutDirection, .leftToRight)
            }.defaultScrollAnchor(.trailing)
        }
    }
}

/// الإحصائيات وملخص السنة.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: Date())
    var body: some View {
        let ps = model.performers, ws = model.works
        let seenYear = ws.filter { $0.seen && $0.wd.hasPrefix("\(year)") }
        var byMonth = [Int](repeating: 0, count: 12); for g in seenYear { if let m = Int(g.wd.dropFirst(5).prefix(2)) { byMonth[m - 1] += 1 } }
        let hof = hallOfFame(ps, ws, year: year)
        var cc: [String: Int] = [:]; for p in ps where !p.country.isEmpty { cc[p.country.uppercased(), default: 0] += 1 }
        var ages: [String: Int] = ["18–24": 0, "25–29": 0, "30–34": 0, "35–39": 0, "40+": 0]
        for p in ps { guard let a = p.age else { continue }; ages[a < 25 ? "18–24" : a < 30 ? "25–29" : a < 35 ? "30–34" : a < 40 ? "35–39" : "40+", default: 0] += 1 }
        let minutes = seenYear.reduce(0) { $0 + ($1.du > 0 ? $1.du : 30) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("السنة", selection: $year) { ForEach((2015...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu)
                HStack(spacing: 8) { StatTile(value: "\(seenYear.count)", label: "شاهدت"); StatTile(value: "\(minutes / 60) س", label: "وقت المشاهدة"); StatTile(value: "\(hof.performers.count)", label: "أضفت (مقيّمات)") }
                Chart(0..<12, id: \.self) { m in BarMark(x: .value("الشهر", arMonths[m]), y: .value("العدد", byMonth[m])).foregroundStyle(Theme.gold) }.frame(height: 160)
                if !hof.performers.isEmpty { SectionHeader(title: "قاعة المشاهير \(year)"); ForEach(hof.performers.prefix(5)) { p in HStack { Avatar(p: p, size: 34); Text(p.name); Spacer(); Stars(value: p.rating, size: 10) } } }
                if !hof.works.isEmpty { SectionHeader(title: "أعمال العام"); ForEach(hof.works.prefix(5)) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) }.buttonStyle(.plain) } }
                if !hof.studios.isEmpty { SectionHeader(title: "استوديوهات العام"); ForEach(hof.studios, id: \.0) { s in BarRow(label: s.0, value: s.1, max: 5, text: String(format: "%.1f (%d)", s.1, s.2)) } }
                SectionHeader(title: "مكتبتك")
                HStack(spacing: 8) { StatTile(value: "\(ps.count)", label: "ممثلة"); StatTile(value: "\(ps.filter(\.fav).count)", label: "مفضلة"); StatTile(value: String(format: "%.1f", ps.filter { $0.rating > 0 }.map(\.rating).reduce(0, +) / Double(max(1, ps.filter { $0.rating > 0 }.count))), label: "متوسط التقييم") }
                SectionHeader(title: "البلدان")
                ForEach(cc.sorted { $0.value > $1.value }.prefix(8), id: \.key) { e in BarRow(label: e.key, value: Double(e.value), max: Double(cc.values.max() ?? 1), text: "\(e.value)") }
                SectionHeader(title: "الأعمار")
                ForEach(["18–24", "25–29", "30–34", "35–39", "40+"], id: \.self) { k in BarRow(label: k, value: Double(ages[k] ?? 0), max: Double(max(1, ages.values.max() ?? 1)), text: "\(ages[k] ?? 0)") }
                SectionHeader(title: "توزيع تقييماتك")
                Chart(Array(stride(from: 0.5, through: 5.0, by: 0.5)), id: \.self) { r in BarMark(x: .value("التقييم", String(r)), y: .value("العدد", ps.filter { $0.rating == r }.count)).foregroundStyle(Theme.copper) }.frame(height: 140)
            }.padding(16)
        }.background(Theme.bg).navigationTitle("الإحصائيات وملخص السنة")
    }
}
