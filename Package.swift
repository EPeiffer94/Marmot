// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marmot",
    platforms: [
        .macOS(.v13)
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
