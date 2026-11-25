import SwiftUI
import FavCore

/// الاستديو: صور ممثلاتك الرسمية ولقطات مشاهدهن من المصادر — فرز بالسحب، ألبومات ذكية، ألبومات الحقب، وإزالة المكرر بالبصمة المرئية.
/// قاعدة مستقلة (kv: studio) — لا تدخل النسخ الاحتياطية.
struct StudioImg: Identifiable, Hashable {
    let id: String, url: String, pid: String, src: String, kind: String
    var year: Int?
    var like = false
    var hide = false
    var seen = false
    var found: Double
    var dh: UInt64? = nil
    var json: JSONValue {
        var o: JSONObject = ["url": .string(url), "pid": .string(pid), "src": .string(src), "kind": .string(kind), "like": .bool(like), "hide": .bool(hide), "seen": .bool(seen), "found": .double(found)]
        if let year { o["year"] = .int(Int64(year)) }; if let dh { o["dh"] = .string(String(dh, radix: 16)) }
        return .object(o)
    }
    init(id: String, url: String, pid: String, src: String, kind: String, year: Int?, found: Double) { self.id = id; self.url = url; self.pid = pid; self.src = src; self.kind = kind; self.year = year; self.found = found }
    init?(id: String, _ j: JSONValue) {
        guard let url = j["url"]?.string, let pid = j["pid"]?.string else { return nil }
        self.init(id: id, url: url, pid: pid, src: j["src"]?.text ?? "", kind: j["kind"]?.text ?? "", year: j["year"]?.int, found: j["found"]?.number ?? 0)
        like = j["like"]?.bool == true; hide = j["hide"]?.bool == true; seen = j["seen"]?.bool == true; dh = j["dh"]?.string.flatMap { UInt64($0, radix: 16) }
    }
}

@Observable
final class StudioState {
    var imgs: [String: StudioImg] = [:]
    var msg = ""
    var running = false
    func load(_ s: Store) { imgs = Dictionary(uniqueKeysWithValues: (s.kv("studio")?.object ?? [:]).compactMap { k, v in StudioImg(id: k, v).map { (k, $0) } }) }
    func save(_ s: Store) { try? s.setKV("studio", .object(imgs.mapValues(\.json))) }
    static func key(_ u: String) -> String { var h: UInt64 = 1469598103934665603; for b in u.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }; return "i" + String(h, radix: 36) }

    /// البحث عن صور جديدة: المفضلات المرتبطة (القاصر مستبعد قبل أي طلب).
    @MainActor func discover(_ m: AppModel) async {
        running = true; defer { running = false; save(m.store) }
        let now = Date().timeIntervalSince1970
        var added = 0
        for p in m.performers.filter({ ($0.fav || $0.rating >= 4) && !$0.isMinor }).prefix(40) {
            msg = "صور \(p.name)…"
            var found: [(String, String, String, Int?)] = []
            if let s = p.stashIds.first, let d = try? await StashDB.performer(s) { found += StashDB.images(d).map { ($0, "stash", "portrait", nil) } }
            if let t = p.pdbIds.first, let d = try? await TPDB.performer(t) { found += TPDB.images(d).map { ($0, "tpdb", "promo", nil) } }
            for w in p.works { if let u = w["p"]?.string, safeHttps(.string(u)) { found.append((u, w["is"] != nil ? "stashs" : "tpdbs", "still", Int((w["d"]?.text ?? w["y"]?.text ?? "").prefix(4)))) } }
            for (u, src, kind, y) in found {
                let k = Self.key(u + "|" + p.id); if imgs[k] != nil { continue }
                imgs[k] = StudioImg(id: k, url: u, pid: p.id, src: src, kind: kind, year: y, found: now); added += 1
            }
        }
        msg = "أُضيفت \(added) صورة جديدة"
    }

    /// إزالة المكرر: بصمة مرئية (dHash 64 بت) لكل صورة؛ المتطابقة لنفس الممثلة (فرق ≤ 4) تُخفى ويبقى الأوضح.
    @MainActor func dedupe(_ m: AppModel) async {
        running = true; defer { running = false; save(m.store) }
        var n = 0
        var hidden = 0
        for k in Array(imgs.keys) {
            guard var x = imgs[k], x.dh == nil, !x.hide else { continue }
            n += 1; if n % 10 == 0 { msg = "بصمات الصور \(n)…" }
            guard let u = URL(string: x.url), let res = try? await URLSession.shared.data(from: u), let img = UIImage(data: res.0) else { continue }
            x.dh = dHash(img); imgs[k] = x
        }
        for (_, l) in Dictionary(grouping: imgs.values.filter { !$0.hide && $0.dh != nil }, by: \.pid) {
            var kept: [StudioImg] = []
            for x in l.sorted(by: { $0.like && !$1.like }) {
                if kept.contains(where: { ($0.dh! ^ x.dh!).nonzeroBitCount <= 4 }) { imgs[x.id]?.hide = true; hidden += 1 } else { kept.append(x) }
            }
        }
        msg = "أُخفيت \(hidden) صورة مكررة"
    }
}

