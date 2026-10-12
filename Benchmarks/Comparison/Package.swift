// swift-tools-version: 6.0
// Compares StringCheese with other Swift template engines. Kept apart from the
// main benchmarks so those build with no dependencies. Run ./run.sh from this
// directory.

import PackageDescription

let package = Package(
   name: "StringCheeseComparison",
   platforms: [.macOS(.v13)],
   dependencies: [
      .package(name: "string-cheese", path: "../.."),
      .package(url: "https://github.com/stencilproject/Stencil", from: "0.15.1"),
      .package(url: "https://github.com/hummingbird-project/swift-mustache", from: "2.0.0"),
      .package(url: "https://github.com/vapor/leaf-kit", from: "1.13.0"),
      .package(url: "https://github.com/apple/swift-nio", from: "2.81.0"),
   ],
   targets: [
      .executableTarget(
         name: "Compare",
         dependencies: [
            .product(name: "StringCheese", package: "string-cheese"),
            .product(name: "Stencil", package: "Stencil"),
            .product(name: "Mustache", package: "swift-mustache"),
            .product(name: "LeafKit", package: "leaf-kit"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
         ],
         swiftSettings: [.swiftLanguageMode(.v5)]
      ),
   ]
)
