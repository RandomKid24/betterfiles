// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "BetterLauncher",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "BetterLauncher", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ],
    swiftLanguageModes: [.v5]
)
