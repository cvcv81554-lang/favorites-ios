import Foundation

// الأعمال — منقولة من التطبيق السابق: «نفس العمل؟» (sameWork) وتوحيد الأعمال عبر الممثلات (groupWorks).

/// معرّفات العمل في المصادر الرسمية: is:<StashDB> ثم ip:<ThePornDB>.
public func sceneIdsOf(_ w: JSONObject) -> [String] {
    let s = w["is"]?.text ?? "", p = w["ip"]?.text ?? ""
    return (s.isEmpty ? [] : ["is:\(s)"]) + (p.isEmpty ? [] : ["ip:\(p)"])
}

/// تعارض: نفس المصدر بمعرّفين مختلفين ⇒ عملان مختلفان حتمًا.
public func idConflict(_ a: JSONObject, _ b: JSONObject) -> Bool {
    func diff(_ k: String) -> Bool { let x = a[k]?.text ?? "", y = b[k]?.text ?? ""; return !x.isEmpty && !y.isEmpty && x != y }
    return diff("is") || diff("ip")
}
public func sharesId(_ a: JSONObject, _ b: JSONObject) -> Bool { !Set(sceneIdsOf(a)).isDisjoint(with: sceneIdsOf(b)) }

private func dayNumber(_ s: String) -> Int? {
    guard s.count >= 10, let y = Int(s.prefix(4)), let m = Int(s.dropFirst(5).prefix(2)), let d = Int(s.dropFirst(8).prefix(2)),
          let date = gregorian.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
    return Int(date.timeIntervalSince1970 / 86400)
}
private func compact(_ s: String) -> String { normTitle(s).replacingOccurrences(of: " ", with: "") }

/// نفس العمل؟ معرّف مشترك ⇒ نعم؛ تعارض معرّف من نفس المصدر ⇒ لا؛
/// وإلا: العنوان نفسه بعد التطبيع + الاستوديو متقارب (أو غائب) + التاريخ متقارب (±3 أيام) إن وُجد في الاثنين.
public func sameWork(_ a: JSONObject, _ b: JSONObject) -> Bool {
    if sharesId(a, b) { return true }
    if idConflict(a, b) { return false }
    let ta = normTitle(a["t"]?.text ?? "")
    if ta.isEmpty || ta != normTitle(b["t"]?.text ?? "") { return false }
    var days: Int? = nil
    if let x = dayNumber(a["d"]?.text ?? ""), let y = dayNumber(b["d"]?.text ?? "") { days = abs(x - y) }
    if let d = days, d > 3 { return false }
    let sa = compact(a["s"]?.text ?? ""), sb = compact(b["s"]?.text ?? "")
    let studioOk = sa.isEmpty || sb.isEmpty || sa == sb || sa.contains(sb) || sb.contains(sa)
    return studioOk || days == 0
}

/// مرجع عمل داخل سجل ممثلة (للكتابة عليه).
public struct WorkRef: Hashable, Sendable { public let performerId: String; public let index: Int }

/// عمل موحّد عبر الممثلات: أول قيمة غير فارغة تفوز، التقييم = الأعلى، والحالات (شوهد، للمشاهدة…) = أي مرجع.
public struct WorkGroup: Identifiable, Sendable {
    public let key: String
    public var id: String { key }
    public var t = "", s = "", d = "", y = "", p = "", u = "", n = "", ds = "", wd = "", tr = ""
    public var r = 0, du = 0, a: Int64 = 0
    public var seen = false, q = false, upc = false, fav = false, rec = false
    public var tg: [String] = [], ls: [String] = []
    public var rc: [String: Int] = [:]
    public var who: [Performer] = []
    public var refs: [WorkRef] = []
    public init(key: String) { self.key = key }

    public var date: String { !d.isEmpty ? d : (!y.isEmpty ? "\(y)-01-01" : "") }
    public func isUpcoming(now: Date = Date()) -> Bool {
        if seen { return false }
        if upc { return true }
        if !d.isEmpty { return d > todayStr(now) }
        if let yy = Int(y) { return yy > ymd(now).0 }
        return false
    }

    mutating func absorb(_ w: JSONObject, _ it: Performer, _ idx: Int) {
        func s0(_ k: String) -> String { w[k]?.text ?? "" }
        if t.isEmpty { t = s0("t") }
        if s.isEmpty { s = s0("s") }
        if d.isEmpty && !s0("d").isEmpty { d = s0("d"); y = String(d.prefix(4)) }
        if y.isEmpty { y = s0("y") }
        if p.isEmpty { p = s0("p") }
        if tr.isEmpty { tr = s0("tr") }
        if u.isEmpty { u = s0("u") }
        if n.isEmpty { n = s0("n") }
        if ds.isEmpty { ds = s0("ds") }
        let rr = w["r"]?.int ?? 0; if rr > r { r = rr }
        let dd = w["du"]?.int ?? 0; if du == 0 && dd > 0 { du = dd }
        let aa = Int64(w["a"]?.number ?? 0); if aa > a { a = aa }
        if w["w"]?.isOn == true { seen = true; if s0("wd") > wd { wd = s0("wd") } }
        if w["q"]?.isOn == true { q = true }
        if w["upc"]?.isOn == true { upc = true }
        if w["fav"]?.isOn == true { fav = true }
        if w["rec"]?.isOn == true { rec = true }
        for (k, v) in w["rc"]?.object ?? [:] { if let x = v.int, x > 0, (rc[k] ?? 0) < x { rc[k] = x } }
        for x in w["tg"]?.array ?? [] { if let s = x.string, !tg.contains(s) { tg.append(s) } }
        for x in w["ls"]?.array ?? [] { if let s = x.string, !ls.contains(s) { ls.append(s) } }
        if !who.contains(where: { $0.id == it.id }) { who.append(it) }
        refs.append(WorkRef(performerId: it.id, index: idx))
    }
}

