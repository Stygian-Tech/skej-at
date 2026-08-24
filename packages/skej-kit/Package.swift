// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkejKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SkejKit", targets: ["SkejKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.5"),
    ],
    targets: [
        .target(
            name: "SkejKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/SkejKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .testTarget(
            name: "SkejKitTests",
            dependencies: ["SkejKit"],
            path: "Tests/SkejKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
