// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Food4ThoughtCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Food4ThoughtCore", targets: ["Food4ThoughtCore"])
    ],
    targets: [
        .target(name: "Food4ThoughtCore"),
        .testTarget(name: "Food4ThoughtCoreTests", dependencies: ["Food4ThoughtCore"])
    ]
)