/// بصمة فرق مرئية 9×8 (dHash).
func dHash(_ img: UIImage) -> UInt64? {
    let w = 9, h = 8
    guard let cg = img.cgImage, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let px = data.bindMemory(to: UInt8.self, capacity: w * h)
    var v: UInt64 = 0
    var bit: UInt64 = 0
    for y in 0..<h { for x in 0..<(w - 1) { if px[y * w + x] > px[y * w + x + 1] { v |= 1 << bit }; bit += 1 } }
    return v
}

struct StudioView: View {
    @Environment(AppModel.self) private var model
    @State private var st = StudioState()
    @State private var tab = 0
    @State private var sorting = false

    var visible: [StudioImg] {
        let ids = Set(model.performers.filter { !$0.isMinor }.map(\.id))
        return st.imgs.values.filter { !$0.hide && ids.contains($0.pid) }.sorted { $0.found > $1.found }
    }

    var body: some View {
        let all = visible
        let shown: [StudioImg] = tab == 0 ? all.filter { !$0.seen } : tab == 1 ? all : all.filter(\.like)
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("جديد (\(all.filter { !$0.seen }.count))").tag(0); Text("الكل").tag(1); Text("المفضلة").tag(2); Text("الألبومات").tag(3) }.pickerStyle(.segmented).padding(16)
            if tab == 3 { albums(all) } else { grid(shown) }
        }
        .background(Theme.bg)
        .navigationTitle("الاستديو")
        .toolbar {
            Menu {
                Button { Task { await st.discover(model) } } label: { Label("البحث عن صور جديدة", systemImage: "sparkle.magnifyingglass") }
                Button { Task { await st.dedupe(model) } } label: { Label("إزالة المكرر (بصمة مرئية)", systemImage: "square.on.square.dashed") }
            } label: { st.running ? AnyView(ProgressView()) : AnyView(Image(systemName: "ellipsis.circle")) }
            if !all.filter({ !$0.seen }).isEmpty { Button("فرز") { sorting = true } }
        }
        .safeAreaInset(edge: .bottom) { if !st.msg.isEmpty { Text(st.msg).font(Theme.font(12.5)).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 6) } }
        .fullScreenCover(isPresented: $sorting) { SwipeSorter(st: st, items: all.filter { !$0.seen }) }
        .onAppear { if st.imgs.isEmpty { st.load(model.store) } }
        .overlay { if st.imgs.isEmpty && !st.running { EmptyStateView(icon: "photo.stack", title: "الاستديو فارغ", message: "اضغط ⋯ ← «البحث عن صور جديدة» لجلب صور مفضلاتك الرسمية من المصادر.") } }
    }

    @ViewBuilder func cell(_ x: StudioImg) -> some View {
        let photo = PhotoView(ref: x.url).frame(height: 160).frame(maxWidth: .infinity).clipped()
        photo
            .overlay(alignment: .bottomTrailing) { if x.like { Image(systemName: "heart.fill").foregroundStyle(Theme.rose).padding(6) } }
            .contextMenu { cellMenu(x) }
    }
    @ViewBuilder func cellMenu(_ x: StudioImg) -> some View {
        Button(x.like ? "إلغاء الإعجاب" : "إعجاب") { toggleLike(x.id) }
        Button("إضافة لصورها") { addToPerformer(x) }
        Button("إخفاء", role: .destructive) { hide(x.id) }
    }
    func toggleLike(_ id: String) { st.imgs[id]?.like.toggle(); st.save(model.store) }
    func hide(_ id: String) { st.imgs[id]?.hide = true; st.save(model.store) }

    func grid(_ l: [StudioImg]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(l.prefix(600)) { x in
                    cell(x)
                }
            }.padding(.horizontal, 4)
        }
    }

    func albumGroups(_ all: [StudioImg]) -> [(String, [StudioImg])] {
        var g: [(String, [StudioImg])] = []
        g.append(("صور شخصية", all.filter { x in x.kind == "portrait" }))
        g.append(("ملصقات", all.filter { x in x.kind == "promo" }))
        g.append(("لقطات مشاهد", all.filter { x in x.kind == "still" }))
        g.append(("StashDB", all.filter { x in x.src.hasPrefix("stash") }))
        g.append(("ThePornDB", all.filter { x in x.src.hasPrefix("tpdb") }))
        g.append(("لم تُشاهد", all.filter { x in !x.seen }))
        var byYear: [Int: [StudioImg]] = [:]
        for x in all { if let y = x.year { byYear[y, default: []].append(x) } }
        for y in byYear.keys.sorted(by: >) { g.append(("حقبة \(y)", byYear[y] ?? [])) }
        return g
    }

    func albums(_ all: [StudioImg]) -> some View {
        let groups = albumGroups(all)
        return List {
            Section("ألبومات ذكية وحقب") {
                ForEach(groups.filter { !$0.1.isEmpty }, id: \.0) { g in NavigationLink { grid(g.1).navigationTitle(g.0) } label: { HStack { Text(g.0); Spacer(); Text("\(g.1.count)").foregroundStyle(Theme.muted) } } }
            }
            Section("حسب الممثلة") {
                ForEach(Dictionary(grouping: all, by: \.pid).sorted { $0.value.count > $1.value.count }, id: \.key) { e in
                    NavigationLink { grid(e.value).navigationTitle(model.performer(e.key)?.name ?? "") } label: { HStack { Text(model.performer(e.key)?.name ?? e.key); Spacer(); Text("\(e.value.count)").foregroundStyle(Theme.muted) } }
                }
            }
        }.scrollContentBackground(.hidden)
    }

    func addToPerformer(_ x: StudioImg) {
        guard let p = model.performer(x.pid), p.photos.count < 30, !p.photos.contains(x.url) else { return }
        model.save(p.with(["photos": .array((p.photos + [x.url]).map { .string($0) })])); model.toast = "أُضيفت لصور \(p.name)"
    }
}

