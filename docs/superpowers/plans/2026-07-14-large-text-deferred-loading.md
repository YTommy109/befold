# 大容量テキスト段階読み込み・非 UTF-8 エンコーディング対応 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 10MB 超のテキストファイルを段階読み込みで表示し、非 UTF-8 エンコーディング（Shift_JIS 等）にフォールバック対応する

**Architecture:** ContentLoader に preview 読み込みを追加し、ViewerStore が 10MB 超ファイルでプレビュー→非同期全量読み込みの 2 段階で表示する。`isUnsupported: Bool` を `RejectReason?` に置き換え、非対応形式とサイズ超過でエラーメッセージを分離する。FileReading に非 UTF-8 フォールバックと部分読み込みを追加する。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView / Swift Testing

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- macOS 14+
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` 表示名
- Conventional Commits + 日本語

---

### Task 1: 非 UTF-8 エンコーディングフォールバック

**Files:**
- Modify: `BefoldApp/BefoldKit/FileReading.swift:93-108` (`decodeUnicodeText`)
- Test: `BefoldApp/befoldTests/DefaultFileReaderTests.swift`

**Interfaces:**
- Consumes: なし（既存 `decodeUnicodeText` の内部変更）
- Produces: `readString(from:)` が Shift_JIS / EUC-JP ファイルに対して正しい文字列を返す

- [ ] **Step 1: Shift_JIS テストを書く**

```swift
@Test("Shift_JIS ファイルが正しくデコードされる")
func shiftJISFileDecodesCorrectly() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let text = "北海道特定疾患"
    let data = try #require((text as NSString).data(using: CFStringConvertEncodingToNSStringEncoding(
        CFStringConvertIANACharSetNameToEncoding("Shift_JIS" as CFString)
    )))
    let file = try tmp.file(named: "data.csv", data: data)

    let reader = DefaultFileReader()
    #expect(!reader.isBinary(at: file))
    #expect(try reader.readString(from: file) == text)
}
```

- [ ] **Step 2: EUC-JP テストを書く**

```swift
@Test("EUC-JP ファイルが正しくデコードされる")
func eucJPFileDecodesCorrectly() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let text = "日本語テスト"
    let data = try #require((text as NSString).data(using: CFStringConvertEncodingToNSStringEncoding(
        CFStringConvertIANACharSetNameToEncoding("EUC-JP" as CFString)
    )))
    let file = try tmp.file(named: "data.txt", data: data)

    let reader = DefaultFileReader()
    #expect(try reader.readString(from: file) == text)
}
```

- [ ] **Step 3: テストが失敗することを確認**

Run: `cd BefoldApp && swift test --filter DefaultFileReaderTests`
Expected: `shiftJISFileDecodesCorrectly` と `eucJPFileDecodesCorrectly` が FAIL

- [ ] **Step 4: `decodeUnicodeText` にフォールバックを実装**

`BefoldApp/BefoldKit/FileReading.swift` の `decodeUnicodeText` メソッド末尾を変更:

```swift
private static func decodeUnicodeText(_ data: Data) -> String? {
    if let bom = detectBOM(data) {
        return String(data: data.dropFirst(bom.bomLength), encoding: bom.encoding)
    }
    if data.prefix(binarySniffLength).contains(0) {
        let encoding: String.Encoding = looksLittleEndianUTF16(data)
            ? .utf16LittleEndian
            : .utf16BigEndian
        return String(data: data, encoding: encoding)
    }
    // UTF-8 として復号を試みる。
    if let utf8 = String(data: data, encoding: .utf8) {
        return utf8
    }
    // UTF-8 復号に失敗した場合、NSString のヒューリスティックでエンコーディングを推定する。
    var usedLossyConversion = false
    let detected = NSString(data: data, encoding: 0, convertedString: nil,
                            usedLossyConversion: &usedLossyConversion)
    return detected as String?
}
```

注意: `NSString(data:encoding:0:...)` ではなく `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)` を使う:

```swift
if let utf8 = String(data: data, encoding: .utf8) {
    return utf8
}
var convertedString: NSString?
var usedLossyConversion: ObjCBool = false
let detected = NSString.stringEncoding(
    for: data,
    encodingOptions: nil,
    convertedString: &convertedString,
    usedLossyConversion: &usedLossyConversion
)
if detected != 0, let result = convertedString {
    return result as String
}
return nil
```

- [ ] **Step 5: テストが通ることを確認**

Run: `cd BefoldApp && swift test --filter DefaultFileReaderTests`
Expected: ALL PASS

- [ ] **Step 6: `readString(from:)` のフォールバック分岐を削除**

`readString(from:)` の末尾にある `try String(contentsOf: url, encoding: .utf8)` フォールバックは `decodeUnicodeText` が UTF-8 含め全パターンを処理するため不要になる。変更後:

```swift
public func readString(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    if let decoded = Self.decodeUnicodeText(data) {
        return decoded
    }
    throw CocoaError(.fileReadInapplicableStringEncoding)
}
```

- [ ] **Step 7: 全テスト通過を確認**

Run: `cd BefoldApp && swift test`
Expected: ALL PASS

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/BefoldKit/FileReading.swift BefoldApp/befoldTests/DefaultFileReaderTests.swift
git commit -m "feat: 非 UTF-8 エンコーディング（Shift_JIS / EUC-JP）のフォールバック復号を追加する"
```

