// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeFM",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeFM",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "ClaudeFMTests", dependencies: ["ClaudeFM"]),
    ]
)
