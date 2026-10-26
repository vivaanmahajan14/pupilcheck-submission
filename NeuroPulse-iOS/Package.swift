// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeuroPulse",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NeuroPulse",
            targets: ["NeuroPulse"]
        ),
        .executable(
            name: "NeuroPulseTestSuite",
            targets: ["NeuroPulseTestSuite"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NeuroPulse",
            dependencies: [],
            path: "Sources/NeuroPulse"
        ),
        .executableTarget(
            name: "NeuroPulseTestSuite",
            dependencies: ["NeuroPulse"],
            path: "Tests/NeuroPulseTestSuite"
        ),
        .testTarget(
            name: "NeuroPulseTests",
            dependencies: ["NeuroPulse"],
            path: "Tests/NeuroPulseTests"
        ),
    ]
)