---

### Task 2: RejectReason と LoadedContent の拡張

**Files:**
- Create: `BefoldApp/BefoldKit/RejectReason.swift`
- Modify: `BefoldApp/BefoldKit/ContentLoader.swift`
- Test: `BefoldApp/befoldTests/ContentLoaderTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `RejectReason` enum (`.unsupportedFormat`, `.fileTooLarge`)
  - `LoadedContent(rejectReason: RejectReason?, content: String, isTruncated: Bool)`
  - `ContentLoader.maxFileSizeBytes` = 50MB（テキスト・バイナリ共通）
  - `ContentLoader.previewSizeBytes` = 10MB
  - `ContentLoader.loadPreview(from:fileType:) -> LoadedContent`

- [ ] **Step 1: `RejectReason.swift` を作成**

```swift
import Foundation

/// ファイルを表示できない理由。
public enum RejectReason: Sendable, Equatable {
    /// バイナリなど非対応形式。
    case unsupportedFormat
    /// ファイルサイズが上限を超えている。
    case fileTooLarge
}
```

- [ ] **Step 2: `LoadedContent` を拡張し `ContentLoader` を更新**

`BefoldApp/BefoldKit/ContentLoader.swift` を全面書き換え:

```swift
import Foundation

public struct ContentLoader: Sendable {
    /// 全量読み込みとバイナリ表示の共通上限（50MB）。
    public static let maxFileSizeBytes = 50 * 1024 * 1024

    /// プレビュー読み込みの上限（10MB）。これ以下なら同期全量読み込みで済む。
    public static let previewSizeBytes = 10 * 1024 * 1024

    public struct LoadedContent: Sendable, Equatable {
        public let rejectReason: RejectReason?
        public let content: String
        public let isTruncated: Bool

        public init(rejectReason: RejectReason?, content: String, isTruncated: Bool = false) {
            self.rejectReason = rejectReason
            self.content = content
            self.isTruncated = isTruncated
        }
    }

    private let fileReader: any FileReading

