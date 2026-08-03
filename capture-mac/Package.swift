// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmbientMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AmbientMac",
            path: "Sources/AmbientMac"
        ),
        .testTarget(
            name: "AmbientMacTests",
            dependencies: ["AmbientMac"],
            path: "Tests/AmbientMacTests"
        ),
    ]
)
