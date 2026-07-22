// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMDSwitcher",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .target(name: "ClaudeMDSwitcherCore"),
        .executableTarget(
            name: "ClaudeMDSwitcher",
            dependencies: [
                "ClaudeMDSwitcherCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ClaudeMDSwitcher",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "ClaudeMDSwitcherCoreTests",
            dependencies: ["ClaudeMDSwitcherCore"],
            path: "tests/ClaudeMDSwitcherCoreTests"
        )
    ]
)