    public init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    public func load(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        } else if fileType.isBinaryContent {
            if let data = try? fileReader.readData(from: resolved) {
                return LoadedContent(rejectReason: nil, content: data.base64EncodedString())
            } else {
                return LoadedContent(rejectReason: .unsupportedFormat, content: "")
            }
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(rejectReason: .unsupportedFormat, content: "")
        } else {
            return LoadedContent(
                rejectReason: nil,
                content: (try? fileReader.readString(from: resolved)) ?? ""
            )
        }
    }

    public func loadPreview(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        } else if fileType.isBinaryContent {
            return load(from: url, fileType: fileType)
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(rejectReason: .unsupportedFormat, content: "")
        } else {
            let content = (try? fileReader.readString(from: resolved, maxBytes: Self.previewSizeBytes)) ?? ""
            return LoadedContent(rejectReason: nil, content: content, isTruncated: true)
        }
    }
}
```

- [ ] **Step 3: `FileReading` プロトコルに `readString(from:maxBytes:)` を追加**

`BefoldApp/BefoldKit/FileReading.swift` のプロトコル定義に追加:

```swift
func readString(from url: URL, maxBytes: Int) throws -> String
```

`DefaultFileReader` に実装を追加:

```swift
public func readString(from url: URL, maxBytes: Int) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let data = try handle.read(upToCount: maxBytes) else {
        return ""
    }
    // 最後の改行で切断し、行途中の切断を防ぐ。
    let trimmed: Data
    if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
        trimmed = data[data.startIndex...lastNewline]
    } else {
        trimmed = data
    }
    if let decoded = Self.decodeUnicodeText(trimmed) {
        return decoded
    }
    throw CocoaError(.fileReadInapplicableStringEncoding)
}
```

`InMemoryFileReader` にも追加:

```swift
func readString(from url: URL, maxBytes: Int) throws -> String {
    let full = try readString(from: url)
    let data = Data(full.utf8)
    if data.count <= maxBytes { return full }
    let prefix = data.prefix(maxBytes)
    if let lastNewline = prefix.lastIndex(of: UInt8(ascii: "\n")) {
        return String(decoding: prefix[prefix.startIndex...lastNewline], as: UTF8.self)
    }
    return String(decoding: prefix, as: UTF8.self)
}
```

- [ ] **Step 4: 既存テストを `rejectReason` に移行**

`BefoldApp/befoldTests/ContentLoaderTests.swift` を更新。`isUnsupported` の参照をすべて `rejectReason` に置き換える:

```swift
@Suite
struct ContentLoaderTests {
    private let loader = ContentLoader(fileReader: DefaultFileReader())

    @Test("テキストファイルを正常に読み込む")
    func loadTextFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.txt", contents: "hello")

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == nil)
        #expect(result.content == "hello")
        #expect(!result.isTruncated)
    }

    @Test("サイズ超過ファイルは fileTooLarge")
    func oversizedFileIsRejected() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let bigData = Data(repeating: 0x41, count: ContentLoader.maxFileSizeBytes + 1)
        let file = try tmp.file(named: "big.txt", data: bigData)

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == .fileTooLarge)
        #expect(result.content == "")
    }

    @Test("バイナリファイルは unsupportedFormat")
    func binaryFileIsRejected() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        var data = Data(repeating: 0x00, count: 100)
        data[0] = 0xFF
        let file = try tmp.file(named: "bin.dat", data: data)

        let result = loader.load(from: file, fileType: .code(language: "plaintext"))
        #expect(result.rejectReason == .unsupportedFormat)
    }

    @Test("画像ファイルは base64 エンコードされる")
    func imageFileIsBase64Encoded() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let file = try tmp.file(named: "img.png", data: data)

        let result = loader.load(from: file, fileType: .image(mimeType: "image/png"))
        #expect(result.rejectReason == nil)
        #expect(result.content == data.base64EncodedString())
    }
}
```

- [ ] **Step 5: `loadPreview` のテストを追加**

```swift
@Test("loadPreview は先頭のみ返し isTruncated を設定する")
func loadPreviewReturnsTruncated() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    // previewSizeBytes を少し超えるファイル
    let lines = (0..<200_000).map { "line\($0),data\($0)" }.joined(separator: "\n")
    let file = try tmp.file(named: "big.csv", contents: lines)

    let result = loader.loadPreview(from: file, fileType: .csv(delimiter: ","))
    #expect(result.rejectReason == nil)
    #expect(result.isTruncated)
    #expect(result.content.utf8.count <= ContentLoader.previewSizeBytes)
    #expect(result.content.hasSuffix("\n"))
}

