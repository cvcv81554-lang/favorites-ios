import Foundation

// بوابة +18 — منقولة حرفيًا من التطبيق السابق (sdAge / minorRec / adultOk) بنفس الدلالات:
// - تاريخ ناقص ⇒ أسوأ حالة: سنة فقط = 31 ديسمبر، سنة وشهر = آخر يوم في الشهر.
// - تاريخ مستحيل (مثل 2001-02-30) أو مستقبلي ⇒ غير صالح ⇒ يُرفض.
// قاعدة لا تُكسر: لا تُضعَف أبدًا، وتُطبَّق قبل أي طلب شبكة لأي سجل أو مرشح. لا يُستنتج العمر من الصور أبدًا.

public struct AgeResult: Equatable, Sendable {
    public let age: Int?
    public let invalid: Bool
    public static let none = AgeResult(age: nil, invalid: false)
    public static let bad = AgeResult(age: nil, invalid: true)
    public static func of(_ a: Int) -> AgeResult { AgeResult(age: a, invalid: false) }
    public var isNone: Bool { age == nil && !invalid }
}

/// تقويم ميلادي ثابت (UTC) لحساب الأعمار بلا تأثير المنطقة الزمنية.
let gregorian: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

/// (سنة، شهر، يوم) لتاريخ «اليوم» بالتقويم المحلي للجهاز (كما في التطبيق السابق).
func ymd(_ d: Date) -> (Int, Int, Int) {
    var c = Calendar(identifier: .gregorian); c.timeZone = .current
    let x = c.dateComponents([.year, .month, .day], from: d)
    return (x.year!, x.month!, x.day!)
}

/// العمر بالسنوات الكاملة (يوم الميلاد نفسه يُحتسب).
func ageOn(birth: (Int, Int, Int), today: (Int, Int, Int)) -> Int {
    var a = today.0 - birth.0
    if today.1 < birth.1 || (today.1 == birth.1 && today.2 < birth.2) { a -= 1 }
    return a
}

func daysIn(year: Int, month: Int) -> Int {
    gregorian.range(of: .day, in: .month, for: gregorian.date(from: DateComponents(year: year, month: month, day: 1))!)!.count
}

private let ageRe = try! NSRegularExpression(pattern: #"^(\d{4})(?:-(\d{1,2}))?(?:-(\d{1,2}))?(?:$|[T\s])"#)

/// sdAge: يقبل YYYY أو YYYY-MM أو YYYY-MM-DD (ويتجاهل ما بعد T أو مسافة).
public func sdAge(_ raw: JSONValue?, now: Date = Date()) -> AgeResult {
    let s = (raw?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return .none }
    let ns = s as NSString
    guard let m = ageRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return .bad }
    func g(_ i: Int) -> Int? { let r = m.range(at: i); return r.location == NSNotFound ? nil : Int(ns.substring(with: r)) }
    let y = g(1)!
    let mo = g(2) ?? 12
    if mo < 1 || mo > 12 { return .bad }
    let last = daysIn(year: y, month: mo)
    let da = g(3) ?? last
    if da < 1 || da > last { return .bad }
    let t = ymd(now)
    if (y, mo, da) > t { return .bad }   // تاريخ في المستقبل
    return .of(ageOn(birth: (y, mo, da), today: t))
}

public func sdAge(_ s: String, now: Date = Date()) -> AgeResult { sdAge(.string(s), now: now) }

/// سجل في المكتبة: قاصر إن كان له تاريخ ميلاد يقول أقل من 18، أو تاريخه غير مفهوم. (بلا تاريخ ⇒ ليس قاصرًا هنا، لكنه غير «موثّق».)
public func minorRec(_ x: JSONObject?, now: Date = Date()) -> Bool {
    guard let x else { return false }
    let b = x["birth"]
    if b == nil || b!.isNull || b!.text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
    let a = sdAge(b, now: now)
    return a.invalid || (a.age ?? 0) < 18
}

/// مرشح خارجي (له birthRaw أو birth): مقبول فقط إن كان بلا تاريخ أو تاريخه يؤكد 18+.
public func adultOk(_ m: JSONObject?, now: Date = Date()) -> Bool {
    guard let m else { return false }
    let raw = (m["birthRaw"]?.text ?? "").isEmpty ? m["birth"] : m["birthRaw"]
    let a = sdAge(raw, now: now)
    return a.isNone || (!a.invalid && (a.age ?? 0) >= 18)
}

/// فئة 18–21 في «اكتشف»: تاريخ كامل مؤكد فقط (لا سنة وحدها ولا سنة وشهر).
public func verifiedYoungAdult(_ birth: String, now: Date = Date()) -> Int? {
    guard birth.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
    let a = sdAge(birth, now: now)
    guard !a.invalid, let age = a.age, age >= 18, age <= 21 else { return nil }
    return age
}
