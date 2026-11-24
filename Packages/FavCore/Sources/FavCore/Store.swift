import Foundation
import SQLite3

/// التخزين المحلي: قاعدة SQLite (السجلات كـ JSON كاملة حتى لا يضيع حقل) + مخزن مفاتيح/قيم + الصور ملفات.
/// كل شيء داخل مجلد التطبيق (Application Support) ولا شيء يغادر الجهاز.
/// نقطة كتابة واحدة: `save` — ترفض القاصر دائمًا (بوابة +18) وتعيد ما حُفظ فعلًا.
public final class Store: @unchecked Sendable {
    public let dir: URL
    public var photosDir: URL { dir.appendingPathComponent("photos", isDirectory: true) }
    var dbURL: URL { dir.appendingPathComponent("library.sqlite") }
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(directory: URL) throws {
        dir = directory
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        try open()
    }

    private func open() throws {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK { throw StoreError.open }
        try exec("PRAGMA journal_mode=WAL")
        try exec("CREATE TABLE IF NOT EXISTS recs(id TEXT PRIMARY KEY, json TEXT NOT NULL, updated INTEGER NOT NULL DEFAULT 0)")
        try exec("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, json TEXT NOT NULL)")
    }
    deinit { sqlite3_close(db) }

    public enum StoreError: Error { case open, sql(String) }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK { let m = err.map { String(cString: $0) } ?? "?"; sqlite3_free(err); throw StoreError.sql(m) }
    }
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: السجلات
    public func loadAll() -> [Performer] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?; var out: [Performer] = []
        guard sqlite3_prepare_v2(db, "SELECT json FROM recs ORDER BY updated DESC", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            if let c = sqlite3_column_text(st, 0), let o = (try? JSONValue.parse(String(cString: c)))?.object { out.append(Performer(o)) }
        }
        return out
    }

    /// حفظ دفعة: يرفض أي سجل قاصر أو بمعرّف غير صالح. يعيد السجلات المحفوظة.
    @discardableResult
    public func save(_ items: [Performer], now: Date = Date()) throws -> [Performer] {
        let ok = items.filter { safeId($0.raw["id"]) && !$0.isMinor && !$0.name.isEmpty }
        if ok.isEmpty { return [] }
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN")
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO recs(id,json,updated) VALUES(?,?,?)", -1, &st, nil) == SQLITE_OK else { try? exec("ROLLBACK"); throw StoreError.sql("prepare") }
        defer { sqlite3_finalize(st) }
        for p in ok {
            var raw = p.raw
            if raw["added"] == nil { raw["added"] = raw["updated"] ?? .int(Int64(now.timeIntervalSince1970 * 1000)) }
            if raw["updated"] == nil { raw["updated"] = .int(Int64(now.timeIntervalSince1970 * 1000)) }
            let json = String(decoding: try JSONValue.object(raw).encoded(), as: UTF8.self)
            sqlite3_reset(st)
            sqlite3_bind_text(st, 1, p.id, -1, transient)
            sqlite3_bind_text(st, 2, json, -1, transient)
            sqlite3_bind_int64(st, 3, Performer(raw).updated)
            if sqlite3_step(st) != SQLITE_DONE { try? exec("ROLLBACK"); throw StoreError.sql("insert \(p.id)") }
        }
        try exec("COMMIT")
        return ok
    }

    public func delete(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM recs WHERE id=?", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, id, -1, transient); sqlite3_step(st)
    }

    // MARK: مفاتيح/قيم (الإعدادات، القوائم، ذاكرات المحركات…)
    public func kv(_ k: String) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json FROM kv WHERE k=?", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, k, -1, transient)
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        return try? JSONValue.parse(String(cString: c))
    }
    public func setKV(_ k: String, _ v: JSONValue) throws {
        let json = String(decoding: try v.encoded(), as: UTF8.self)
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO kv(k,json) VALUES(?,?)", -1, &st, nil) == SQLITE_OK else { throw StoreError.sql("kv") }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, k, -1, transient); sqlite3_bind_text(st, 2, json, -1, transient)
        if sqlite3_step(st) != SQLITE_DONE { throw StoreError.sql("kv step") }
    }

    // MARK: الصور
    /// يحفظ صورة data URI ملفًا ويعيد مرجعها «file:<اسم>». روابط http(s) تبقى كما هي. غير الصالح ⇒ nil.
    public func storeImage(_ src: String, id: String, index: Int) -> String? {
        if src.hasPrefix("file:") { return src }
        if src.hasPrefix("https://") || src.hasPrefix("http://") { return src }
        guard src.hasPrefix("data:image/"), let comma = src.firstIndex(of: ","),
              let data = Data(base64Encoded: String(src[src.index(after: comma)...]), options: .ignoreUnknownCharacters), !data.isEmpty else { return nil }
        let mime = String(src[src.index(src.startIndex, offsetBy: 11)..<(src.firstIndex(of: ";") ?? comma)]).lowercased()
        let ext = ["jpeg": "jpg", "jpg": "jpg", "png": "png", "webp": "webp", "gif": "gif", "avif": "avif"][mime] ?? "jpg"
        let safe = id.replacingOccurrences(of: #"[^A-Za-z0-9_-]"#, with: "_", options: .regularExpression)
        let name = "\(safe)-\(index)-\(data.count).\(ext)"
        do { try data.write(to: photosDir.appendingPathComponent(name), options: .atomic); return "file:\(name)" } catch { return nil }
    }

    public func photoURL(_ ref: String) -> URL? {
        if ref.hasPrefix("file:") { return photosDir.appendingPathComponent(String(ref.dropFirst(5))) }
        return URL(string: ref)
    }

    /// مرجع صورة ⇒ data URI (للتصدير).
    public func photoDataURI(_ ref: String) -> String? {
        if ref.hasPrefix("https://") || ref.hasPrefix("http://") || ref.hasPrefix("data:") { return ref }
        guard let u = photoURL(ref), let d = try? Data(contentsOf: u) else { return nil }
        let ext = u.pathExtension.lowercased()
        let mime = ["jpg": "jpeg", "jpeg": "jpeg", "png": "png", "webp": "webp", "gif": "gif", "avif": "avif"][ext] ?? "jpeg"
        return "data:image/\(mime);base64,\(d.base64EncodedString())"
    }

    // MARK: نقطة استرجاع (قبل الاستيراد الكبير)
    var snapshotURL: URL { dir.appendingPathComponent("library.before-import.sqlite") }
    /// نسخة كاملة من القاعدة قبل الاستيراد (VACUUM INTO آمن أثناء الاستخدام).
    public func makeRollbackPoint() throws {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: snapshotURL)
        try exec("VACUUM INTO '\(snapshotURL.path.replacingOccurrences(of: "'", with: "''"))'")
    }
    public var hasRollbackPoint: Bool { FileManager.default.fileExists(atPath: snapshotURL.path) }
    /// يعيد القاعدة لما كانت عليه قبل آخر استيراد (الصور الإضافية تبقى ملفات غير مستخدمة — لا ضرر).
    public func rollback() throws {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        sqlite3_close(db); db = nil
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix)) }
        try FileManager.default.copyItem(at: snapshotURL, to: dbURL)
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK { throw StoreError.open }
    }

    /// تنفيذ خطة استيراد: نقطة استرجاع ⇒ الصور ملفات ⇒ حفظ على دفعات ⇒ القوائم والتفضيلات ⇒ تقرير تحقق.
    public func apply(_ plan: Backup.Plan, progress: ((Int, Int) -> Void)? = nil) throws -> MigrationReport {
        let before = Set(loadAll().map(\.id))
        try makeRollbackPoint()
        var batch: [Performer] = []
        let todo = plan.items.filter { $0.action != .keep }
        for (i, it) in todo.enumerated() {
            progress?(i, todo.count)
            var r = it.record
            let id = r["id"]!.string!
            let photos = (r["photos"]?.array ?? []).compactMap { $0.string }
            r["photos"] = .array(photos.enumerated().compactMap { storeImage($1, id: id, index: $0) }.map { .string($0) })
            if let th = r["thumb"]?.string {
                if let ref = storeImage(th, id: id, index: 99) { r["thumb"] = .string(ref) } else { r["thumb"] = nil }
            }
            batch.append(Performer(r))
            if batch.count >= 25 { try save(batch); batch.removeAll() }
        }
        try save(batch)
        let lists = (kv("lists")?.array ?? []).compactMap { $0.object }, wlists = (kv("wlists")?.array ?? []).compactMap { $0.object }
        try setKV("lists", .array(Backup.mergeLists(lists, plan.file.lists).map { .object($0) }))
        try setKV("wlists", .array(Backup.mergeLists(wlists, plan.file.wlists).map { .object($0) }))
        let prefs = (kv("prefs")?.object ?? [:]).compactMapValues { $0.string }
        try setKV("prefs", .object(Backup.mergePrefs(prefs, plan.file.prefs).mapValues { .string($0) }))
        progress?(todo.count, todo.count)
        let after = Dictionary(loadAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return MigrationReport.verify(plan: plan, before: before, after: after)
    }
}