@Test("loadPreview で上限以下のバイナリは通常読み込み")
func loadPreviewBinaryFallsThrough() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let data = Data([0x89, 0x50, 0x4E, 0x47])
    let file = try tmp.file(named: "img.png", data: data)

    let result = loader.loadPreview(from: file, fileType: .image(mimeType: "image/png"))
    #expect(result.rejectReason == nil)
    #expect(result.content == data.base64EncodedString())
}
```

- [ ] **Step 6: `readString(from:maxBytes:)` のテストを追加**

`DefaultFileReaderTests.swift` に追加:

```swift
@Test("readString(maxBytes:) は指定バイト以内で改行境界で切断する")
func readStringWithMaxBytesTruncatesAtNewline() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let text = "line1\nline2\nline3\nline4\n"
    let file = try tmp.file(named: "lines.txt", contents: text)

    let result = try DefaultFileReader().readString(from: file, maxBytes: 15)
    #expect(result == "line1\nline2\n")
}
```

- [ ] **Step 7: テストが通ることを確認**

Run: `cd BefoldApp && swift test`
Expected: ALL PASS

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/BefoldKit/RejectReason.swift BefoldApp/BefoldKit/ContentLoader.swift \
  BefoldApp/BefoldKit/FileReading.swift BefoldApp/befoldTests/ContentLoaderTests.swift \
  BefoldApp/befoldTests/DefaultFileReaderTests.swift BefoldApp/befoldTests/InMemoryFileReader.swift
git commit -m "feat: RejectReason 導入と ContentLoader に段階読み込み・50MB 上限を追加する"
```

---

### Task 3: ViewerStore の段階読み込みと UI 層の移行

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift`
- Modify: `BefoldApp/befold/Viewer/UnsupportedFileView.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift`
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:571,589`
- Test: `BefoldApp/befoldTests/ViewerStoreTests.swift`

**Interfaces:**
- Consumes:
  - `ContentLoader.loadPreview(from:fileType:) -> LoadedContent`
  - `ContentLoader.load(from:fileType:) -> LoadedContent`
  - `ContentLoader.previewSizeBytes: Int`
  - `LoadedContent.rejectReason: RejectReason?`
  - `LoadedContent.isTruncated: Bool`
- Produces:
  - `ViewerStore.rejectReason: RejectReason?`（`isUnsupported` を置換）
  - `ViewerStore.isRejected: Bool`（computed、既存 `isUnsupported` 参照箇所の移行用）
  - `ViewerStore.isTruncated: Bool`
  - `UnsupportedFileView(fileURL:rejectReason:)` — メッセージ分岐

- [ ] **Step 1: ViewerStore の `isUnsupported` を `rejectReason` に置き換え**

`BefoldApp/befold/Viewer/ViewerStore.swift`:

`isUnsupported` プロパティを置き換える:

```swift
private(set) var rejectReason: RejectReason?
private(set) var isTruncated: Bool = false

var isRejected: Bool { rejectReason != nil }
```

`showsCodeContent` の `isUnsupported` を `isRejected` に:

```swift
var showsCodeContent: Bool {
    if isRejected { return false }
    if isSourceMode { return true }
    if case .code = fileType { return true }
    return false
}
```

`loadContent()` を段階読み込みに更新:

```swift
private var fullLoadTask: Task<Void, Never>?

private func loadContent() {
    guard let filePath else { return }
    let resolved = filePath.resolvingSymlinksInPath()
    guard fileReader.fileExists(at: resolved) else {
        scheduleFileGone()
        return
    }
    fileGoneTask?.cancel()
    fileGoneTask = nil
    fullLoadTask?.cancel()
    fullLoadTask = nil

    let size = fileReader.fileSize(at: resolved)
    let needsDeferred = size.map { $0 > ContentLoader.previewSizeBytes } ?? false

    if needsDeferred {
        let preview = contentLoader.loadPreview(from: resolved, fileType: fileType)
        rejectReason = preview.rejectReason
        isTruncated = preview.isTruncated
        content = preview.content
        onContentReloaded?()

        guard preview.rejectReason == nil else { return }
        fullLoadTask = Task { @MainActor [weak self, contentLoader, fileType] in
            let full = contentLoader.load(from: resolved, fileType: fileType)
            guard !Task.isCancelled, let self else { return }
            self.rejectReason = full.rejectReason
            self.isTruncated = false
            self.content = full.content
            self.onContentReloaded?()
        }
    } else {
        let loaded = contentLoader.load(from: resolved, fileType: fileType)
        rejectReason = loaded.rejectReason
        isTruncated = false
        content = loaded.content
        onContentReloaded?()
    }
}
```

`close()` で `fullLoadTask` もキャンセル:

