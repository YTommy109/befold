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
        // libgit2 の C ソースを SPM の C ターゲットとしてビルドするパッケージ。
        // プリビルドの XCFramework ではないため cmake を必要としない。
        // exact 指定にするのは、libgit2 の API/ABI ではなくリポジトリ形式の対応範囲
        // （extensions の許容一覧）が版で変わり、開けるリポジトリの集合が動くため。
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2"),
    ],
    targets: [
        // git_libgit2_opts（C 可変長引数）を Swift から呼ぶための薄い C シム。
        // 詳細は CGitShim/include/CGitShim.h の doc を参照。
        .target(
            name: "CGitShim",
            dependencies: [.product(name: "libgit2", package: "libgit2")],
            path: "CGitShim"
        ),
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
                // viewer-src/ から esbuild で生成し、成果物もコミットしているバンドル
                // （生成手順は viewer-src/README.md）。ビルド時に Node を要求しないため、
                // ここでは通常のリソースとして扱う。
                .copy("Resources/viewer-bundle.js"),
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
                // git 連携は本体アプリだけが使う。QuickLook 拡張(appex)と CLI へは
                // 依存を入れない(appex に libgit2 がコンパイルされない構造にしておく)。
                "CGitShim",
                .product(name: "libgit2", package: "libgit2"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "befold",
            exclude: ["Info.plist", "befold.entitlements"],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/befold-review-skill.md"),
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
                // GitLibrary のテストが libgit2 の C API と C シムを直接叩く
                // (検索パスの往復・config 読み出しの検証)。
                "CGitShim",
                .product(name: "libgit2", package: "libgit2"),
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
