import SwiftUI
import PhotosUI
import Vision
import CoreML
import CoreImage
import CryptoKit
import FavCore

/// تمييز الوجوه — على الجهاز فقط: Vision يكتشف الوجه ونقاطه ← محاذاة قالب ArcFace (112×112) ← نموذج AuraFace (Apache-2.0) ← بصمة 512.
/// النموذج يُنزَّل مرة واحدة من نسخة مثبّتة على Hugging Face، ويُتحقق من حجمه وبصمته SHA-256 قبل ترجمته. لا تُرسل أي صورة لأي جهة.
/// تطابق محتمل ≠ هوية مؤكدة، ولا يُستنتج العمر من الوجه أبدًا.
enum FaceEngine {
    static let modelURL = URL(string: "https://huggingface.co/RuiSumida/AuraFace-v1-CoreML/resolve/fac7fea8becbb1963b80670cad1ee1eca4b38fb7/FaceEmbedding.mlmodel")!
    static let sha256 = "9cb10bef2141a36619bb1fdbf1e0e14e2519c6da4b7e9b9969a4d67702d7122b"
    static let bytes = 130_356_005
    static let same = 0.45, maybe = 0.30
    static var compiled: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FaceEmbedding.mlmodelc") }
    static var ready: Bool { FileManager.default.fileExists(atPath: compiled.path) }
    nonisolated(unsafe) static var model: MLModel?
    static let ctx = CIContext()

    static func install(progress: @escaping (Double) -> Void) async -> Bool {
        let del = Progress(cb: progress)
        guard let res = try? await URLSession.shared.download(from: modelURL, delegate: del), (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let data = try? Data(contentsOf: res.0, options: .mappedIfSafe), data.count == bytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { return false }
        let tmp = res.0
        let src = tmp.deletingLastPathComponent().appendingPathComponent("FaceEmbedding.mlmodel")
        try? FileManager.default.removeItem(at: src); try? FileManager.default.moveItem(at: tmp, to: src)
        guard let c = try? await MLModel.compileModel(at: src) else { return false }
        try? FileManager.default.removeItem(at: compiled)
        do { try FileManager.default.moveItem(at: c, to: compiled) } catch { return false }
        model = nil
        return load() != nil
    }
    final class Progress: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        let cb: (Double) -> Void; init(cb: @escaping (Double) -> Void) { self.cb = cb }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) { if t > 0 { cb(Double(w) / Double(t)) } }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
    static func load() -> MLModel? {
        if let m = model { return m }
        guard ready else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        model = try? MLModel(contentsOf: compiled, configuration: cfg)
        return model
    }