```swift
func close() {
    fileGoneTask?.cancel()
    fileGoneTask = nil
    fullLoadTask?.cancel()
    fullLoadTask = nil
    fileWatcher?.stop()
    fileWatcher = nil
}
```

- [ ] **Step 2: UnsupportedFileView を rejectReason 対応に更新**

```swift
import BefoldKit
import SwiftUI

struct UnsupportedFileView: View {
    let fileURL: URL?
    let rejectReason: RejectReason

    var body: some View {
        VStack(spacing: 12) {
            if let fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch rejectReason {
        case .unsupportedFormat:
            String(localized: "viewer.unsupported.format", bundle: .l10n)
        case .fileTooLarge:
            String(localized: "viewer.unsupported.tooLarge", bundle: .l10n)
        }
    }
}
```

ローカライズ文字列を追加（既存の `.lproj` ファイルに）:

- `"viewer.unsupported.format"` = `"このファイル形式はプレビューに対応していません"`
- `"viewer.unsupported.tooLarge"` = `"ファイルが大きすぎるため表示できません"`

注意: 既存のローカライズファイルの形式（`.strings` / `.xcstrings` / String Catalog）に従うこと。ハードコードの文字列がローカライズ済みかを確認し、既存パターンに合わせる。もしハードコードのままなら同じくハードコードで分岐:

```swift
private var message: String {
    switch rejectReason {
    case .unsupportedFormat:
        "このファイル形式はプレビューに対応していません"
    case .fileTooLarge:
        "ファイルが大きすぎるため表示できません"
    }
}
```

- [ ] **Step 3: ViewerContentView を更新**

```swift
.opacity(store.isRejected ? 0 : 1)

if let reason = store.rejectReason {
    UnsupportedFileView(fileURL: store.filePath, rejectReason: reason)
}
```

- [ ] **Step 4: ViewerWindowController の参照を更新**

`BefoldApp/befold/App/ViewerWindowController.swift`:

571 行目:
```swift
let isEnabled = !store.isRejected
```

589 行目:
```swift
store.fileType.supportsSourceMode && !store.isRejected
```

- [ ] **Step 5: 既存テストを `rejectReason` / `isRejected` に移行**

`BefoldApp/befoldTests/ViewerStoreTests.swift` で `store.isUnsupported` を全て置き換え:

- `store.isUnsupported` → `store.isRejected`（真偽値チェック）
- 理由を区別するテスト箇所では `store.rejectReason == .unsupportedFormat` / `.fileTooLarge` を使う

具体例（全箇所）:

```swift
// openBinaryFileMarksUnsupported:
#expect(store.rejectReason == .unsupportedFormat)

// openOversizedFileMarksUnsupportedWithoutLoading:
#expect(store.rejectReason == .fileTooLarge)

// openFileAtSizeLimitLoadsContent:
#expect(!store.isRejected)

// switchingFromOversizedToNormalResetsUnsupported:
#expect(store.isRejected)  // → #expect(!store.isRejected)（変更後も同じロジック）

// 以下同様に isUnsupported → isRejected に置換
```

`showsCodeContent` のテストが存在すれば `isUnsupported` 参照を更新。

テスト内のコメントにある `isUnsupported` テキストも `isRejected` / `rejectReason` に更新する。

- [ ] **Step 6: `isTruncated` のテストを追加**

```swift
@Test("10MB 超ファイルは isTruncated で段階読み込みされる")
func oversizedTextFileIsTruncatedThenFullLoaded() async {
    let file = URL(fileURLWithPath: "/files/big.csv")
    let reader = InMemoryFileReader()
    let lines = (0..<500_000).map { "line\($0)" }.joined(separator: "\n")
    reader.setFile(lines, at: file)
    reader.setSize(ContentLoader.previewSizeBytes + 1, at: file)

    let store = makeStore(reader: reader)
    store.openFile(file)

    #expect(store.isTruncated)
    #expect(!store.isRejected)
    // 非同期全量読み込みの完了を待つ
    await yieldMainActor()
    #expect(!store.isTruncated)
    #expect(store.content == lines)

    store.close()
}

@Test("10MB 以下のファイルは isTruncated = false")
func normalFileIsNotTruncated() {
    let file = URL(fileURLWithPath: "/files/small.csv")
    let reader = InMemoryFileReader()
    reader.setFile("a,b\n1,2", at: file)

    let store = makeStore(reader: reader)
    store.openFile(file)

    #expect(!store.isTruncated)
    #expect(!store.isRejected)

    store.close()
}
```

