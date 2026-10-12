// swift-tools-version: 6.0
// StringCheese benchmarks. Kept in their own package so the library package
// stays free of executables. Run ./run.sh from this directory.

import PackageDescription

let package = Package(
   name: "StringCheeseBenchmarks",
   platforms: [.macOS(.v13)],
   dependencies: [
      .package(name: "string-cheese", path: ".."),
   ],
   targets: [
      .executableTarget(
         name: "SwiftBench",
         dependencies: [.product(name: "StringCheese", package: "string-cheese")]
      ),
   ]
)
