// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmbientMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AmbientMac",
            path: "Sources/AmbientMac",
            // Hackathon pragmatism: Swift 6 strict concurrency turns every
            // AppKit callback into a compile error we do not have time for
            // today. v5 mode keeps @MainActor useful without the data-race gate.
            swiftSettings: [.swiftLanguageMode(.v5)],
            // An SPM executable has no Info.plist, and without one TCC
            // terminates the process the first time it touches the microphone.
            // Section-create the plist straight into __TEXT so `swift run`
            // works with no .app bundle and no Xcode project.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "AmbientMacTests",
            dependencies: ["AmbientMac"],
            path: "Tests/AmbientMacTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
