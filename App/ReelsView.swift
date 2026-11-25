import SwiftUI
import AVKit
import WebKit
import FavCore

/// إعدادات «مقاطع» (kv: reels_cfg) — نفس مفاتيح التطبيق السابق.
struct ReelsCfg {
    var sound = true
    var hqOnly = true
    var server = true
    var auto = false
    var favTab = false
    var prefetch = true
    var night = true
    var count = 100
    var gb = 3
    var emb: [String] = ["ph", "rt", "ep"]
    init(_ j: JSONValue?) {
        sound = j?["snd"]?.bool ?? true; hqOnly = j?["hq"]?.bool ?? true; server = j?["srv"]?.bool ?? true; auto = j?["auto"]?.bool ?? false
        favTab = j?["ft"]?.bool ?? false; prefetch = j?["pf"]?.bool ?? true; night = j?["night"]?.bool ?? true
        count = j?["n"]?.int ?? 100; gb = j?["gb"]?.int ?? 3; emb = (j?["emb"]?.array ?? [.string("ph"), .string("rt"), .string("ep")]).compactMap { $0.string }
    }
    var json: JSONValue { ["snd": .bool(sound), "hq": .bool(hqOnly), "srv": .bool(server), "auto": .bool(auto), "ft": .bool(favTab), "pf": .bool(prefetch), "night": .bool(night),
                           "n": .int(Int64(count)), "gb": .int(Int64(gb)), "emb": .array(emb.map { .string($0) })] }
}

/// ذاكرة المقاطع على الجهاز (Caches/clips) بحد كلي (افتراضي 3 GB) — الأقدم يُزال أولًا.
enum ClipCache {
    static var dir: URL { let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("clips"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    static func file(_ url: String) -> URL { dir.appendingPathComponent(StudioState.key(url) + ".mp4") }
    static func cached(_ url: String) -> URL? { FileManager.default.fileExists(atPath: file(url).path) ? file(url) : nil }
    static func download(_ url: String) async -> URL? {
        if let c = cached(url) { return c }
        guard let u = URL(string: url), let res = try? await URLSession.shared.download(from: u), ((res.1 as? HTTPURLResponse)?.statusCode ?? 0) < 400 else { return nil }
        try? FileManager.default.moveItem(at: res.0, to: file(url))
        return cached(url)
    }
    static func stats() -> (Int, Int64) {
        let fs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return (fs.count, fs.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) })
    }
    static func prune(limitGB: Int) {
        let fs = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])) ) }
            .sorted { ($0.1?.contentModificationDate ?? .distantPast) < ($1.1?.contentModificationDate ?? .distantPast) }
        var total = fs.reduce(Int64(0)) { $0 + Int64($1.1?.fileSize ?? 0) }
        let limit = Int64(limitGB) << 30
        for (u, v) in fs where total > limit { try? FileManager.default.removeItem(at: u); total -= Int64(v?.fileSize ?? 0) }
    }
}

@Observable
final class ReelsState {
    var feed: [Reel] = []
    var cfg = ReelsCfg(nil)
    var hosts: [String: JSONValue] = [:]
    var quality: [String: [String: Double]] = [:]
    var extras: [String: StashExtra] = [:]
    var msg = ""
    var loading = false

