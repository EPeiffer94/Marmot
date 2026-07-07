// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marmot",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Marmot",
            path: "Sources/Marmot"
        ),
        .testTarget(
            name: "MarmotTests",
            dependencies: ["Marmot"],
            path: "Tests/MarmotTests"
        )
    ]
)
