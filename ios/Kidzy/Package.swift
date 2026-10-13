// swift-tools-version: 6.0
// KidzyCore holds the app's logic without UIKit so it is tested on the Mac with `swift test`.
import PackageDescription

let package = Package(
    name: "KidzyCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "KidzyCore", targets: ["KidzyCore"])],
    targets: [
        .target(name: "KidzyCore", path: "Shared"),
        .testTarget(name: "KidzyCoreTests", dependencies: ["KidzyCore"], path: "Tests/KidzyCoreTests"),
    ]
)
