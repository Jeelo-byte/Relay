// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Relay",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RelayKit", targets: ["RelayKit"]), .executable(name: "Relay", targets: ["RelayApp"])],
    dependencies: [
        .package(url: "https://github.com/jedisct1/swift-sodium.git", branch: "master"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
    ],
    targets: [
        .target(name: "RelayKit", dependencies: [.product(name: "Sodium", package: "swift-sodium"), .product(name: "GRDB", package: "GRDB.swift")], path: "apple/RelayKit/Sources/RelayKit", resources: [.process("Resources")]),
        .executableTarget(name: "RelayApp", dependencies: ["RelayKit"], path: "apple/RelayApp"),
        .testTarget(name: "RelayKitTests", dependencies: ["RelayKit"], path: "apple/RelayKit/Tests/RelayKitTests")
    ], swiftLanguageModes: [.v5]
)
