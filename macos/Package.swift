// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "partscribe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "partscribe",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the binary so TCC can attribute the
                // system-audio-capture permission to partscribe itself when it
                // runs as a LaunchAgent (no .app bundle to carry a plist).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/partscribe/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "PartScribeTests",
            dependencies: ["partscribe"]
        ),
    ]
)
