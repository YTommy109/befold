# QuickLook 対応 事前リファクタリング Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アプリ本体と将来の QuickLook extension でレンダリングパイプラインを共有できるよう、コードを整理する

**Architecture:** ViewerStore から読み込みロジックを `ContentLoader` として切り出し、`loadViewerHTML` の Bundle 参照を引数化し、共有可能なコード群を `BefoldKit` ライブラリターゲットにまとめる。既存テストは全パスを維持する。

**Tech Stack:** Swift 6 / SPM / XcodeGen

## Global Constraints

- macOS 14+ / Swift 6 strict concurrency
- `swift test` 全パス必須
- QuickLook extension 自体はこのブランチでは作らない（土台整理のみ）
- 既存の public API・動作を変更しない

---

### Task 1: ContentLoader の切り出し

**Files:**
- Create: `BefoldApp/befold/Viewer/ContentLoader.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift:117-150`
- Test: `BefoldApp/befoldTests/ContentLoaderTests.swift`

**Interfaces:**
- Consumes: `FileReading` protocol, `FileType`
- Produces: `ContentLoader` struct with `func load(from url: URL, fileType: FileType) -> LoadedContent`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import befold

@Suite
struct ContentLoaderTests {
    private let loader = ContentLoader(fileReader: DefaultFileReader())

    @Test("テキストファイルを正常に読み込む")
    func loadTextFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "test-\(UUID()).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(!result.isUnsupported)
        #expect(result.content == "hello")
    }

    @Test("サイズ超過ファイルは isUnsupported")
    func oversizedFileIsUnsupported() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "big-\(UUID()).txt")
        let bigData = Data(repeating: 0x41, count: ContentLoader.maxFileSizeBytes + 1)
        try bigData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(result.isUnsupported)
        #expect(result.content == "")
    }

    @Test("バイナリファイルは isUnsupported")
    func binaryFileIsUnsupported() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "bin-\(UUID()).dat")
        var data = Data(repeating: 0x00, count: 100)
        data[0] = 0xFF
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .code(language: "plaintext"))
        #expect(result.isUnsupported)
    }

    @Test("画像ファイルは base64 エンコードされる")
    func imageFileIsBase64Encoded() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "img-\(UUID()).png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = loader.load(from: tmp, fileType: .image(mimeType: "image/png"))
        #expect(!result.isUnsupported)
        #expect(result.content == data.base64EncodedString())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd BefoldApp && swift test --filter ContentLoaderTests 2>&1 | tail -5`
Expected: compilation error — `ContentLoader` not defined

- [ ] **Step 3: Write ContentLoader implementation**

```swift
import Foundation

struct ContentLoader: Sendable {
    static let maxFileSizeBytes = 10 * 1024 * 1024
    static let maxBinaryFileSizeBytes = 50 * 1024 * 1024

    struct LoadedContent: Sendable, Equatable {
        let isUnsupported: Bool
        let content: String
    }

    private let fileReader: any FileReading

    init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    func load(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        let sizeLimit = fileType.isBinaryContent ? Self.maxBinaryFileSizeBytes : Self.maxFileSizeBytes
        if let size = fileReader.fileSize(at: resolved), size > sizeLimit {
            return LoadedContent(isUnsupported: true, content: "")
        } else if fileType.isBinaryContent {
            if let data = try? fileReader.readData(from: resolved) {
                return LoadedContent(isUnsupported: false, content: data.base64EncodedString())
            } else {
                return LoadedContent(isUnsupported: true, content: "")
            }
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(isUnsupported: true, content: "")
        } else {
            return LoadedContent(isUnsupported: false, content: (try? fileReader.readString(from: resolved)) ?? "")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd BefoldApp && swift test --filter ContentLoaderTests 2>&1 | tail -5`
Expected: all 4 tests pass

- [ ] **Step 5: Refactor ViewerStore to use ContentLoader**

`BefoldApp/befold/Viewer/ViewerStore.swift` — replace private `loadedState` method and size constants:

Remove the two `static let` size constants and the private `loadedState(for:)` method.
Add a stored property and delegate to it:

```swift
// In ViewerStore, add property:
private let contentLoader: ContentLoader

// In init, add:
self.contentLoader = ContentLoader(fileReader: fileReader)

// Replace loadContent's call to loadedState:
private func loadContent() {
    guard let filePath else { return }
    let resolved = filePath.resolvingSymlinksInPath()
    guard fileReader.fileExists(at: resolved) else {
        scheduleFileGone()
        return
    }
    fileGoneTask?.cancel()
    fileGoneTask = nil

    let loaded = contentLoader.load(from: resolved, fileType: fileType)
    isUnsupported = loaded.isUnsupported
    content = loaded.content
    onContentReloaded?()
}
```

Remove `ViewerStore.maxFileSizeBytes` and `ViewerStore.maxBinaryFileSizeBytes` — update any references (check `MarkdownImageEmbedder`) to use `ContentLoader.maxBinaryFileSizeBytes` instead.

- [ ] **Step 6: Run full test suite**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add BefoldApp/befold/Viewer/ContentLoader.swift BefoldApp/befoldTests/ContentLoaderTests.swift BefoldApp/befold/Viewer/ViewerStore.swift
git commit -m "refactor: ViewerStore から ContentLoader を切り出す"
```

---

### Task 2: loadViewerHTML の Bundle 引数化

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift:139-143`
- Test: 既存の ViewerWebView 関連テスト（コンパイル確認）

**Interfaces:**
- Consumes: `Bundle.l10n`
- Produces: `loadViewerHTML(into:bundle:)` — bundle パラメータをデフォルト引数 `.l10n` で受け取る

- [ ] **Step 1: Change loadViewerHTML signature**

`BefoldApp/befold/Viewer/ViewerWebView.swift`:

```swift
static func loadViewerHTML(into webView: WKWebView, bundle: Bundle = .l10n) {
    guard let htmlURL = bundle.url(forResource: "viewer", withExtension: "html") else { return }
    let resourceDir = htmlURL.deletingLastPathComponent()
    webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
}
```

デフォルト引数 `.l10n` により既存の呼び出し元は変更不要。

- [ ] **Step 2: Run full test suite**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: all tests pass（シグネチャ変更のみ、動作変更なし）

- [ ] **Step 3: Commit**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift
git commit -m "refactor: loadViewerHTML に bundle 引数を追加する"
```

---

### Task 3: BefoldKit ライブラリターゲットの作成

**Files:**
- Modify: `BefoldApp/Package.swift`
- Modify: `BefoldApp/project.yml`
- Move to `BefoldApp/BefoldKit/`: `FileType.swift`, `FileReading.swift`, `ContentLoader.swift`, `ViewerBridge.swift`
- Modify: moved files (access control を `public` / `package` に変更)
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift` (import 追加)
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift` (import 追加)
- Modify: `BefoldApp/befoldTests/` (import 追加)

**Interfaces:**
- Consumes: 既存の `FileType`, `ViewerBridge`, `FileReading`, `ContentLoader`
- Produces: `BefoldKit` モジュール — QuickLook extension が依存可能なライブラリ

- [ ] **Step 1: Create BefoldKit directory and move files**

```bash
mkdir -p BefoldApp/BefoldKit
mv BefoldApp/befold/Viewer/FileType.swift BefoldApp/BefoldKit/
mv BefoldApp/befold/Viewer/FileReading.swift BefoldApp/BefoldKit/
mv BefoldApp/befold/Viewer/ContentLoader.swift BefoldApp/BefoldKit/
mv BefoldApp/befold/Viewer/ViewerBridge.swift BefoldApp/BefoldKit/
```

- [ ] **Step 2: Update access control in moved files**

`BefoldKit/FileType.swift`:
- `enum FileType` → `public enum FileType`
- 全 `static let` / `static func` / computed property → `public`
- `init(url:)` → `public init(url:)`

`BefoldKit/FileReading.swift`:
- `protocol FileReading` → `public protocol FileReading`
- `struct DefaultFileReader` → `public struct DefaultFileReader`
- `func fileExists/readString/readData/isBinary/fileSize` → `public`
- `init()` → `public init()`

`BefoldKit/ContentLoader.swift`:
- `struct ContentLoader` → `public struct ContentLoader`
- `struct LoadedContent` → `public struct LoadedContent`
- `static let maxFileSizeBytes/maxBinaryFileSizeBytes` → `public`
- `init(fileReader:)` → `public init(fileReader:)`
- `func load(from:fileType:)` → `public func load(from:fileType:)`
- `LoadedContent` の `let isUnsupported/content` → `public let`

`BefoldKit/ViewerBridge.swift`:
- `enum ViewerBridge` → `public enum ViewerBridge`
- 全 `static let` / `static func` → `public`
- `enum ViewMode` → `public enum ViewMode`
- `struct FindOptions` → `public struct FindOptions`
- FindOptions の `var` → `public var`、`init` を明示的に `public init(...)` として追加
- `findStringsScript()` の `Bundle.l10n` 参照 → `findStringsScript(bundle: Bundle = .l10n)` に引数化

- [ ] **Step 3: Update Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "befold",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
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
            dependencies: ["BefoldKit"],
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
```