- [ ] **Step 7: テストが通ることを確認**

Run: `cd BefoldApp && swift test`
Expected: ALL PASS

- [ ] **Step 8: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerStore.swift BefoldApp/befold/Viewer/UnsupportedFileView.swift \
  BefoldApp/befold/Viewer/ViewerContentView.swift BefoldApp/befold/App/ViewerWindowController.swift \
  BefoldApp/befoldTests/ViewerStoreTests.swift
git commit -m "feat: ViewerStore に段階読み込みを導入し RejectReason でエラーメッセージを分離する"
```

---

### Task 4: JS 側の truncated バナー表示

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/viewer.html`
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`
- Test: `BefoldApp/befoldTests/ViewerBridgeTests.swift`（renderScript の引数追加テスト）

**Interfaces:**
- Consumes:
  - `ViewerStore.isTruncated: Bool`
- Produces:
  - `ViewerBridge.truncatedScript(_:) -> String` — JS の `_mmdSetTruncated(bool)` を呼ぶ
  - `viewer.html` 内に `#mmd-truncated-banner` 要素とスタイル

- [ ] **Step 1: viewer.html にバナー要素とスタイルを追加**

`BefoldApp/BefoldKit/Resources/viewer.html` の `<div id="mmd-error">` の直後にバナーを追加:

```html
<div id="mmd-truncated-banner" class="mmd-truncated-banner" style="display:none;">ファイルの一部を表示しています…</div>
```

CSS に追加:

```css
.mmd-truncated-banner {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 6px 16px;
  font-size: 12px;
  text-align: center;
  z-index: 1000;
  background: rgba(255, 204, 0, 0.15);
  color: var(--text-color);
  border-top: 1px solid rgba(255, 204, 0, 0.3);
}
```

JS に truncated 制御関数を追加:

```javascript
function _mmdSetTruncated(isTruncated) {
  var banner = document.getElementById('mmd-truncated-banner');
  banner.style.display = isTruncated ? 'block' : 'none';
}
```

- [ ] **Step 2: ViewerBridge に truncatedScript を追加**

`BefoldApp/BefoldKit/ViewerBridge.swift`:

```swift
public static func truncatedScript(_ isTruncated: Bool) -> String {
    "_mmdSetTruncated(\(isTruncated))"
}
```

- [ ] **Step 3: ViewerWebView の updateContent で isTruncated を反映**

`ViewerWebView` の `updateContent` シグネチャに `isTruncated: Bool` を追加し、`applyRender` の末尾で:

```swift
webView.evaluateJavaScript(ViewerBridge.truncatedScript(isTruncated))
```

呼び出し側（`ViewerWebView.updateNSView` 相当の箇所）で `store.isTruncated` を渡す。

- [ ] **Step 4: ViewerBridge テストを追加**

`BefoldApp/befoldTests/ViewerBridgeTests.swift`:

```swift
@Test("truncatedScript は _mmdSetTruncated を呼ぶ JS を返す")
func truncatedScript() {
    #expect(ViewerBridge.truncatedScript(true) == "_mmdSetTruncated(true)")
    #expect(ViewerBridge.truncatedScript(false) == "_mmdSetTruncated(false)")
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `cd BefoldApp && swift test`
Expected: ALL PASS

- [ ] **Step 6: 手動テスト**

1. 10MB 以下の CSV を開く → バナーなし
2. 10MB 超 50MB 以下の CSV を開く → バナー「ファイルの一部を表示しています…」が一時表示され、全量読み込み後に消える
3. 50MB 超のファイルを開く → 「ファイルが大きすぎるため表示できません」
4. バイナリファイルを開く → 「このファイル形式はプレビューに対応していません」

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/BefoldKit/Resources/viewer.html BefoldApp/BefoldKit/ViewerBridge.swift \
  BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: 段階読み込み中のバナー表示を追加する"
```