    @MainActor func build(_ m: AppModel, favs: Bool, focus: (String, String)? = nil, seed: UInt64) async {
        loading = true; defer { loading = false }
        cfg = ReelsCfg(m.store.kv("reels_cfg"))
        hosts = m.store.kv("reel_hosts")?.object ?? [:]
        quality = (m.store.kv("reel_quality")?.object ?? [:]).mapValues { ($0.object ?? [:]).compactMapValues { $0.number } }
        let taste = buildWorkTaste(m.works)
        func inFocus(_ g: FavCore.WorkGroup) -> Bool { focus.map { reelFocusMatch(g, kind: $0.0, value: $0.1) } ?? true }
        let fav = favs && focus == nil
        let trailers = rankReels(m.works.filter(inFocus), taste, m.reelSig, favsOnly: fav, seed: seed, n: 200,
                                 playable: { u in hostUsable(self.hosts, u) && qualityOk(self.quality, u, hqOnly: self.cfg.hqOnly) }, isCached: { ClipCache.cached($0) != nil })
        var server: [Reel] = []
        if cfg.server && StashServer.configured {
            msg = "الاتصال بخادم Stash…"
            var map = (m.store.kv("stash_local_map")?.object ?? [:]).compactMapValues { $0.string }
            for p in m.performers where map[p.id] == nil && !p.isMinor { if let l = try? await StashServer.localPerformer(p) { map[p.id] = l } else { map[p.id] = "" }; if map.count > 400 { break } }
            try? m.store.setKV("stash_local_map", .object(map.mapValues { .string($0) }))
            let byLocal = Dictionary(m.performers.compactMap { p in map[p.id].flatMap { $0.isEmpty ? nil : ($0, p) } }, uniquingKeysWith: { a, _ in a })
            if let sc = try? await StashServer.scenes(byLocal: byLocal) {
                for (g, ex) in sc { extras[g.key] = ex }
                var k = 0
                for r in rankReels(sc.map(\.0).filter(inFocus), taste, m.reelSig, favsOnly: fav, seed: seed, n: 200) {
                    let ex = extras[r.g.key]
                    let marks = markerSegments(ex?.markers ?? [], durationSec: r.g.du * 60)
                    if !marks.isEmpty { for mk in marks { server.append(r.variant(start: mk.start, len: mk.len, src: "Stash · لقطة" + (mk.label.isEmpty ? "" : ": \(mk.label)"))) } }
                    else { let s = shortSegment(key: r.g.key, durationSec: r.g.du * 60); server.append(s.len > 0 ? r.variant(start: s.start, len: s.len, src: "Stash · مقطع قصير") : r.variant(full: true, src: "Stash · فيديو كامل")) }
                    k += 1; if k % 4 == 0 { server.append(r.variant(full: true, src: "Stash · فيديو كامل")) }
                }
            }
        }
        var embeds: [Reel] = []
        if !cfg.emb.isEmpty {
            let cache = m.store.kv("embed_cache")?.object ?? [:]
            var groups: [FavCore.WorkGroup] = []
            for p in m.performers where !p.isMinor { for v in cache["\(p.id)"]?.array ?? [] {
                var g = FavCore.WorkGroup(key: v["k"]?.text ?? ""); g.t = v["t"]?.text ?? ""; g.p = v["p"]?.text ?? ""; g.tr = v["tr"]?.text ?? ""; g.du = v["du"]?.int ?? 0; g.who = [p]
                if cfg.emb.contains(where: { g.key.hasPrefix("emb:\($0):") }) { groups.append(g) }
            } }
            embeds = rankReels(groups.filter(inFocus), taste, m.reelSig, favsOnly: fav, seed: seed, n: 120).map { r in
                let src = embedSources.first { r.g.key.hasPrefix("emb:\($0.id):") }?.name ?? ""
                return r.variant(full: true, src: "\(src) · فيديو كامل")
            }
        }
        feed = weave(weave(trailers, server), embeds, bPerA: 1)
        msg = feed.isEmpty ? "لا مقاطع بعد — حدّث أعمال مفضلاتك من المصدرين، أو اضبط خادم Stash." : ""
        if cfg.prefetch { Task.detached { [feed = feed, cfg = cfg] in for r in feed.prefix(min(cfg.count, 12)) where !r.g.key.hasPrefix("stash:") && !r.g.key.hasPrefix("emb:") { _ = await ClipCache.download(r.url) }; ClipCache.prune(limitGB: cfg.gb) } }
    }

    func markBlocked(_ m: AppModel, _ url: String, _ why: String) {
        hosts[hostOf(url)] = ["ok": false, "t": .double(Date().timeIntervalSince1970 * 1000), "why": .string(why)]
        try? m.store.setKV("reel_hosts", .object(hosts))
    }
    func recordQuality(_ m: AppModel, _ url: String, h: Double, audio: Bool?) {
        var q: [String: Double] = ["h": h]; if let a = audio { q["a"] = a ? 1 : 0 }
        quality[url] = q
        try? m.store.setKV("reel_quality", .object(quality.mapValues { .object($0.mapValues { .double($0) }) }))
    }
}

