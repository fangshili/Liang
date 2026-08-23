// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Liang",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Liang", targets: ["Liang"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "Liang",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Liang",
            resources: [
                .copy("Resources/hooks/liang-bridge.sh"),
                .copy("Resources/hooks/claude-bridge.sh"),
                .copy("Resources/hooks/codex-bridge.sh"),
                .copy("Resources/Icons/cursor-icon.png"),
                .copy("Resources/Icons/claude-icon.png"),
                .copy("Resources/Icons/codex-task-icon.png"),
                .copy("Resources/Icons/codex-onboarding-icon.png")
            ]
        )
    ]
)
