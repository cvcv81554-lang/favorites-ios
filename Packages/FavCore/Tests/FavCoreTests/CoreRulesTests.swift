import XCTest
@testable import FavCore

/// القواعد الأساسية: بوابة +18، التنقية، «نفس العمل؟»، وتوحيد الأعمال — بنفس نتائج التطبيق الحالي.
final class CoreRulesTests: XCTestCase {
    let now = LegacyCompatTests.now   // 2026-11-24

    func testAgeGateWorstCaseRules() {
        XCTAssertEqual(sdAge("1990-06-15", now: now).age, 36)
        XCTAssertEqual(sdAge("2008-11-24", now: now).age, 18)          // يوم الميلاد نفسه يُحتسب
        XCTAssertEqual(sdAge("2008-11-25", now: now).age, 17)
        XCTAssertEqual(sdAge("2008", now: now).age, 17)                 // سنة فقط ⇒ 31 ديسمبر
        XCTAssertEqual(sdAge("2008-11", now: now).age, 17)              // سنة وشهر ⇒ آخر يوم (30 نوفمبر)
        XCTAssertEqual(sdAge("2008-10", now: now).age, 18)
        XCTAssertTrue(sdAge("2001-02-30", now: now).invalid)            // تاريخ مستحيل
        XCTAssertTrue(sdAge("2030-01-01", now: now).invalid)            // مستقبل
        XCTAssertTrue(sdAge("not a date", now: now).invalid)
        XCTAssertTrue(sdAge("", now: now).isNone)
        XCTAssertTrue(minorRec(["birth": "2010-01-01"], now: now))
        XCTAssertTrue(minorRec(["birth": "2001-02-30"], now: now))
        XCTAssertFalse(minorRec(["name": "x"], now: now))                // بلا تاريخ: ليس قاصرًا، لكنه غير موثّق
        XCTAssertTrue(adultOk(["birthRaw": ""], now: now))
        XCTAssertFalse(adultOk(["birthRaw": "2009"], now: now))
        XCTAssertTrue(adultOk(["birth": "1999"], now: now))
        XCTAssertNil(verifiedYoungAdult("2006", now: now))              // 18–21 يحتاج تاريخًا كاملًا
        XCTAssertEqual(verifiedYoungAdult("2006-01-01", now: now), 20)
        XCTAssertNil(verifiedYoungAdult("1990-01-01", now: now))
    }