struct ReelsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var st = ReelsState()
    @State private var favs = false
    @State private var focus: (String, String, String)?
    @State private var cur: String?
    @State private var muted = false
    @State private var speed: Float = 1
    @State private var clean = false
    @State private var menuFor: Reel?
    @State private var full: Reel?
    @State private var seed = UInt64(Date().timeIntervalSince1970)
    @State private var library = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if st.feed.isEmpty {
                VStack(spacing: 12) { if st.loading { ProgressView() }; Text(st.msg.isEmpty ? "تجهيز المقاطع…" : st.msg).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding() }.frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(st.feed) { r in
                            ReelPage(reel: r, active: cur == r.id, muted: muted, speed: speed, clean: clean, st: st,
                                     onEnd: { if st.cfg.auto { next(after: r) } }, onMenu: { menuFor = r }, onFull: { full = r },
                                     onFocus: { k, v, l in focus = (k, v, l); Task { await rebuild() } })
                                .containerRelativeFrame([.horizontal, .vertical]).id(r.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollIndicators(.hidden).ignoresSafeArea()
                .scrollPosition(id: $cur)
                .refreshable { seed &+= 1; await rebuild() }
            }
            if !clean { topBar } else { HStack { Spacer(); Button { clean = false } label: { Image(systemName: "eye").padding(10) } }.padding(.top, 50) }
        }
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
        .task { favs = ReelsCfg(model.store.kv("reels_cfg")).favTab; muted = !ReelsCfg(model.store.kv("reels_cfg")).sound; await rebuild() }
        .sheet(item: $menuFor) { r in ReelMenu(reel: r, speed: $speed, clean: $clean, st: st) { remove(r) }.presentationDetents([.medium, .large]) }
        .fullScreenCover(item: $full) { r in FullVideoView(url: r.url, title: r.g.t, start: r.start, stash: st.extras[r.g.key]) }
        .sheet(isPresented: $library) { NavigationStack { ReelsLibraryView(groups: Dictionary(st.feed.map { ($0.g.key, $0.g) }, uniquingKeysWith: { a, _ in a })) } }
    }

    var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white).padding(10) }
                Spacer()
                tab("مفضلاتي", favs && focus == nil) { favs = true; focus = nil; saveTab(); Task { await rebuild() } }
                Text("|").foregroundStyle(.white.opacity(0.3))
                tab("لك", !favs && focus == nil) { favs = false; focus = nil; saveTab(); Task { await rebuild() } }
                Spacer()
                Menu {
                    Button("سجلّي / المحفوظة / أعجبتني") { library = true }
                    Button(muted ? "تشغيل الصوت" : "كتم الصوت") { muted.toggle(); var c = ReelsCfg(model.store.kv("reels_cfg")); c.sound = !muted; try? model.store.setKV("reels_cfg", c.json) }
                    Button(st.cfg.auto ? "إيقاف التمرير التلقائي" : "تمرير تلقائي") { st.cfg.auto.toggle(); try? model.store.setKV("reels_cfg", st.cfg.json) }
                    Button("الوضع النظيف") { clean = true }
                    NavigationLink(value: Route.stash) { Text("مكتبة Stash") }
                    NavigationLink(value: Route.network) { Text("الشبكة والمقاطع") }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.white).padding(10) }
            }
            if let f = focus { Button { focus = nil; Task { await rebuild() } } label: { Label(f.2, systemImage: "xmark.circle.fill").font(Theme.font(13)).padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule()) } }
            if !st.msg.isEmpty && !st.feed.isEmpty { Text(st.msg).font(Theme.font(12)).foregroundStyle(.white.opacity(0.8)).padding(8).background(.black.opacity(0.5), in: Capsule()) }
        }.padding(.top, 44).padding(.horizontal, 8)
    }
    func tab(_ t: String, _ on: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { VStack(spacing: 3) { Text(t).font(Theme.font(16.5, on ? .bold : .medium)).foregroundStyle(on ? .white : .white.opacity(0.6)); Capsule().fill(.white).frame(width: on ? 22 : 0, height: 2.5) } }.padding(.horizontal, 10)
    }
    func saveTab() { var c = ReelsCfg(model.store.kv("reels_cfg")); c.favTab = favs; try? model.store.setKV("reels_cfg", c.json) }
    func rebuild() async { await st.build(model, favs: favs, focus: focus.map { ($0.0, $0.1) }, seed: seed); cur = st.feed.first?.id }
    func next(after r: Reel) { if let i = st.feed.firstIndex(where: { $0.id == r.id }), i + 1 < st.feed.count { withAnimation { cur = st.feed[i + 1].id } } }
    func remove(_ r: Reel) { next(after: r); st.feed.removeAll { $0.id == r.id } }
}