/// توحيد الأعمال عبر الممثلات (union-find):
/// 1) الأعمال ذات المعرّفات تُجمع بمعرّفاتها (StashDB وThePornDB في العمل نفسه يربطان المصدرين)، بلا دمج متعارض من نفس المصدر.
/// 2) أعمال المصدرين بنفس العنوان المطبّع تُربط إن كانت «نفس العمل».
/// 3) الأعمال بلا معرّف تنضم لمجموعة واحدة مطابقة إن وُجدت، وإلا مفتاح wkey(t)|wkey(s).
public func groupWorks(_ items: [Performer]) -> [WorkGroup] {
    var parent: [String: String] = [:]
    var kinds: [String: [String: String]] = [:]
    func find(_ x: String) -> String {
        var r = x
        while let p = parent[r], p != r { r = p }
        var c = x
        while let p = parent[c], p != r { parent[c] = r; c = p }
        return r
    }
    func add(_ x: String) { if parent[x] == nil { parent[x] = x; kinds[x] = [String(x.prefix(2)): x] } }
    @discardableResult func union(_ a: String, _ b: String) -> Bool {
        var ra = find(a), rb = find(b)
        if ra == rb { return true }
        let ka = kinds[ra]!, kb = kinds[rb]!
        for (k, v) in ka { if let o = kb[k], o != v { return false } }   // تعارض من نفس المصدر
        if ra.hasPrefix("ip:") && rb.hasPrefix("is:") { swap(&ra, &rb) }   // جذر StashDB مفضّل
        parent[rb] = ra
        kinds[ra] = kinds[rb]!.merging(kinds[ra]!) { _, x in x }
        kinds[rb] = nil
        return true
    }
    var withId: [(JSONObject, Performer, Int)] = [], noId: [(JSONObject, Performer, Int)] = []
    for it in items {
        let ws = it.works
        for (i, w) in ws.enumerated() {
            if wKeyOf(w) == "|" { continue }
            let ids = sceneIdsOf(w)
            if ids.isEmpty { noId.append((w, it, i)); continue }
            ids.forEach(add)
            for x in ids.dropFirst() { union(ids[0], x) }
            withId.append((w, it, i))
        }
    }
    var byT: [String: [JSONObject]] = [:], tOrder: [String] = []
    for (w, _, _) in withId { let k = normTitle(w["t"]?.text ?? ""); if byT[k] == nil { tOrder.append(k) }; byT[k, default: []].append(w) }
    for k in tOrder {
        let l = byT[k]!; if l.count < 2 { continue }
        for a in 0..<l.count { for b in (a + 1)..<l.count {
            if find(sceneIdsOf(l[a])[0]) != find(sceneIdsOf(l[b])[0]) && sameWork(l[a], l[b]) { union(sceneIdsOf(l[a])[0], sceneIdsOf(l[b])[0]) }
        } }
    }
    var map: [String: WorkGroup] = [:], order: [String] = []
    var reps: [String: [(String, JSONObject)]] = [:]
    func absorb(_ k: String, _ w: JSONObject, _ it: Performer, _ i: Int) {
        if map[k] == nil { map[k] = WorkGroup(key: k); order.append(k) }
        map[k]!.absorb(w, it, i)
    }
    for (w, it, i) in withId {
        let k = find(sceneIdsOf(w)[0])
        absorb(k, w, it, i)
        let t = normTitle(w["t"]?.text ?? "")
        if !(reps[t] ?? []).contains(where: { $0.0 == k }) { reps[t, default: []].append((k, w)) }
    }
    for (w, it, i) in noId {
        let m = Set((reps[normTitle(w["t"]?.text ?? "")] ?? []).filter { sameWork($0.1, w) }.map { $0.0 })
        absorb(m.count == 1 ? m.first! : wKeyOf(w), w, it, i)
    }
    return order.map { map[$0]! }
}

/// يطبّق تعديلًا على كل نسخ العمل عند كل الممثلات ويعيد السجلات المعدّلة (للحفظ).
public func applyToGroup(_ g: WorkGroup, in library: [String: Performer], _ fn: (inout JSONObject) -> Void) -> [Performer] {
    var byP: [String: [Int]] = [:]
    for r in g.refs { byP[r.performerId, default: []].append(r.index) }
    return byP.compactMap { pid, idxs in
        guard let p = library[pid] else { return nil }
        var ws = p.works
        for i in idxs where i < ws.count { fn(&ws[i]) }
        return p.with(["works": .array(ws.map { .object($0) })])
    }
}
