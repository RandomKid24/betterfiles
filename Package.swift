// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "BetterLauncher",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Shared"),
        .target(name: "LauncherCore"),
        .executableTarget(name: "BetterLauncher", dependencies: ["LauncherCore", "Shared"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
        .target(name: "FilesCore"),
        .executableTarget(name: "BetterFiles", dependencies: ["FilesCore", "Shared"]),
        .testTarget(name: "FilesCoreTests", dependencies: ["FilesCore"]),
    ],
    swiftLanguageModes: [.v5]
)
