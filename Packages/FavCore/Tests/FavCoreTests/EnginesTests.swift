import XCTest
@testable import FavCore

/// المحركات المنقولة والجديدة: الذوق، الأعمال، المقاطع، اللغة الطبيعية، اليوميات، الدمج، Stash، والذكاء.
final class EnginesTests: XCTestCase {
    let now = LegacyCompatTests.now

    func performer(_ id: String, rating: Double, fav: Bool = true, hair: String, eth: String, country: String = "US", height: Double = 165) -> (Performer, Features) {
        (Performer(["id": .string(id), "name": .string("P \(id)"), "rating": .double(rating), "fav": .bool(fav), "birth": "1995-01-01"]),
         ["hair_color": .s(hair), "ethnicity": .s(eth), "country": .s(country), "height": .n(height), "age": .n(30)])
    }

    func testTasteProfileAndSimilarity() {
        let f: [Features] = [["hair_color": .s("BLONDE"), "height": .n(165)], ["hair_color": .s("BLONDE"), "height": .n(167)], ["hair_color": .s("BLONDE"), "height": .n(170)], ["hair_color": .s("BLACK")]]
        let p = buildProfile(f)
        XCTAssertTrue(p.sufficient); XCTAssertEqual(p.strongCats.first?.top.key, "BLONDE")
        let a = similarity(p, ["hair_color": .s("BLONDE"), "height": .n(166)]), b = similarity(p, ["hair_color": .s("RED"), "height": .n(185)])
        XCTAssertGreaterThan(a.score, b.score); XCTAssertFalse(a.why.isEmpty); XCTAssertFalse(b.diff.isEmpty)
        XCTAssertFalse(describeProfile(p).isEmpty)
    }

    func testFeaturesFromStashRecordNeverGuess() {
        let f = featuresOf(["hair_color": "BLONDE", "ethnicity": "OTHER", "tattoos": [], "cup_size": "DD", "birth_date": "1990-01-01", "height": 170], now: now)
        XCTAssertEqual(f["hair_color"], .s("BLONDE")); XCTAssertNil(f["ethnicity"]); XCTAssertEqual(f["tattoos"], .s("no")); XCTAssertEqual(f["cup"], .n(4.5)); XCTAssertEqual(f["age"], .n(36))
    }

    func testWorkTasteAndRecommendations() {
        var g1 = WorkGroup(key: "a"); g1.t = "A"; g1.s = "Studio X"; g1.r = 5; g1.seen = true
        var g2 = WorkGroup(key: "b"); g2.t = "B"; g2.s = "Studio X"; g2.r = 5; g2.seen = true
        var g3 = WorkGroup(key: "c"); g3.t = "C"; g3.s = "Studio X"; g3.d = "2020-01-01"
        var g4 = WorkGroup(key: "d"); g4.t = "D"; g4.s = "Other"
        let t = buildWorkTaste([g1, g2, g3, g4])
        let r = recommendWorks([g1, g2, g3, g4], t, now: now)
        XCTAssertEqual(r.map(\.g.key), ["c"]); XCTAssertTrue(r[0].why[0].contains("Studio X"))
        XCTAssertEqual(predictWork(g3, t)?.rating, nil)   // دعم قليل ⇒ لا تنبؤ
    }

    func testMergeWorksFillsOnlyEmptyAndNeverDeletes() {
        let cur: [JSONObject] = [["t": "Scene", "s": "S", "d": "2020-01-01", "r": 5, "n": "ملاحظتي"]]
        let inc: [JSONObject] = [["t": "scene", "s": "S", "d": "2020-01-02", "is": "X1", "n": "ليست لي", "p": "https://i/x.jpg"], ["t": "New", "s": "S"]]
        let m = mergeWorks(cur, inc)
        XCTAssertEqual(m.added, 1); XCTAssertEqual(m.filled, 1)
        XCTAssertEqual(m.list[0]["n"], "ملاحظتي"); XCTAssertEqual(m.list[0]["is"], "X1"); XCTAssertEqual(m.list[0]["r"], 5)
        XCTAssertNotNil(m.list[1]["a"])
    }

