// swift-tools-version: 6.0
// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import PackageDescription

let package = Package(
   name: "DMTemplates",
   platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
   products: [
      .library(name: "DMTemplates", targets: ["DMTemplates"]),
   ],
   targets: [
      .target(name: "DMTemplates"),
      .testTarget(name: "DMTemplatesTests", dependencies: ["DMTemplates"]),
   ]
)
