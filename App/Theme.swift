import SwiftUI
import CoreText
import FavCore

/// هوية «المفضلة»: داكن، ذهبي ونحاسي، ولمسات خمرية. خط IBM Plex Sans Arabic (ترخيص OFL — مضمّن).
enum Theme {
    static let bg = Color(red: 0.06, green: 0.05, blue: 0.08)
    static let surface = Color(red: 0.11, green: 0.09, blue: 0.13)
    static let line = Color.white.opacity(0.08)
    static let gold = Color(red: 0.86, green: 0.70, blue: 0.42)
    static let copper = Color(red: 0.78, green: 0.52, blue: 0.36)
    static let burgundy = Color(red: 0.45, green: 0.12, blue: 0.20)
    static let rose = Color(red: 0.88, green: 0.36, blue: 0.48)
    static let muted = Color.white.opacity(0.55)
    static let ok = Color(red: 0.45, green: 0.78, blue: 0.55)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "IBMPlexSansArabic-Bold"
        case .semibold: name = "IBMPlexSansArabic-SemiBold"
        case .medium: name = "IBMPlexSansArabic-Medium"
        default: name = "IBMPlexSansArabic-Regular"
        }
        return .custom(name, size: size)
    }

    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// بطاقة بخلفية السطح وحد رفيع.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

/// نجوم التقييم (أنصاف).
struct Stars: View {
    let value: Double
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let v = value - Double(i)
                Image(systemName: v >= 1 ? "star.fill" : v >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size)).foregroundStyle(Theme.gold)
            }
        }
    }
}

/// صورة من مرجع محلي (file:) أو رابط https — تملأ إطارها بلا تشويه.
/// الروابط تُحمَّل تلقائيًا فقط من مضيفات المصادر الرسمية؛ غيرها (قد يأتي من ملف مستورد) لا يُطلب إلا بضغطك —
/// حتى لا يكشف ملفٌ اتصالك لموقع مجهول.
struct PhotoView: View {
    @Environment(AppModel.self) private var model
    let ref: String
    @State private var allowedRef: String?   // الموافقة مرتبطة بالرابط نفسه فقط

    static let trustedHosts = ["theporndb.net", "metadataapi.net", "stashdb.org", "wikimedia.org", "wikipedia.org"]
    static func isTrusted(_ u: URL) -> Bool {
        guard let h = u.host?.lowercased() else { return false }
        return trustedHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    var body: some View {
        Group {
            if ref.hasPrefix("file:"), let u = model.store.photoURL(ref), let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if ref.hasPrefix("https://"), let u = URL(string: ref) {
                if Self.isTrusted(u) || allowedRef == ref {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { placeholder }
                    }
                } else {
                    ZStack {
                        placeholder
                        Button { allowedRef = ref } label: {
                            Label("تحميل الصورة من \(u.host ?? "")", systemImage: "arrow.down.circle").font(Theme.font(11))
                        }.buttonStyle(.bordered).padding(6)
                    }
                }
            } else { placeholder }
        }
        .clipped()
    }
    private var placeholder: some View {
        ZStack { Theme.surface; Image(systemName: "person.crop.rectangle").font(.system(size: 26)).foregroundStyle(Theme.muted) }
    }
}

/// حالة فارغة واضحة.
struct EmptyStateView: View {
    let icon: String, title: String, message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Theme.gold)
            Text(title).font(Theme.font(19, .bold))
            Text(message).font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
