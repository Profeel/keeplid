// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepLid",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KeepLidCore", targets: ["KeepLidCore"]),
        .executable(name: "keeplid", targets: ["keeplid-cli"]),
        .executable(name: "KeepLidApp", targets: ["KeepLidApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KeepLidCore",
            dependencies: [],
            path: "Sources/KeepLidCore"
        ),
        .executableTarget(
            name: "keeplid-cli",
            dependencies: ["KeepLidCore"],
            path: "Sources/keeplid-cli"
        ),
        .executableTarget(
            name: "KeepLidApp",
            dependencies: ["KeepLidCore"],
            path: "Sources/KeepLidApp"
        )
    ]
)
