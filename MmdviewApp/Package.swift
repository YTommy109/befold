// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mmdview",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "mmdview",
            path: "mmdview",
            exclude: ["Info.plist", "mmdview.entitlements"],
            resources: [
                .copy("Resources/viewer.html"),
                .copy("Resources/style.css"),
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/markdown-it.min.js"),
            ]
        ),
        .testTarget(
            name: "mmdviewTests",
            dependencies: ["mmdview"],
            path: "mmdviewTests"
        ),
    ]
)
