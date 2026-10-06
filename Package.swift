// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OrdinaryNotchFree", platforms: [.macOS(.v14)], products: [.executable(name: "OrdinaryNotch", targets: ["OrdinaryNotch"])], targets: [
    .target(name: "FanCore"), .target(name: "ActivityCore"),
    .executableTarget(name: "OrdinaryActivityBridge", dependencies: ["ActivityCore"]),
    .executableTarget(name: "OrdinaryNotch", dependencies: ["FanCore", "ActivityCore"]),
    .testTarget(name: "OrdinaryNotchTests", dependencies: ["OrdinaryNotch", "FanCore", "ActivityCore"])
])
