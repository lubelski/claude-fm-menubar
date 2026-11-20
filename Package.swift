// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeFM",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudeFM"),
    ]
)