/// الفرز بالسحب: يمين = إعجاب، يسار = تخطٍّ، أعلى = إخفاء، مع تراجع.
struct SwipeSorter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let st: StudioState; let items: [StudioImg]
    @State private var i = 0
    @State private var offset: CGSize = .zero
    @State private var history: [(String, StudioImg)] = []
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if i < items.count {
                let x = items[i]
                VStack(spacing: 10) {
                    Text(model.performer(x.pid)?.name ?? "").font(Theme.font(17, .bold))
                    PhotoView(ref: x.url).scaledToFit().frame(maxHeight: 560).clipShape(RoundedRectangle(cornerRadius: 18))
                        .offset(offset).rotationEffect(.degrees(Double(offset.width / 20)))
                        .gesture(DragGesture().onChanged { offset = $0.translation }.onEnded { v in
                            if v.translation.width > 120 { act(x, "like") } else if v.translation.width < -120 { act(x, "skip") } else if v.translation.height < -140 { act(x, "hide") }
                            withAnimation { offset = .zero }
                        })
                    HStack(spacing: 30) {
                        Button { act(x, "skip") } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 46)) }
                        Button { act(x, "hide") } label: { Image(systemName: "eye.slash.circle.fill").font(.system(size: 40)) }.tint(.gray)
                        Button { act(x, "like") } label: { Image(systemName: "heart.circle.fill").font(.system(size: 46)) }.tint(Theme.rose)
                    }
                    Text("\(i + 1) / \(items.count)").font(Theme.font(12)).foregroundStyle(Theme.muted)
                }.padding()
            } else { EmptyStateView(icon: "checkmark.circle", title: "انتهى الفرز", message: "") }
            VStack { HStack { Button("تم") { st.save(model.store); dismiss() }; Spacer(); Button("تراجع") { undo() }.disabled(history.isEmpty) }.padding(); Spacer() }
        }
    }
    func act(_ x: StudioImg, _ a: String) {
        history.append((x.id, x))
        st.imgs[x.id]?.seen = true
        if a == "like" { st.imgs[x.id]?.like = true }
        if a == "hide" { st.imgs[x.id]?.hide = true }
        i += 1
    }
    func undo() { guard let last = history.popLast() else { return }; st.imgs[last.0] = last.1; i = max(0, i - 1) }
}