    func testStoreRejectsMinorsAlways() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = try Store(directory: dir)
        let y = gregorian.component(.year, from: Date())
        let saved = try s.save([Performer(["id": "ok", "name": "Adult", "birth": "1990-01-01"]),
                                Performer(["id": "minor", "name": "Minor", "birth": "\(y - 16)-01-01"]),
                                Performer(["id": "bad id", "name": "Bad"])])
        XCTAssertEqual(saved.map(\.id), ["ok"])
        XCTAssertEqual(s.loadAll().map(\.id), ["ok"])
    }

    func testSanitize() {
        XCTAssertTrue(safeId("p-demo_1.x:y")); XCTAssertFalse(safeId("bad id")); XCTAssertFalse(safeId("عربي"))
        XCTAssertTrue(safeImg("https://a/b.jpg")); XCTAssertFalse(safeImg("javascript:alert(1)")); XCTAssertFalse(safeImg("https://a/\"x"))
        XCTAssertEqual(ydOf("2023-5-7"), ["d": "2023-05-07", "y": "2023"]); XCTAssertEqual(ydOf("7/5/2023"), ["d": "2023-05-07", "y": "2023"]); XCTAssertEqual(ydOf("2023-05"), ["y": "2023"])
        XCTAssertEqual(wkey("Demo Scene: One!"), "demosceneone"); XCTAssertEqual(wkey("مشهد تجريبي"), "مشهدتجريبي")
        let w = safeWorks(["Title (2011)", ["t": "  X ", "p": "http://insecure/p.jpg", "ip": "bad id!", "y": "20x", "tg": ["a", "a", 3]], ["t": ""]])
        XCTAssertEqual(w.count, 2)
        XCTAssertEqual(w[0], ["t": "Title", "y": "2011"])
        XCTAssertEqual(w[1], ["t": "X", "tg": ["a"]])
    }

    func testSameWork() {
        XCTAssertTrue(sameWork(["t": "A", "is": "1"], ["t": "B", "is": "1"]))                                 // معرّف مشترك
        XCTAssertFalse(sameWork(["t": "A", "is": "1", "d": "2020-01-01"], ["t": "A", "is": "2", "d": "2020-01-01"]))   // تعارض
        XCTAssertTrue(sameWork(["t": "Beach Day", "s": "Studio X", "d": "2020-01-01"], ["t": "beach day!", "s": "StudioX", "d": "2020-01-03"]))
        XCTAssertFalse(sameWork(["t": "Beach Day", "d": "2020-01-01"], ["t": "Beach Day", "d": "2020-02-01"]))      // أكثر من 3 أيام
        XCTAssertFalse(sameWork(["t": "Beach Day", "s": "A", "d": "2020-01-01"], ["t": "Beach Day", "s": "B", "d": "2020-01-02"]))
        XCTAssertTrue(sameWork(["t": "Beach Day", "s": "A", "d": "2020-01-01"], ["t": "Beach Day", "s": "B", "d": "2020-01-01"]))
    }

    func testGroupWorksAcrossPerformersAndSources() {
        let a = Performer(["id": "a", "name": "A", "works": [["t": "Shared", "s": "S", "d": "2023-05-07", "is": "SC-1", "w": 1, "wd": "2024-01-02", "r": 4],
                                                             ["t": "Only A", "s": "S"]]])
        let b = Performer(["id": "b", "name": "B", "works": [["t": "Shared", "s": "S", "d": "2023-05-08", "ip": "TP-9", "r": 5],
                                                             ["t": "shared", "s": "S"]]])   // بلا معرّف ⇒ ينضم للمجموعة نفسها
        let g = groupWorks([a, b])
        XCTAssertEqual(g.count, 2)
        let shared = g.first { $0.t == "Shared" }!
        XCTAssertEqual(Set(shared.who.map(\.id)), ["a", "b"])
        XCTAssertEqual(shared.refs.count, 3)
        XCTAssertTrue(shared.seen); XCTAssertEqual(shared.r, 5); XCTAssertEqual(shared.wd, "2024-01-02")
        XCTAssertTrue(shared.key.hasPrefix("is:"))   // جذر StashDB مفضّل
    }

    func testStoreImportApplyRollbackAndReport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = try Store(directory: dir)
        try s.save([Performer(["id": "keep-me", "name": "Existing", "updated": 10])])
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let file = BackupFile(items: [["id": "new-1", "name": "New", "rating": 4.5, "criteria": ["beauty": 5], "lists": ["L1"], "photos": [.string(png)], "thumb": .string(png),
                                       "works": [["t": "W", "w": 1]], "updated": 20]],
                              lists: [["id": "L1", "name": "قائمة"]], wlists: [], prefs: ["vkte_goal": "3"], minorsSkipped: 1, invalid: 0)
        let plan = Backup.plan(file, current: Dictionary(uniqueKeysWithValues: s.loadAll().map { ($0.id, $0) }))
        let report = try s.apply(plan)
        XCTAssertTrue(report.ok, report.problems.joined(separator: "\n"))
        XCTAssertEqual(report.checked, 1)
        let n = s.loadAll().first { $0.id == "new-1" }!
        XCTAssertTrue(n.photos[0].hasPrefix("file:")); XCTAssertNotNil(s.photoDataURI(n.photos[0]))
        XCTAssertEqual(s.kv("lists")?.array?.count, 1); XCTAssertEqual(s.kv("prefs")?["vkte_goal"], "3")
        XCTAssertTrue(s.hasRollbackPoint)
        try s.rollback()
        XCTAssertEqual(s.loadAll().map(\.id), ["keep-me"])   // رجع كما كان قبل الاستيراد
    }

    func testJSONNumbersRoundTrip() throws {
        let v = try JSONValue.parse(#"{"a":5,"b":4.5,"c":1760000000000,"d":true,"e":null}"#)
        XCTAssertEqual(v["a"], .int(5)); XCTAssertEqual(v["b"], .double(4.5)); XCTAssertEqual(v["c"], .int(1_760_000_000_000)); XCTAssertEqual(v["d"], .bool(true))
        XCTAssertEqual(try JSONValue.parse(v.encoded()), v)
    }
}
