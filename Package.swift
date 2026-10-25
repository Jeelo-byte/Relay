// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Relay", platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.executable(name: "Relay", targets: ["RelayApp"])],
  dependencies: [.package(path: "apple/RelayKit")],
  targets: [
    .executableTarget(
      name: "RelayApp", dependencies: [.product(name: "RelayKit", package: "RelayKit")],
      path: "apple/RelayApp", exclude: ["Assets.xcassets", "Relay.macOS.entitlements"]),
    .testTarget(
      name: "RelayKitTests", dependencies: [.product(name: "RelayKit", package: "RelayKit")],
      path: "apple/RelayKit/Tests/RelayKitTests"),
    .testTarget(
      name: "RelayAppTests", dependencies: ["RelayApp"],
      path: "apple/RelayAppTests"),
  ], swiftLanguageModes: [.v5])
