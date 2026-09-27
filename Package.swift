// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "llm-account-switcher",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "llm-account-switcher", targets: ["LLMAccountSwitcher"])],
    targets: [
        .executableTarget(name: "LLMAccountSwitcher", path: "Sources"),
        .testTarget(
            name: "LLMAccountSwitcherTests",
            dependencies: ["LLMAccountSwitcher"],
            path: "Tests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