/// صفحة مقطع: مشغّل Apple (AVPlayer)، نقرة = إيقاف، نقرتان = ♥ مكان الإصبع، سحب لليسار = ملفها، ضغط مطوّل = القائمة.
struct ReelPage: View {
    @Environment(AppModel.self) private var model
    let reel: Reel; let active: Bool; let muted: Bool; let speed: Float; let clean: Bool; let st: ReelsState
    let onEnd: () -> Void; let onMenu: () -> Void; let onFull: () -> Void; let onFocus: (String, String, String) -> Void
    @State private var player: AVPlayer?
    @State private var paused = false
    @State private var hearts: [Heart] = []
    @State private var watch = Date.distantPast
    @State private var watched: Double = 0
    @State private var loops = 0
    @State private var observer: Any?
    @State private var failed = ""

    var g: FavCore.WorkGroup { reel.g }
    var liked: Bool { model.reelSig.clips[g.key]?["l"] == 1 }
    var saved: Bool { model.reelSig.clips[g.key]?["s"] == 1 }

    var body: some View {
        ZStack {
            Color.black
            if !g.p.isEmpty { PhotoView(ref: g.p).blur(radius: 30).opacity(0.45) }
            if g.key.hasPrefix("emb:") { if active { EmbedWeb(url: reel.url).padding(.vertical, 90) } }
            else if let player { VideoPlayer(player: player).disabled(true) } else if failed.isEmpty { ProgressView() }
            if !failed.isEmpty { Text("تعذّر تشغيل هذا المقطع — \(failed)").font(Theme.font(13)).foregroundStyle(.white.opacity(0.7)).padding().multilineTextAlignment(.center) }
            if paused { Image(systemName: "play.fill").font(.system(size: 60)).foregroundStyle(.white.opacity(0.7)) }
            ForEach(hearts) { h in Image(systemName: "heart.fill").font(.system(size: 96)).foregroundStyle(Theme.rose).position(h.at).transition(.scale.combined(with: .opacity)) }
            if !clean { overlay }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(count: 2).onEnded { v in like(at: v.location) }.exclusively(before: TapGesture().onEnded { togglePause() }))
        .onLongPressGesture { onMenu() }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.width < -80 && abs(v.translation.height) < 60 { openProfile() } })
        .onChange(of: active) { _, a in a ? activate() : deactivate() }
        .onAppear { prepare(); if active { activate() } }
        .onDisappear { deactivate(); teardown() }
        .onChange(of: muted) { _, m in player?.isMuted = m }
        .onChange(of: speed) { _, s in if active && !paused { player?.rate = s } }
    }

    var overlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { ForEach(g.who.prefix(3)) { p in Button("@\(p.name)") { onFocus("pf", p.id, p.name) }.font(Theme.font(16, .bold)) } }
                    Text(g.t).font(Theme.font(13.5)).lineLimit(2)
                    if !g.tg.isEmpty { HStack { ForEach(g.tg.prefix(4), id: \.self) { t in Button("#\(t)") { onFocus("tg", t, "#\(t)") }.font(Theme.font(12.5, .semibold)) } } }
                    Text(reel.why).font(Theme.font(12)).foregroundStyle(reel.explore ? Theme.rose : Theme.gold)
                    Button { if !g.s.isEmpty { onFocus("st", g.s, g.s) } } label: { Label([g.s, g.y, reel.src].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "building.2").font(Theme.font(12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1) }
                }.foregroundStyle(.white)
                Spacer()
                VStack(spacing: 18) {
                    if let p = g.who.first { avatar(p) }
                    side(liked ? "heart.fill" : "heart", liked ? Theme.rose : .white, "إعجاب") { toggleLike() }
                    side(saved ? "bookmark.fill" : "bookmark", saved ? Theme.gold : .white, "حفظ") { model.reelSig = toggleSave(model.reelSig, g); model.saveReelSig() }
                    if reel.len > 0 || reel.full { side("play.rectangle.fill", Theme.gold, "كاملًا") { model.reelSig = recordAction(model.reelSig, g, "full"); model.saveReelSig(); player?.pause(); onFull() } }
                    else if !g.key.hasPrefix("stash:") && !g.key.hasPrefix("emb:") { NavigationLink(value: Route.work(g.key)) { sideLabel("note.text", .white, "العمل") } }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 54)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
        }
    }

    func avatar(_ p: Performer) -> some View {
        ZStack(alignment: .bottom) {
            Button { openProfile() } label: { Avatar(p: p, size: 48).overlay(Circle().stroke(.white, lineWidth: 1.5)) }
            if !(model.performer(p.id)?.fav ?? true) {
                Button { follow(p) } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Theme.rose, in: Circle()) }.offset(y: 10)
            }
        }
    }
    func side(_ icon: String, _ c: Color, _ t: String, _ f: @escaping () -> Void) -> some View { Button(action: f) { sideLabel(icon, c, t) } }
    func sideLabel(_ icon: String, _ c: Color, _ t: String) -> some View { VStack(spacing: 2) { Image(systemName: icon).font(.system(size: 28)).foregroundStyle(c); Text(t).font(Theme.font(11)).foregroundStyle(.white) }.shadow(radius: 4) }

    // MARK: التشغيل
    func prepare() {
        guard player == nil, !g.key.hasPrefix("emb:") else { return }
        Task { @MainActor in
            var url = URL(string: reel.url)
            if let c = ClipCache.cached(reel.url) { url = c }
            if let ex = st.extras[g.key], !ex.direct, let h = await StashServer.hls(ex.id) { url = URL(string: h) }
            guard let u = url else { failed = "رابط غير صالح"; return }
            let item = AVPlayerItem(url: u)
            let p = AVPlayer(playerItem: item); p.isMuted = muted; p.automaticallyWaitsToMinimizeStalling = true
            if reel.start > 0 { await p.seek(to: CMTime(seconds: Double(reel.start), preferredTimescale: 600)) }
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in tick(t, p) }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in loops += 1; onEnd(); p.seek(to: CMTime(seconds: Double(reel.start), preferredTimescale: 600)); if active { p.play() } }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { n in fail((n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "") }
            player = p
            Task { await measure(item) }
            if active { activate() }
        }
    }
    func tick(_ t: CMTime, _ p: AVPlayer) {
        if p.currentItem?.status == .failed { fail(p.currentItem?.error?.localizedDescription ?? "") }
        if reel.len > 0 && t.seconds >= Double(reel.start + reel.len) { loops += 1; onEnd(); p.seek(to: CMTime(seconds: Double(reel.start), preferredTimescale: 600)) }
    }
    func fail(_ why: String) {
        failed = looksBlocked(why) ? "الخادم محجوب على شبكتك" : "الخادم لا يستجيب"
        if !g.key.hasPrefix("stash:") { st.markBlocked(model, reel.url, why) }
    }
    /// الجودة الحقيقية: الدقة ووجود صوت — المعاينات الصامتة أو الأقل من 480p تُتخطى (إن فُعّل «إعلانات حقيقية فقط»).
    func measure(_ item: AVPlayerItem) async {
        guard let tracks = try? await item.asset.load(.tracks) else { return }
        let video = tracks.first { $0.mediaType == .video }
        let size = (try? await video?.load(.naturalSize)) ?? .zero
        let audio = tracks.contains { $0.mediaType == .audio }
        if size.height > 0 && !g.key.hasPrefix("stash:") { st.recordQuality(model, reel.url, h: Double(size.height), audio: audio) }
    }
    func activate() {
        guard let p = player else { return }
        paused = false; watch = Date(); p.isMuted = muted; p.playImmediately(atRate: speed)
    }
    func deactivate() {
        player?.pause()
        if watch > .distantPast {
            let secs = Date().timeIntervalSince(watch); watch = .distantPast; watched += secs
            let dur = reel.len > 0 ? Double(reel.len) : max(1, player?.currentItem?.duration.seconds.isFinite == true ? player!.currentItem!.duration.seconds : Double(g.du * 60))
            model.reelSig = recordView(model.reelSig, g, frac: Double(loops) + min(1, watched / dur), secs: watched)
            model.saveReelSig()
        }
    }
    func teardown() { if let o = observer { player?.removeTimeObserver(o) }; observer = nil; player = nil }
    func togglePause() { guard let p = player else { return }; paused.toggle(); paused ? p.pause() : p.playImmediately(atRate: speed) }
    func like(at pt: CGPoint) {
        let id = Int(Date().timeIntervalSince1970 * 1000)
        withAnimation(.spring) { hearts.append(Heart(id: id, at: pt)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { hearts.removeAll { $0.id == id } } }
        if !liked { model.reelSig = recordView(model.reelSig, g, frac: 1, like: true); model.saveReelSig() }
    }
    func toggleLike() {
        if liked { model.reelSig.clips[g.key]?["l"] = nil } else { model.reelSig = recordView(model.reelSig, g, frac: 1, like: true) }
        model.saveReelSig()
    }
    func openProfile() {
        guard let p = g.who.first, model.performer(p.id) != nil else { return }
        model.reelSig = recordAction(model.reelSig, g, "profile"); model.saveReelSig()
        onFocus("pf", p.id, p.name)
    }
    func follow(_ p: Performer) {
        guard let cur = model.performer(p.id) else { return }
        if model.save(cur.with(["fav": true])) { model.reelSig = recordAction(model.reelSig, g, "follow"); model.saveReelSig(); model.toast = "أُضيفت \(p.name) لمفضلاتك ⭐" }
    }
}

