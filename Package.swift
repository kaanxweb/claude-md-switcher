// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMDSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeMDSwitcher",
            path: "Sources/ClaudeMDSwitcher",
            exclude: ["Info.plist"]
        )
    ]
)
