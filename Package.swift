// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMDSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeMDSwitcherCore"),
        .executableTarget(
            name: "ClaudeMDSwitcher",
            dependencies: ["ClaudeMDSwitcherCore"],
            path: "Sources/ClaudeMDSwitcher",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ClaudeMDSwitcherCoreTests",
            dependencies: ["ClaudeMDSwitcherCore"],
            path: "tests/ClaudeMDSwitcherCoreTests"
        )
    ]
)
