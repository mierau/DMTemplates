// swift-tools-version: 6.0
// StringCheese
// Dustin Mierau
// Cared for under the MIT license.

import PackageDescription

let package = Package(
   name: "string-cheese",
   platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
   products: [
      .library(name: "StringCheese", targets: ["StringCheese"]),
   ],
   targets: [
      .target(name: "StringCheese"),
      .testTarget(name: "StringCheeseTests", dependencies: ["StringCheese"]),
   ]
)
