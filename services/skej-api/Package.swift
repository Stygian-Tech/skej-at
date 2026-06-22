// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkejAPI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SkejKit", targets: ["SkejKit"]),
        .executable(name: "SkejAPI", targets: ["SkejAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.0"),
    ],
    targets: [
        .target(
            name: "SkejKit",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Crypto", package: "swift-crypto"),
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
        .executableTarget(
            name: "SkejAPI",
            dependencies: ["SkejKit"],
            path: "Sources/SkejAPI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SkejKitTests",
            dependencies: [
                "SkejKit",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/SkejKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