    static let template: [CGPoint] = [CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014), CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)]

    /// بصمة أكبر وجه (512، مُطبَّعة) + عدد الوجوه.
    static func embed(_ data: Data) -> ([Float], Int)? {
        guard let m = load(), var ci = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.origin.x, y: -ci.extent.origin.y))
        let size = ci.extent.size
        let req = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(ciImage: ci).perform([req])
        guard let faces = req.results, !faces.isEmpty,
              let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }), let lm = face.landmarks else { return nil }
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.pointsInImage(imageSize: size) ?? [] }
        func mean(_ p: [CGPoint]) -> CGPoint? { p.isEmpty ? nil : CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count)) }
        guard let e1 = mean(pts(lm.leftPupil)) ?? mean(pts(lm.leftEye)), let e2 = mean(pts(lm.rightPupil)) ?? mean(pts(lm.rightEye)),
              let nose = pts(lm.nose).min(by: { $0.y < $1.y }), let ml = pts(lm.outerLips).min(by: { $0.x < $1.x }), let mr = pts(lm.outerLips).max(by: { $0.x < $1.x }) else { return nil }
        let eyes = [e1, e2].sorted { $0.x < $1.x }
        let src = [eyes[0], eyes[1], nose, ml, mr], dst = template.map { CGPoint(x: $0.x, y: 112 - $0.y) }
        let n = CGFloat(src.count)
        let mx = src.map(\.x).reduce(0, +) / n, my = src.map(\.y).reduce(0, +) / n, mu = dst.map(\.x).reduce(0, +) / n, mv = dst.map(\.y).reduce(0, +) / n
        var a1: CGFloat = 0
        var a2: CGFloat = 0
        var den: CGFloat = 0
        for i in 0..<src.count { let xc = src[i].x - mx, yc = src[i].y - my, uc = dst[i].x - mu, vc = dst[i].y - mv; a1 += xc * uc + yc * vc; a2 += xc * vc - yc * uc; den += xc * xc + yc * yc }
        guard den > 0 else { return nil }
        let a = a1 / den, b = a2 / den
        let aligned = ci.transformed(by: CGAffineTransform(a: a, b: b, c: -b, d: a, tx: mu - (a * mx - b * my), ty: mv - (b * mx + a * my))).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
        guard let inName = m.modelDescription.inputDescriptionsByName.keys.first, let desc = m.modelDescription.inputDescriptionsByName[inName] else { return nil }
        do {
            let provider: MLFeatureProvider
            if desc.type == .image {
                var pb: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &pb)
                guard let buf = pb else { return nil }
                ctx.render(aligned, to: buf)
                provider = try MLDictionaryFeatureProvider(dictionary: [inName: MLFeatureValue(pixelBuffer: buf)])
            } else {
                var px = [UInt8](repeating: 0, count: 112 * 112 * 4)
                ctx.render(aligned, toBitmap: &px, rowBytes: 448, bounds: CGRect(x: 0, y: 0, width: 112, height: 112), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                let arr = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
                for y in 0..<112 { for x in 0..<112 { for c in 0..<3 { arr[c * 12544 + y * 112 + x] = NSNumber(value: Float(px[(y * 112 + x) * 4 + c])) } } }
                provider = try MLDictionaryFeatureProvider(dictionary: [inName: MLFeatureValue(multiArray: arr)])
            }
            let out = try m.prediction(from: provider)
            guard let e = out.featureValue(for: m.modelDescription.outputDescriptionsByName.keys.first ?? "embedding")?.multiArrayValue else { return nil }
            var v = (0..<e.count).map { e[$0].floatValue }
            let nn = sqrt(v.reduce(0) { $0 + $1 * $1 }); guard nn > 0 else { return nil }
            v = v.map { $0 / nn }
            return (v, faces.count)
        } catch { return nil }
    }
    static func cos(_ a: [Float], _ b: [Float]) -> Double { a.count == b.count ? Double(zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }) : 0 }
    /// بصمة الممثلة: أكبر مجموعة متشابهة من صورها (إجماع) — لا تفسدها صورة لشخص آخر.
    static func consensus(_ es: [[Float]]) -> [Float]? {
        if es.count == 1 { return es[0] }
        var best: [Int] = []
        for i in es.indices { let g = es.indices.filter { $0 == i || cos(es[i], es[$0]) >= maybe }; if g.count > best.count { best = g } }
        guard best.count >= 2 else { return nil }
        var s = [Float](repeating: 0, count: es[0].count); for i in best { for k in s.indices { s[k] += es[i][k] } }
        let n = sqrt(s.reduce(0) { $0 + $1 * $1 }); return s.map { $0 / n }
    }
    static func photoData(_ m: AppModel, _ ref: String) async -> Data? {
        if ref.hasPrefix("file:") { return m.store.photoURL(ref).flatMap { try? Data(contentsOf: $0) } }
        guard ref.hasPrefix("https://"), let u = URL(string: ref) else { return nil }
        return try? await URLSession.shared.data(from: u).0
    }
}

/// بوابة النموذج: شرح + تنزيل (130 م.ب مرة واحدة).
struct FaceModelGate<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var ready = FaceEngine.ready
    @State private var progress: Double?
    @State private var failed = false
    var body: some View {
        if ready { content } else {
            VStack(spacing: 14) {
                Image(systemName: "face.smiling").font(.system(size: 50)).foregroundStyle(Theme.gold)
                Text("تمييز الوجوه").font(Theme.font(20, .bold))
                Text("يحتاج نموذج AuraFace (ترخيص Apache-2.0) — 130 م.ب تُنزَّل مرة واحدة ويُتحقق منها. بعدها كل شيء على جهازك: لا تُرسل أي صورة لأي جهة.").font(Theme.font(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                if let progress { ProgressView(value: progress).tint(Theme.gold); Text(progress >= 0.999 ? "تجهيز النموذج على جهازك…" : "تنزيل \(Int(progress * 130)) من 130 م.ب").font(Theme.font(12)) }
                else { Button("تنزيل النموذج (130 م.ب)") { Task { progress = 0; let ok = await FaceEngine.install { p in Task { @MainActor in progress = p } }; progress = nil; ready = ok; failed = !ok } }.buttonStyle(.borderedProminent) }
                if failed { Text("تعذّر التنزيل أو لم تطابق البصمة — لم يُثبَّت شيء.").foregroundStyle(Theme.rose).font(Theme.font(12)) }
            }.padding(24)
        }
    }
}

/// «فحص صورها بالوجه»: تشابه كل صورة مع إجماع صورها؛ المشكوك فيها أولًا، والإزالة بتأكيدك فقط.
struct FaceAlbumView: View {
    @Environment(AppModel.self) private var model
    let performerId: String
    @State private var results: [(String, Double?)]?
    @State private var progress = ""
    var body: some View {
        FaceModelGate {
            ScrollView {
                if let r = results {
                    let odd = r.filter { ($0.1 ?? 1) < FaceEngine.maybe }.count
                    Text(odd == 0 ? "✓ كل الصور تبدو لنفس الشخص" : "\(odd) صورة قد لا تكون لها — راجعها").font(Theme.font(15, .semibold)).foregroundStyle(odd == 0 ? Theme.ok : Theme.gold)
                    Text("تطابق محتمل وليس هوية مؤكدة — الإضاءة والزاوية والمكياج تؤثر. القرار لك.").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(r.sorted { ($0.1 ?? 2) < ($1.1 ?? 2) }, id: \.0) { x in
                            VStack(spacing: 3) {
                                PhotoView(ref: x.0).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(color(x.1), lineWidth: 2.5))
                                Text(x.1.map { "\(Int(($0 * 100).rounded()))٪" } ?? "بلا وجه واضح").font(Theme.font(11)).foregroundStyle(color(x.1))
                                if (x.1 ?? 1) < FaceEngine.same { Button("إزالة") { remove(x.0) }.font(Theme.font(11)) }
                            }
                        }
                    }
                } else { ProgressView(); Text(progress).font(Theme.font(12)) }
            }.padding()
            .task { await run() }
        }.navigationTitle("فحص الصور بالوجه")
    }
    func color(_ s: Double?) -> Color { guard let s else { return Theme.muted }; return s >= FaceEngine.same ? Theme.ok : s >= FaceEngine.maybe ? Theme.gold : Theme.rose }
    @MainActor func run() async {
        guard let p = model.performer(performerId), !p.isMinor else { results = []; return }
        var es: [String: [Float]] = [:]
        for (i, ref) in p.photos.enumerated() {
            progress = "تحليل الصور (\(i + 1)/\(p.photos.count))…"
            if let d = await FaceEngine.photoData(model, ref), let e = FaceEngine.embed(d), e.1 == 1 { es[ref] = e.0 }
        }
        let c = FaceEngine.consensus(Array(es.values))
        results = p.photos.map { ref in (ref, c.flatMap { cc in es[ref].map { e in FaceEngine.cos(e, cc) } }) }
    }
    func remove(_ ref: String) {
        guard let p = model.performer(performerId) else { return }
        let l = p.photos.filter { $0 != ref }
        model.save(p.with(["photos": .array(l.map { .string($0) }), "thumb": .string(l.first ?? "")])); results?.removeAll { $0.0 == ref }
    }
}