/// مشغّل التضمين الرسمي (WKWebView) — يبقى داخل مضيف التضمين ولا يفتح روابط خارجه.
struct EmbedWeb: UIViewRepresentable {
    let url: String
    func makeCoordinator() -> Coord { Coord(host: URL(string: url)?.host ?? "") }
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration(); c.allowsInlineMediaPlayback = true; c.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: c); w.isOpaque = false; w.backgroundColor = .black; w.navigationDelegate = context.coordinator
        if let u = URL(string: url) { w.load(URLRequest(url: u)) }
        return w
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
    static func dismantleUIView(_ v: WKWebView, coordinator: Coord) { v.loadHTMLString("", baseURL: nil) }
    final class Coord: NSObject, WKNavigationDelegate {
        let host: String; init(host: String) { self.host = host }
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(a.request.url?.host == host || a.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}

/// قائمة الضغط المطوّل: السرعة، غير مهتم، أقل منها/من الاستوديو، حفظ، إخفاء، الوضع النظيف.
struct ReelMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reel: Reel; @Binding var speed: Float; @Binding var clean: Bool; let st: ReelsState; let onRemove: () -> Void
    var body: some View {
        List {
            Picker("السرعة", selection: $speed) { Text("0.5").tag(Float(0.5)); Text("1").tag(Float(1)); Text("1.5").tag(Float(1.5)); Text("2").tag(Float(2)) }.pickerStyle(.segmented)
            Button { model.reelSig = recordAction(model.reelSig, reel.g, "nope"); model.saveReelSig(); onRemove(); dismiss() } label: { Label("غير مهتم", systemImage: "heart.slash") }
            ForEach(reel.g.who) { p in Button { model.reelSig = dislikeReel(model.reelSig, performerId: p.id); model.saveReelSig(); onRemove(); dismiss() } label: { Label("أقل من \(p.name)", systemImage: "person.fill.xmark") } }
            if !reel.g.s.isEmpty { Button { model.reelSig = dislikeReel(model.reelSig, studio: reel.g.s); model.saveReelSig(); onRemove(); dismiss() } label: { Label("أقل من \(reel.g.s)", systemImage: "building.2") } }
            Button { model.reelSig = dislikeReel(model.reelSig, hideKey: reel.g.key); model.saveReelSig(); onRemove(); dismiss() } label: { Label("إخفاء هذا المقطع", systemImage: "eye.slash") }
            Toggle("الوضع النظيف", isOn: $clean)
        }
    }
}