注意: レンダリングリソース (viewer.html 等) は `BefoldKit` に移動する。`befold` ターゲットからは削除し、ローカライズリソースとアイコンのみ残す。

- [ ] **Step 4: Move resources to BefoldKit**

```bash
mkdir -p BefoldApp/BefoldKit/Resources
mv BefoldApp/befold/Resources/viewer.html BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/viewer.js BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/style.css BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/mermaid.min.js BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/markdown-it.min.js BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/highlight.min.js BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/github.css BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/github-dark.css BefoldApp/BefoldKit/Resources/
mv BefoldApp/befold/Resources/github-markdown.css BefoldApp/BefoldKit/Resources/
```

- [ ] **Step 5: Update LocalizedBundle.swift**

`BefoldApp/befold/App/LocalizedBundle.swift` を更新して、`BefoldKit` のリソースバンドルを参照する拡張を追加:

```swift
import Foundation
import BefoldKit

extension Bundle {
    /// Localizable.xcstrings を含むバンドル。
    /// swift build / swift test ではリソースが Bundle.module に入り、
    /// xcodebuild のアプリバンドルでは Bundle.main に入る差を吸収する。
    static var l10n: Bundle {
        #if SWIFT_PACKAGE
            .module
        #else
            .main
        #endif
    }

    /// viewer.html 等のレンダリングリソースを含むバンドル。
    /// BefoldKit ターゲットのリソースバンドルを返す。
    static var rendering: Bundle {
        Bundle.befoldKitResources
    }
}
```

`BefoldKit` 側にバンドルアクセサを追加(`BefoldKit/BundleAccessor.swift`):

```swift
import Foundation

extension Bundle {
    /// BefoldKit のリソースバンドル。SPM は _BefoldKit_Resources を自動生成する。
    public static let befoldKitResources: Bundle = .module
}
```

- [ ] **Step 6: Update loadViewerHTML to use Bundle.rendering**

`BefoldApp/befold/Viewer/ViewerWebView.swift`:

```swift
static func loadViewerHTML(into webView: WKWebView, bundle: Bundle = .rendering) {
    guard let htmlURL = bundle.url(forResource: "viewer", withExtension: "html") else { return }
    let resourceDir = htmlURL.deletingLastPathComponent()
    webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
}
```

- [ ] **Step 7: Add `import BefoldKit` to app source files**