/// «ابحث بصورة»: أقرب ممثلات مكتبتك وجهًا لصورة من معرضك.
struct FaceSearchView: View {
    @Environment(AppModel.self) private var model
    @State private var profiles: [String: [Float]] = [:]
    @State private var building = false
    @State private var progress = ""
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var results: [(Performer, Double)] = []
    @State private var msg = ""
    var body: some View {
        FaceModelGate {
            List {
                Section {
                    Text("\(profiles.count) ممثلة جاهزة للمقارنة").foregroundStyle(Theme.muted)
                    Button(building ? progress : "تجهيز/تحديث بصمات المفضلات") { Task { await build() } }.disabled(building)
                    PhotosPicker(selection: $item, matching: .images) { Label("اختر صورة", systemImage: "photo") }.disabled(profiles.isEmpty)
                }
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240) }
                if !msg.isEmpty { Text(msg).foregroundStyle(Theme.gold) }
                if !results.isEmpty {
                    Section(results.first!.1 < FaceEngine.maybe ? "لا تشبه أحدًا بوضوح" : "الأقرب في مكتبتك (تطابق محتمل)") {
                        ForEach(results, id: \.0.id) { r in NavigationLink(value: Route.performer(r.0.id)) { HStack { Avatar(p: r.0, size: 40); Text(r.0.name); Spacer(); Text("\(Int((r.1 * 100).rounded()))٪").foregroundStyle(r.1 >= FaceEngine.same ? Theme.ok : r.1 >= FaceEngine.maybe ? Theme.gold : Theme.rose) } } }
                    }
                }
            }
            .onChange(of: item) { _, it in Task { await match(it) } }
            .onAppear { load() }
        }.navigationTitle("ابحث بصورة")
    }
    func load() { profiles = (model.store.kv("face_prof")?.object ?? [:]).compactMapValues { $0.array?.compactMap { $0.number.map(Float.init) } } }
    @MainActor func build() async {
        building = true; defer { building = false }
        for (i, p) in model.performers.filter({ ($0.fav || $0.rating >= 4) && !$0.isMinor && !$0.photos.isEmpty }).enumerated() {
            if profiles[p.id] != nil { continue }
            progress = "بصمة \(p.name) (\(i + 1))…"
            var es: [[Float]] = []
            for ref in p.photos.prefix(6) { if let d = await FaceEngine.photoData(model, ref), let e = FaceEngine.embed(d), e.1 == 1 { es.append(e.0) } }
            if let c = FaceEngine.consensus(es) { profiles[p.id] = c }
        }
        try? model.store.setKV("face_prof", .object(profiles.mapValues { .array($0.map { .double(Double($0)) }) }))
    }
    @MainActor func match(_ it: PhotosPickerItem?) async {
        guard let it, let d = try? await it.loadTransferable(type: Data.self) else { return }
        image = UIImage(data: d)
        guard let e = FaceEngine.embed(d) else { msg = "لم يُعثر على وجه واضح"; results = []; return }
        msg = e.1 > 1 ? "في الصورة \(e.1) وجوه — استُخدم أكبرها" : ""
        results = profiles.compactMap { id, v in model.performer(id).flatMap { $0.isMinor ? nil : ($0, FaceEngine.cos(e.0, v)) } }.sorted { $0.1 > $1.1 }.prefix(10).map { $0 }
    }
}
