// swift-tools-version:5.9
import PackageDescription

// FavCore: كل منطق «المفضلة» بلا واجهة — النموذج، بوابة +18، التنقية، الأعمال، النسخ الاحتياطي، التخزين.
// يُختبر بـ `swift test` على macOS (GitHub Actions) دون محاكي.
let package = Package(
    name: "FavCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FavCore", targets: ["FavCore"])],
    targets: [
        .target(name: "FavCore", path: "Sources/FavCore"),
        .testTarget(name: "FavCoreTests", dependencies: ["FavCore"], path: "Tests/FavCoreTests",
                    resources: [.copy("Fixtures")]),
    ]
)
