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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "SnapshotSafari",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: [
                "Info.plist",
                "Resources/Entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("OSAKit")
            ]
        ),
        .testTarget(
            name: "SnapshotSafariTests",
            dependencies: ["SnapshotSafari"]
        )
    ]
)