以下のファイルに `import BefoldKit` を追加:
- `BefoldApp/befold/Viewer/ViewerStore.swift`
- `BefoldApp/befold/Viewer/ViewerWebView.swift`
- `BefoldApp/befold/Viewer/ViewerContentView.swift`
- `BefoldApp/befold/Viewer/MarkdownImageEmbedder.swift`
- `BefoldApp/befold/Viewer/DirectoryLister.swift`
- `BefoldApp/befold/Viewer/FileListEntry.swift`
- `BefoldApp/befold/App/ViewerWindowController.swift`
- `BefoldApp/befold/App/ScrollPositionStore.swift`
- `BefoldApp/befold/App/SourceModeStore.swift`

`@testable import befold` に加え `import BefoldKit` (または `@testable import BefoldKit`) をテストファイルにも追加。

- [ ] **Step 8: Update project.yml**

```yaml
targets:
  BefoldKit:
    type: framework
    platform: macOS
    sources:
      - path: BefoldKit
        excludes:
          - "Resources/**"
      - path: BefoldKit/Resources
        buildPhase: resources
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.degino.befold.kit
      PRODUCT_NAME: BefoldKit
      GENERATE_INFOPLIST_FILE: true
  befold:
    type: application
    platform: macOS
    sources:
      - path: befold
        excludes:
          - "Resources/**"
          - Info.plist
          - befold.entitlements
      - path: befold/Resources
        buildPhase: resources
        excludes:
          - "__tests__/**"
          - "viewer.html"
          - "viewer.js"
          - "style.css"
          - "mermaid.min.js"
          - "markdown-it.min.js"
          - "highlight.min.js"
          - "github.css"
          - "github-dark.css"
          - "github-markdown.css"
    dependencies:
      - target: BefoldKit
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.degino.befold
      PRODUCT_NAME: befold
      MARKETING_VERSION: "1.5.0"
      CURRENT_PROJECT_VERSION: "335"
      INFOPLIST_FILE: befold/Info.plist
      CODE_SIGN_ENTITLEMENTS: befold/befold.entitlements
      ENABLE_HARDENED_RUNTIME: true
      GENERATE_INFOPLIST_FILE: false
  befoldTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - befoldTests
    dependencies:
      - target: befold
      - target: BefoldKit
    settings:
      BUNDLE_LOADER: "$(TEST_HOST)"
      TEST_HOST: "$(BUILT_PRODUCTS_DIR)/befold.app/Contents/MacOS/befold"
      GENERATE_INFOPLIST_FILE: true
```

- [ ] **Step 9: Fix compilation — resolve all import errors**

`swift build` を実行し、`FileType` / `ViewerBridge` / `FileReading` / `ContentLoader` への未解決参照を `import BefoldKit` で解消する。各ファイルを確認して修正。

Run: `cd BefoldApp && swift build 2>&1 | grep "error:" | head -20`

- [ ] **Step 10: Run full test suite**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 11: Verify xcodegen**

Run: `cd BefoldApp && xcodegen generate 2>&1`
Expected: 正常終了（Generated project に BefoldKit ターゲットが含まれる）

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor: BefoldKit ライブラリターゲットを作成してレンダリング基盤を共有可能にする"
```

---

### Task 4: MarkdownImageEmbedder の maxBinaryFileSizeBytes 参照更新

**Files:**
- Modify: `BefoldApp/befold/Viewer/MarkdownImageEmbedder.swift` (ViewerStore.maxBinaryFileSizeBytes → ContentLoader.maxBinaryFileSizeBytes)

**Interfaces:**
- Consumes: `ContentLoader.maxBinaryFileSizeBytes`
- Produces: 既存動作の維持

- [ ] **Step 1: Update reference**

`MarkdownImageEmbedder.swift` 内の `ViewerStore.maxBinaryFileSizeBytes` を `ContentLoader.maxBinaryFileSizeBytes` に変更。

- [ ] **Step 2: Run full test suite**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 3: Commit (amend into previous)**

```bash
git add BefoldApp/befold/Viewer/MarkdownImageEmbedder.swift
git commit --amend --no-edit
```

---
