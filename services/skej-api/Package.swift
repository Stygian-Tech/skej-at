// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkejAPI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SkejGateway", targets: ["SkejGateway"]),
        .executable(name: "SkejAPI", targets: ["SkejAPI"]),
    ],
    dependencies: [
        .package(path: "../../packages/skej-kit"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.0"),
    ],
    targets: [
        .target(
            name: "SkejGateway",
            dependencies: [
                .product(name: "SkejKit", package: "skej-kit"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/SkejGateway",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SkejAPI",
            dependencies: ["SkejGateway", .product(name: "SkejKit", package: "skej-kit")],
            path: "Sources/SkejAPI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SkejGatewayTests",
            dependencies: [
                "SkejGateway",
                .product(name: "SkejKit", package: "skej-kit"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/SkejKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
