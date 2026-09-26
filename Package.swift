// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "codex-account-manager",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "codex-account-manager", targets: ["CodexAccountManager"])],
    targets: [
        .executableTarget(name: "CodexAccountManager", path: "Sources"),
        .testTarget(
            name: "CodexAccountManagerTests",
            dependencies: ["CodexAccountManager"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
