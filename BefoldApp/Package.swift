// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "befold",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
    ],
    targets: [
        .target(
            name: "BefoldKit",
            path: "BefoldKit",
            resources: [
                .copy("Resources/viewer.html"),
                .copy("Resources/viewer.js"),
                .copy("Resources/style.css"),
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/markdown-it.min.js"),
                .copy("Resources/highlight.min.js"),
                .copy("Resources/dompurify.min.js"),
                .copy("Resources/github.css"),
                .copy("Resources/github-dark.css"),
                .copy("Resources/github-markdown.css"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .executableTarget(
            name: "befold",
            dependencies: [
                "BefoldKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "befold",
            exclude: ["Info.plist", "befold.entitlements", "Resources/__tests__"],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/AppIcon.icns"),
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "befoldTests",
            dependencies: ["befold", "BefoldKit"],
            path: "befoldTests",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
    ]
)