    func testSamePersonIsConservative() {
        let a = Candidate(source: "stash", id: "1", name: "Jane Sample", aliases: "Janey", birth: "1995-01-01", country: "US")
        XCTAssertTrue(samePerson(a, Candidate(source: "tpdb", id: "2", name: "Jane Sample", birth: "1995-01-01")))
        XCTAssertFalse(samePerson(a, Candidate(source: "tpdb", id: "3", name: "Jane Sample", birth: "1996-02-02")))
        XCTAssertFalse(samePerson(a, Candidate(source: "tpdb", id: "4", name: "Janet", birth: "")))
    }

    func testReelsRankingDiversityAndSignals() {
        let ps = (0..<5).map { Performer(["id": .string("p\($0)"), "name": .string("P\($0)"), "fav": true]) }
        var groups: [WorkGroup] = []
        for (i, p) in ps.enumerated() { for j in 0..<4 { var g = WorkGroup(key: "w\(i)-\(j)"); g.t = "W\(i)-\(j)"; g.s = "S\(i)"; g.tr = "https://cdn.test/\(i)-\(j).mp4"; g.who = [p]; groups.append(g) } }
        let f = rankReels(groups, buildWorkTaste(groups), ReelSignals(), seed: 3)
        for i in 1..<4 { XCTAssertNotEqual(f[i].g.who[0].id, f[i - 1].g.who[0].id) }
        var s = ReelSignals()
        for _ in 0..<3 { s = recordView(s, groups[0], frac: 2, like: true, secs: 40, hour: 1) }
        XCTAssertGreaterThan(s.aff["pf:p0"]!, 1); XCTAssertNotNil(s.aff["d3|pf:p0"])
        XCTAssertEqual(viewSignal(frac: 0.08, secs: 180), 0.6); XCTAssertEqual(viewSignal(frac: 0.08, secs: 2), -0.35)
        let d = decayReels(ReelSignals(aff: ["a": 2, "b": -2], day: 100), today: 130)
        XCTAssertEqual(d.aff["b"], -2); XCTAssertEqual(d.aff["a"]!, 2 * pow(0.985, 30), accuracy: 1e-9)
        XCTAssertEqual(ReelSignals(json: s.json), s)
    }

    func testNaturalLanguage() {
        let q = parseQuery("شقراء برازيلية بين 20 و25 تقييمها 4 فما فوق")
        XCTAssertEqual(q.hair, ["BLONDE"]); XCTAssertEqual(q.countries, ["BR"]); XCTAssertEqual(q.minAge, 20); XCTAssertEqual(q.maxAge, 25); XCTAssertEqual(q.minRating, 4)
        XCTAssertEqual(parseQuery("سمراء طويلة بدون وشوم").tattoos, false)
        XCTAssertEqual(parseQuery("عمرها 17").minAge, 18)
        XCTAssertTrue(parseQuery("Jane Doe").isEmpty)
        let j = NLQuery.fromJSON(["hair": ["BLONDE", "PURPLE"], "minAge": 12, "sort": "random"])
        XCTAssertEqual(j.hair, ["BLONDE"]); XCTAssertEqual(j.minAge, 18); XCTAssertNil(j.sort)
    }

    func testJournalAndStreaks() {
        XCTAssertEqual(streaks(["2026-11-22", "2026-11-23", "2026-11-24", "2026-11-01"], now: now).best, 3)
        XCTAssertEqual(streaks(["2026-11-22", "2026-11-23"], now: now).current, 2)
        XCTAssertEqual(nextMilestone(240).next, 250)
        XCTAssertEqual(tierFromRating(4.8), "S"); XCTAssertEqual(eloUpdate(winner: 1000, loser: 1000).0, 1016, accuracy: 0.01)
    }

