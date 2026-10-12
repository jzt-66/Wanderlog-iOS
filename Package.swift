// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WanderlogCore", platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "WanderlogCore", targets: ["WanderlogCore"])],
  targets: [
    .target(name: "WanderlogCore", path: "Core"),
    .testTarget(name: "WanderlogCoreTests", dependencies: ["WanderlogCore"], path: "Tests")
  ]
)
