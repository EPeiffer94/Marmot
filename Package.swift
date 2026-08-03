// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marmot",
    platforms: [
        // macOS 26 floor: Marmot is built around Liquid Glass and the
        // modern SwiftUI surface. String form so the manifest still parses
        // on toolchains whose SupportedPlatform enum predates .v26.
        .macOS("26.0")
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Marmot",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Marmot"
        ),
        .testTarget(
            name: "MarmotTests",
            dependencies: ["Marmot"],
            path: "Tests/MarmotTests"
        )
    ]
)
