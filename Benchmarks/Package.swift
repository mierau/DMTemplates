// swift-tools-version: 6.0
// DMTemplates benchmarks. Kept in their own package so the library package
// stays free of executables. Run ./run.sh from this directory.

import PackageDescription

let package = Package(
   name: "DMTemplatesBenchmarks",
   dependencies: [
      .package(name: "DMTemplates", path: ".."),
   ],
   targets: [
      .executableTarget(
         name: "SwiftBench",
         dependencies: [.product(name: "DMTemplates", package: "DMTemplates")]
      ),
   ]
)
