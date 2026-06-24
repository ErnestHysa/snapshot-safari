// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapshotSafari",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SnapshotSafari", targets: ["SnapshotSafari"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SnapshotSafari",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