    func testStashHelpers() {
        let s = markerSegments([StashMarker(at: 600, end: 640, label: "A"), StashMarker(at: 100, end: nil, label: "B"), StashMarker(at: 110, end: 115, label: "X")], durationSec: 1800)
        XCTAssertEqual(s.map(\.start), [100, 600]); XCTAssertEqual(s.map(\.len), [30, 40])
        let c = parseVtt("WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nsprite.jpg#xywh=0,0,160,90\n", base: "http://s/scene/1_thumbs.vtt?apikey=K")
        XCTAssertEqual(c.first?.url, "http://s/scene/sprite.jpg?apikey=K"); XCTAssertEqual(c.first?.w, 160)
        XCTAssertEqual(shortSegment(key: "stash:1", durationSec: 1800).len, 45); XCTAssertEqual(shortSegment(key: "x", durationSec: 50).len, 0)
        let m = missingWorks([["t": "A", "s": "S", "d": "2020-01-01", "is": "1"], ["t": "B", "d": "2099-01-01"]], owned: [["t": "zzz", "is": "1"]], now: now)
        XCTAssertEqual(m.total, 1); XCTAssertEqual(m.have, 1)
    }

    func testIntelligenceFindsTraitsCombosAndPredicts() {
        var lib: [Performer] = [], feats: [String: Features] = [:]
        // نمط صناعي: الشقراء القوقازية 5، الشقراء غير القوقازية 3، غير الشقراء 2.5
        for i in 0..<18 {
            let blonde = i % 2 == 0, cauc = i % 3 != 0
            let (p, f) = performer("x\(i)", rating: blonde && cauc ? 5 : blonde ? 3 : 2.5, hair: blonde ? "BLONDE" : "BLACK", eth: cauc ? "CAUCASIAN" : "LATIN", height: 160 + Double(i))
            lib.append(p); feats[p.id] = f
        }
        let s = samples(lib, feats)
        let dna = tasteDNA(s)
        XCTAssertTrue(dna.sufficient)
        XCTAssertEqual(dna.strong.first?.key, "hair_color=BLONDE")
        XCTAssertTrue(dna.combos.contains { $0.id.contains("BLONDE") && $0.id.contains("CAUCASIAN") })
        let pr = predictRating(["hair_color": .s("BLONDE"), "ethnicity": .s("CAUCASIAN"), "country": .s("US"), "height": .n(170), "age": .n(30)], samples: s, dna: dna)
        XCTAssertNotNil(pr); XCTAssertGreaterThanOrEqual(pr!.rating, 4)
        XCTAssertNil(predictRating(["hair_color": .s("BLONDE")], samples: s))   // معلومات ناقصة ⇒ لا تنبؤ
        XCTAssertFalse(archetypes(s).isEmpty)
        XCTAssertNotNil(nextQuestion(dna: dna, answered: []))
        XCTAssertFalse(learnedPreferences(dna: dna, archetypes: [], memory: [:]).isEmpty)
        var log = PredictionLog(json: nil); log.predict("x0", pr!); log.resolve("x0", actual: 3)
        XCTAssertEqual(log.metrics.n, 1)
        XCTAssertEqual(analyze("ما أقوى الأنماط؟", AnalystContext(lib: lib, works: [], feats: feats, dna: dna, predictions: log, workTaste: buildWorkTaste([]))).text.contains("الأنماط"), true)
    }

    func testKnowledgeGraphAndHealth() {
        let a = Performer(["id": "a", "name": "A"]), b = Performer(["id": "b", "name": "B"])
        var g = WorkGroup(key: "w1"); g.t = "W"; g.s = "S"; g.who = [a, b]
        let kg = KnowledgeGraph(lib: [a, b], works: [g], lists: [])
        XCTAssertEqual(kg.path("p:a", "p:b"), ["p:a", "w:w1", "p:b"])
        XCTAssertEqual(kg.related(performer: "a").first?.0, "b")
        let h = libraryHealth([a, Performer(["id": "a2", "name": "A"])])
        XCTAssertTrue(h.issues.contains { $0.kind == "duplicate" })
    }
}
