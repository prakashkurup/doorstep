// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Doorstep",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Doorstep",
            path: "Sources/Doorstep",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DoorstepTests",
            dependencies: ["Doorstep"],
            path: "Tests/DoorstepTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
