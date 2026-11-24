import XCTest
@testable import FavCore

/// التوافق مع التطبيق الحالي (Flutter): ملفات Fixtures مولّدة بكوده نفسه (tool/gen_ios_fixture_test.dart) ببيانات محايدة.
final class LegacyCompatTests: XCTestCase {
    /// «اليوم» ثابت لاختبارات العمر (حتى لا تتغير النتيجة مع مرور السنوات).
    static let now = gregorian.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!

    func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    var expected: JSONObject { get throws { try XCTUnwrap(JSONValue.parse(fixture("legacy-expected", "json")).object) } }

    func testPlainBackupParsesExactlyLikeTheFlutterApp() throws {
        let f = try Backup.parse(fixture("legacy-plain-v5", "json"), now: Self.now)
        let e = try expected
        XCTAssertEqual(f.items.map { $0["id"]!.string! }, e["ids"]!.array!.map { $0.string! })
        XCTAssertEqual(f.minorsSkipped, e["minorsSkipped"]!.int)
        XCTAssertEqual(f.invalid, e["invalid"]!.int)
        XCTAssertEqual(f.lists.map { JSONValue.object($0) }, e["lists"]!.array!)
        XCTAssertEqual(f.wlists.map { JSONValue.object($0) }, e["wlists"]!.array!)
        XCTAssertEqual(f.prefs, e["prefs"]!.object!.mapValues { $0.string! })
        // كل سجل مطابق حقلًا بحقل — بما فيها الحقل المجهول zzFuture والأعمال بعد التنقية
        for (got, want) in zip(f.items, e["items"]!.array!) {
            XCTAssertEqual(JSONValue.object(got), want, "السجل \(got["id"]!.text)")
        }
        XCTAssertEqual(f.items[0]["zzFuture"]?["flag"], .bool(true))
        XCTAssertNil(f.prefs["vkte_key"]); XCTAssertNil(f.prefs["vkte_pin2"])
    }

    func testEncryptedBackupFromFlutterDecrypts() throws {
        let enc = try fixture("legacy-encrypted", "vkte")
        XCTAssertTrue(Backup.isEncrypted(enc))
        let plain = try Backup.decrypt(enc, password: try expected["password"]!.string!)
        XCTAssertEqual(plain, try fixture("legacy-plain-v5", "json"))
        XCTAssertThrowsError(try Backup.decrypt(enc, password: "wrong-password")) { XCTAssertEqual($0 as? BackupError, .wrongPassword) }
    }

    func testEncryptRoundTripAndShortPassword() throws {
        let enc = try Backup.encrypt("{\"a\":1}", password: "12345678")
        XCTAssertEqual(try Backup.decrypt(enc, password: "12345678"), "{\"a\":1}")
        XCTAssertThrowsError(try Backup.encrypt("x", password: "1234567")) { XCTAssertEqual($0 as? BackupError, .shortPassword) }
    }

    func testExportIsReadableAgainAndDropsSecrets() throws {
        let f = try Backup.parse(fixture("legacy-plain-v5", "json"), now: Self.now)
        let out = try Backup.export(f.items.map(Performer.init), lists: f.lists, wlists: f.wlists, prefs: ["vkte_goal": "5", "vkte_key": "SECRET"], now: Self.now) { $0 }
        XCTAssertFalse(out.contains("SECRET"))
        let back = try Backup.parse(out, now: Self.now)
        XCTAssertEqual(back.items.map { JSONValue.object($0) }, f.items.map { JSONValue.object($0) })
        XCTAssertEqual(try JSONValue.parse(out)["app"], "vkte-favorites"); XCTAssertEqual(try JSONValue.parse(out)["v"], 5)
    }

    func testImportPlanNeverDeletesAndRespectsUpdated() throws {
        let f = try Backup.parse(fixture("legacy-plain-v5", "json"), now: Self.now)
        // موجود أحدث محليًا ⇒ يبقى؛ موجود أقدم ⇒ يُحدَّث مع إبقاء حقول الجهاز؛ جديد ⇒ يُضاف
        let newerLocal = Performer(["id": "p-demo-a", "name": "Local A", "updated": 1_900_000_000_000, "photos": ["file:a.jpg", "file:b.jpg"]])
        let olderLocal = Performer(["id": "p-demo-b", "name": "Old B", "updated": 1, "views": 77, "photos": []])
        let other = Performer(["id": "p-only-local", "name": "Only Local", "updated": 5])
        let plan = Backup.plan(f, current: ["p-demo-a": newerLocal, "p-demo-b": olderLocal, "p-only-local": other])
        let byId = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.record["id"]!.string!, $0) })
        XCTAssertEqual(byId["p-demo-a"]?.action, .keep)
        XCTAssertEqual(byId["p-demo-b"]?.action, .update)
        XCTAssertEqual(byId["p-demo-b"]?.record["views"], 77)
        XCTAssertEqual(byId["p-no-date"]?.action, .add)
        XCTAssertNil(byId["p-only-local"])   // لا يمسّ ما ليس في الملف
        XCTAssertEqual(plan.added, 1); XCTAssertEqual(plan.updated, 1); XCTAssertEqual(plan.kept, 1)
    }
}
