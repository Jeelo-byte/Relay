// swift-tools-version: 6.0
import PackageDescription

var dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/jedisct1/swift-sodium.git", revision: "cfd195c76882aa9b997560ca7cb95d72fbf5db00"),
  .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
]
var products: [Target.Dependency] = [
  .product(name: "Sodium", package: "swift-sodium"),
  .product(name: "GRDB", package: "GRDB.swift")
]
// The pinned Gemma runtime requires Swift 6.2. Older Xcode can build the
// complete manual client without resolving an incompatible MLX dependency.
#if compiler(>=6.2)
dependencies += [
  .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
  .package(url: "https://github.com/huggingface/swift-huggingface", exact: "0.9.0"),
  .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0")
]
products += [
  .product(name: "MLXLLM", package: "mlx-swift-lm"),
  .product(name: "MLXVLM", package: "mlx-swift-lm"),
  .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
  .product(name: "HuggingFace", package: "swift-huggingface"),
  .product(name: "Tokenizers", package: "swift-transformers")
]
#endif
let package = Package(
  name: "RelayKit", platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "RelayKit", targets: ["RelayKit"])],
  dependencies: dependencies,
  targets: [
    .target(name: "RelayKit", dependencies: products, path: "Sources/RelayKit", resources: [.process("Resources/RelayAssets.xcassets"), .process("Resources/normalize.js"), .process("Resources/placeholder.txt"), .copy("Resources/MessageHost")]),
    .testTarget(name: "RelayKitTests", dependencies: ["RelayKit"], path: "Tests/RelayKitTests")
  ], swiftLanguageModes: [.v5]
)