/// سجلّي / المحفوظة / أعجبتني.
struct ReelsLibraryView: View {
    @Environment(AppModel.self) private var model
    let groups: [String: FavCore.WorkGroup]
    @State private var tab = 0
    var body: some View {
        let keys = tab == 0 ? reelHistory(model.reelSig) : tab == 1 ? reelSaved(model.reelSig) : reelLiked(model.reelSig)
        let all = Dictionary(model.works.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }).merging(groups) { a, _ in a }
        List {
            Picker("", selection: $tab) { Text("سجلّي").tag(0); Text("المحفوظة").tag(1); Text("أعجبتني").tag(2) }.pickerStyle(.segmented)
            ForEach(keys.compactMap { all[$0] }) { g in NavigationLink(value: Route.work(g.key)) { WorkRow(g: g) } }
            if keys.isEmpty { Text("لا شيء هنا بعد").foregroundStyle(Theme.muted) }
        }.navigationTitle("مقاطعي").routes()
    }
}

/// مشغّل الفيديو الكامل: VideoPlayer مع تقديم بمصغرات Stash (VTT)، ±10، ومزامنة مكان التوقف وعدد المشاهدات مع Stash.
struct FullVideoView: View {
    @Environment(\.dismiss) private var dismiss
    let url: String; let title: String; var start: Int = 0; var stash: StashExtra? = nil
    @State private var player: AVPlayer?
    @State private var cues: [VttCue] = []
    @State private var sprites: [String: UIImage] = [:]
    @State private var pos: Double = 0
    @State private var dur: Double = 0
    @State private var scrub: Double?
    @State private var began = Date()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() } else { ProgressView() }
            VStack {
                HStack { Button { dismiss() } label: { Image(systemName: "xmark").padding(10).background(.ultraThinMaterial, in: Circle()) }; Text(title).font(Theme.font(14, .semibold)).lineLimit(1); Spacer() }.padding()
                Spacer()
                if let s = scrub, let c = cueAt(cues, s), let img = sprites[c.url]?.cgImage?.cropping(to: CGRect(x: c.x, y: c.y, width: c.w, height: c.h)) {
                    Image(uiImage: UIImage(cgImage: img)).resizable().scaledToFit().frame(width: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if dur > 0 {
                    HStack {
                        Button { seek(pos - 10) } label: { Image(systemName: "gobackward.10") }
                        Slider(value: Binding(get: { scrub ?? pos }, set: { scrub = $0 }), in: 0...dur) { editing in if !editing, let s = scrub { seek(s); scrub = nil } }
                        Button { seek(pos + 10) } label: { Image(systemName: "goforward.10") }
                    }.padding().background(.ultraThinMaterial).environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .task { await setup() }
        .onDisappear { finish() }
    }
    func setup() async {
        var u = URL(string: url)
        if let c = ClipCache.cached(url) { u = c }
        if let s = stash, !s.direct, let h = await StashServer.hls(s.id) { u = URL(string: h) }
        guard let u else { return }
        let p = AVPlayer(url: u)
        let from = start > 0 ? start : Int(stash?.resume ?? 0)
        if from > 10 || start > 0 { await p.seek(to: CMTime(seconds: Double(from), preferredTimescale: 600)) }
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in pos = t.seconds; if let d = p.currentItem?.duration.seconds, d.isFinite { dur = d } }
        player = p; p.play(); began = Date()
        if let v = stash?.vtt, !v.isEmpty {
            cues = await StashServer.thumbs(v)
            for s in Set(cues.map(\.url)).prefix(4) { if let su = URL(string: s), let res = try? await URLSession.shared.data(from: su), let img = UIImage(data: res.0) { sprites[s] = img } }
        }
    }
    func seek(_ s: Double) { player?.seek(to: CMTime(seconds: max(0, s), preferredTimescale: 600)) }
    func finish() {
        player?.pause()
        guard let s = stash else { return }
        let played = Date().timeIntervalSince(began), resume = dur > 0 && pos > dur - 20 ? 0 : pos
        if played >= 5 { Task { await StashServer.saveActivity(s.id, resume: resume, played: played); if played >= 60 || (dur > 0 && played >= dur * 0.5) { await StashServer.addPlay(s.id) } } }
    }
}

struct Heart: Identifiable { let id: Int; let at: CGPoint }
