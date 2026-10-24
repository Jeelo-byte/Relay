// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "RelayKit",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "RelayKit", targets: ["RelayKit"])],
  dependencies: [
    .package(
      url: "https://github.com/jedisct1/swift-sodium.git",
      revision: "cfd195c76882aa9b997560ca7cb95d72fbf5db00"),
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
    .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "RelayKit",
      dependencies: [
        .product(name: "Sodium", package: "swift-sodium"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ], path: "Sources/RelayKit", resources: [.process("Resources")]),
    .testTarget(name: "RelayKitTests", dependencies: ["RelayKit"], path: "Tests/RelayKitTests"),
  ], swiftLanguageModes: [.v5]
)
