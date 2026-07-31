// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "befold",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
    ],
    targets: [
        .target(
            name: "BefoldCLI",
            dependencies: ["BefoldKit"],
            path: "BefoldCLI",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "BefoldKit",
            path: "BefoldKit",
            exclude: ["Resources/__tests__"],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/viewer.html"),
                .copy("Resources/viewer.js"),
                .copy("Resources/viewer-main.js"),
                .copy("Resources/style.css"),
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/markdown-it.min.js"),
                .copy("Resources/highlight.min.js"),
                .copy("Resources/dompurify.min.js"),
                .copy("Resources/github.css"),
                .copy("Resources/github-dark.css"),
                .copy("Resources/github-markdown.css"),
                .copy("Resources/THIRD_PARTY_LICENSES.md"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "BefoldRenderKit",
            dependencies: ["BefoldKit"],
            path: "BefoldRenderKit",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .executableTarget(
            name: "befold",
            dependencies: [
                "BefoldKit",
                "BefoldCLI",
                "BefoldRenderKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "befold",
            exclude: ["Info.plist", "befold.entitlements"],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AboutOGP.png"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .executableTarget(
            name: "befold-cli",
            dependencies: [
                "BefoldCLI",
                "BefoldKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "befold-cli",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        // テスト用の共有ヘルパー。befoldTests / befoldCLITests の双方から使うため
        // 独立したターゲットに置く。GUI 本体(befold)や BefoldRenderKit・BefoldKit への
        // 依存を持ち込まないよう、依存は Foundation と Testing(swift-testing。待機
        // ヘルパーが Issue.record / SourceLocation / TimeLimitTrait を使う)のみに保つこと。
        // Testing はテストホスト外では解決できないため、リンクするのはテストターゲットに限る。
        .target(
            name: "BefoldTestSupport",
            path: "BefoldTestSupport",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "befoldTests",
            dependencies: [
                "befold", "BefoldKit", "BefoldCLI", "BefoldRenderKit", "BefoldTestSupport",
            ],
            path: "befoldTests",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "befoldCLITests",
            dependencies: ["befold-cli", "BefoldCLI", "BefoldKit", "BefoldTestSupport"],
            path: "befoldCLITests",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
    ]
)
