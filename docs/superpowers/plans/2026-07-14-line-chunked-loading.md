# 行指向テキストのチャンク読み込み Implementation Plan

<!-- supersedes ./2026-07-14-large-text-deferred-loading.md -->
<!-- constrained-by ../specs/2026-07-14-line-chunked-loading-design.md -->

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CSV/TSV・コード・プレーンテキストを 1,000 行単位でチャンク読み込みし、ボタン操作で追記表示する仕組みに置き換える。既存の段階読み込み（fullLoadTask / loadPreview / needsDeferred）を全削除する。

**Architecture:** 行指向ファイルは `LineChunkReader`（FileHandle ベース）で 1,000 行ずつ読み、初回チャンクを `render()` で描画、以降は JS `appendChunk()` で DOM に追記する。非行指向（Markdown/Mermaid/HTML/SVG）は従来の一括読み込み（10MB 上限）。バイナリは従来どおり 50MB 上限。ViewerStore は非同期タスクを持たず、すべて MainActor 同期実行。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView / Swift Testing

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- macOS 14+
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` 表示名
- コミットは Conventional Commits + 日本語
- `Bundle.l10n` 経由のローカライズ（en + ja）
- JS への文字列注入は `JSONEncoder` でエスケープ
- ViewerBridge の文字列定数と viewer.html/viewer.js の定義の整合性は ViewerBridgeTests がソースを読んで検証する

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `BefoldApp/BefoldKit/TextEncoding.swift` | BOM 検出・エンコーディング推定のユーティリティ（DefaultFileReader から抽出） |
| `BefoldApp/BefoldKit/LineChunkReader.swift` | FileHandle ベースの行チャンクリーダー + `ChunkedTextReading` プロトコル |
| `BefoldApp/befoldTests/LineChunkReaderTests.swift` | LineChunkReader の単体テスト |

### Modified files

| Path | Changes |
|---|---|
| `BefoldApp/BefoldKit/FileReading.swift` | `decodeUnicodeText` / `detectBOM` を `TextEncoding` 経由に切り替え |
| `BefoldApp/BefoldKit/FileType.swift` | `isLineOriented` 計算プロパティ追加 |
| `BefoldApp/BefoldKit/ContentLoader.swift` | `openChunked` 追加（`loadPreview` / `previewSizeBytes` は Task 4 で削除） |
| `BefoldApp/BefoldKit/ViewerBridge.swift` | `appendChunkScript` / `bannerStringsScript` / `loadMoreLinesMessageName` 追加、`truncatedScript` オーバーロード追加（旧シグネチャは Task 4 で削除） |
| `BefoldApp/BefoldKit/Resources/viewer.html` | バナー HTML を button 付きに変更 |
| `BefoldApp/BefoldKit/Resources/viewer.js` | `appendChunk()` 関数追加 |
| `BefoldApp/BefoldKit/Resources/style.css` | バナーボタンのスタイル追加 |
| `BefoldApp/befold/Viewer/ViewerStore.swift` | `fullLoadTask` / `needsDeferred` / `loadPreview` 呼び出し削除、`chunkSession` / `loadMoreLines()` 追加、旧 `truncatedScript` 呼び出しを新シグネチャに置き換え |
| `BefoldApp/befold/Viewer/ViewerContentView.swift` | `onLoadMoreLines` パラメータ追加 |
| `BefoldApp/befold/Viewer/ViewerWebView.swift` | `loadMoreLines` メッセージハンドラ追加、`onLoadMoreLines` コールバック追加 |
| `BefoldApp/befold/Resources/Localizable.xcstrings` | バナー文字列（en + ja）追加 |
| `BefoldApp/befoldTests/ContentLoaderTests.swift` | `loadPreview` テスト削除、`openChunked` テスト追加 |
| `BefoldApp/befoldTests/ViewerStoreTests.swift` | 段階読み込みテスト → チャンク読み込みテストに置き換え |
| `BefoldApp/befoldTests/ViewerBridgeTests.swift` | 新メソッドのテスト追加 |
| `BefoldApp/befoldTests/FileTypeTests.swift` | `isLineOriented` テスト追加 |

---

### Task 1: TextEncoding 抽出 + LineChunkReader

**Files:**
- Create: `BefoldApp/BefoldKit/TextEncoding.swift`
- Create: `BefoldApp/BefoldKit/LineChunkReader.swift`
- Create: `BefoldApp/befoldTests/LineChunkReaderTests.swift`
- Modify: `BefoldApp/BefoldKit/FileReading.swift:92-145`（`detectBOM` / `decodeUnicodeText` を `TextEncoding` 委譲に）

**Interfaces:**
- Consumes: `DefaultFileReader.detectBOM`, `DefaultFileReader.decodeUnicodeText`（抽出元）
- Produces:
  - `TextEncoding.detectBOM(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)?`
  - `TextEncoding.decodeText(_ data: Data) -> String?`
  - `TextEncoding.isChunkableEncoding(_ data: Data) -> Bool`
  - `TextEncoding.detectEncoding(_ data: Data) -> String.Encoding?`
  - `protocol ChunkedTextReading: AnyObject { var isAtEnd: Bool { get }; func readNextChunk() throws -> String }`
  - `LineChunkReader: ChunkedTextReading`（`init(url:) throws`、UTF-16/32 は `TextEncodingError.unsupportedForChunking` を throw）

#### Step 1: TextEncoding のテストを書く

```swift
// BefoldApp/befoldTests/LineChunkReaderTests.swift
import BefoldKit
import Foundation
import Testing

@Suite
struct TextEncodingTests {
    @Test("UTF-8 BOM を検出する")
    func detectsUtf8Bom() {
        let data = Data([0xEF, 0xBB, 0xBF] + Array("hello".utf8))
        let result = TextEncoding.detectBOM(data)
        #expect(result?.encoding == .utf8)
        #expect(result?.bomLength == 3)
    }

    @Test("UTF-16 LE BOM を検出する")
    func detectsUtf16LeBom() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        let result = TextEncoding.detectBOM(data)
        #expect(result?.encoding == .utf16LittleEndian)
        #expect(result?.bomLength == 2)
    }

    @Test("UTF-16 BE BOM を検出する")
    func detectsUtf16BeBom() {
        let data = Data([0xFE, 0xFF, 0x00, 0x41])
        let result = TextEncoding.detectBOM(data)
        #expect(result?.encoding == .utf16BigEndian)
        #expect(result?.bomLength == 2)
    }

    @Test("UTF-32 LE BOM を検出する")
    func detectsUtf32LeBom() {
        let data = Data([0xFF, 0xFE, 0x00, 0x00])
        let result = TextEncoding.detectBOM(data)
        #expect(result?.encoding == .utf32LittleEndian)
        #expect(result?.bomLength == 4)
    }

    @Test("BOM なしデータは nil を返す")
    func noBomReturnsNil() {
        let data = Data("hello".utf8)
        #expect(TextEncoding.detectBOM(data) == nil)
    }

    @Test("UTF-16/32 BOM はチャンク不可")
    func utf16IsNotChunkable() {
        let utf16le = Data([0xFF, 0xFE, 0x41, 0x00])
        #expect(!TextEncoding.isChunkableEncoding(utf16le))
    }

    @Test("UTF-8 BOM はチャンク可")
    func utf8BomIsChunkable() {
        let utf8bom = Data([0xEF, 0xBB, 0xBF] + Array("hello".utf8))
        #expect(TextEncoding.isChunkableEncoding(utf8bom))
    }

    @Test("BOM なし UTF-8 はチャンク可")
    func plainUtf8IsChunkable() {
        let data = Data("hello\nworld".utf8)
        #expect(TextEncoding.isChunkableEncoding(data))
    }

    @Test("BOM なしで NUL を含むデータはチャンク不可")
    func nulContainingDataIsNotChunkable() {
        var data = Data([0x41, 0x00, 0x42, 0x00])
        #expect(!TextEncoding.isChunkableEncoding(data))
    }
}
```

- [ ] テストファイルを作成して上記テストを書く
- [ ] `swift test --filter TextEncodingTests` で全テスト FAIL を確認

#### Step 2: TextEncoding を実装する

```swift
// BefoldApp/BefoldKit/TextEncoding.swift
import Foundation

public enum TextEncodingError: Error {
    case unsupportedForChunking
    case decodeFailed
}

public enum TextEncoding {
    public static func detectBOM(_ data: Data) -> (encoding: String.Encoding, bomLength: Int)? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 4 {
            if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
                return (.utf32BigEndian, 4)
            }
            if bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
                return (.utf32LittleEndian, 4)
            }
        }
        if bytes.count >= 2 {
            if bytes[0] == 0xFE, bytes[1] == 0xFF { return (.utf16BigEndian, 2) }
            if bytes[0] == 0xFF, bytes[1] == 0xFE { return (.utf16LittleEndian, 2) }
        }
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return (.utf8, 3)
        }
        return nil
    }

    public static func isChunkableEncoding(_ data: Data) -> Bool {
        if let bom = detectBOM(data) {
            switch bom.encoding {
            case .utf16BigEndian, .utf16LittleEndian,
                 .utf32BigEndian, .utf32LittleEndian:
                return false
            default:
                return true
            }
        }
        let sniffWindow = data.prefix(8192)
        return !sniffWindow.contains(0)
    }

    public static func detectEncoding(_ data: Data) -> String.Encoding? {
        if let bom = detectBOM(data) {
            return bom.encoding
        }
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0 { return String.Encoding(rawValue: detected) }
        return nil
    }

    public static func decodeText(_ data: Data) -> String? {
        if let bom = detectBOM(data) {
            return String(data: data.dropFirst(bom.bomLength), encoding: bom.encoding)
        }
        if data.prefix(8192).contains(0) {
            let encoding: String.Encoding = looksLittleEndianUTF16(data)
                ? .utf16LittleEndian : .utf16BigEndian
            return String(data: data, encoding: encoding)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        var convertedString: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        if detected != 0, let result = convertedString {
            return result as String
        }
        return nil
    }

    static func looksLittleEndianUTF16(_ data: Data) -> Bool {
        let window = data.prefix(8192)
        var evenNul = 0, oddNul = 0
        for (index, byte) in window.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenNul += 1 } else { oddNul += 1 }
        }
        return oddNul >= evenNul
    }
}
```

- [ ] `BefoldApp/BefoldKit/TextEncoding.swift` を作成して上記を書く
- [ ] `swift test --filter TextEncodingTests` で全テスト PASS を確認

#### Step 3: DefaultFileReader を TextEncoding 委譲にリファクタリングする

`BefoldApp/BefoldKit/FileReading.swift` の `decodeUnicodeText` を `TextEncoding.decodeText` に委譲する。`detectBOM` / `hasUnicodeBOM` / `looksLikeUTF16` / `looksLittleEndianUTF16` / `nulCountsByParity` の private メソッドは TextEncoding に移動済みなので DefaultFileReader から削除する。

```swift
// DefaultFileReader.decodeUnicodeText → 置き換え
private static func decodeUnicodeText(_ data: Data) -> String? {
    TextEncoding.decodeText(data)
}
```

`detectBOM`、`hasUnicodeBOM`、`looksLikeUTF16`、`looksLittleEndianUTF16`、`nulCountsByParity` の 5 メソッドを削除。`isBinary(at:)` 内の UTF-16 BOM 判定は `TextEncoding.detectBOM` を使うように書き換える:

```swift
public func isBinary(at url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8192) else { return false }
    guard data.contains(0) else { return false }
    if TextEncoding.detectBOM(data) != nil { return false }
    if TextEncoding.isChunkableEncoding(data) == false, !data.contains(0) { return false }
    // BOM なし NUL 含む: UTF-16 の可能性チェック
    return !Self.looksLikeUTF16FromNulParity(data)
}
```

ただし `isBinary` の NUL パリティ判定は `TextEncoding.isChunkableEncoding` とは目的が異なる（isChunkableEncoding は「チャンク可か」、isBinary は「バイナリか」）。DefaultFileReader 側に残す `looksLikeUTF16FromNulParity` ヘルパーは、TextEncoding の `looksLittleEndianUTF16` と共有可能な NUL パリティカウントを使う。

実際の実装では既存の `isBinary` テスト（DefaultFileReaderTests）がすべて通ることを確認しながらリファクタリングする。

- [ ] `FileReading.swift` から `detectBOM` / `decodeUnicodeText` / `hasUnicodeBOM` / `looksLittleEndianUTF16` / `nulCountsByParity` を削除し、`TextEncoding` 呼び出しに置き換える
- [ ] `isBinary` を `TextEncoding.detectBOM` ベースに書き換える（NUL パリティ判定は要検討、既存の `looksLikeUTF16` ロジックを inline か TextEncoding に移動）
- [ ] `swift test --filter DefaultFileReaderTests` で既存テスト全 PASS を確認
- [ ] `swift test` で全テスト PASS を確認

#### Step 4: ChunkedTextReading プロトコルを定義する

```swift
// BefoldApp/BefoldKit/LineChunkReader.swift（ファイル先頭）
import Foundation

public protocol ChunkedTextReading: AnyObject {
    var isAtEnd: Bool { get }
    func readNextChunk() throws -> String
}
```

- [ ] `BefoldApp/BefoldKit/LineChunkReader.swift` を作成してプロトコルを書く

#### Step 5: LineChunkReader のテストを書く

```swift
// BefoldApp/befoldTests/LineChunkReaderTests.swift（TextEncodingTests の下に追加）
@Suite(.serialized)
struct LineChunkReaderTests {
    @Test("1000 行未満のファイルは 1 チャンクで完結する")
    func smallFileCompletesInOneChunk() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let lines = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let file = try tmp.file(named: "small.txt", contents: lines)

        let reader = try LineChunkReader(url: file)
        let chunk = try reader.readNextChunk()

        #expect(chunk == lines)
        #expect(reader.isAtEnd)
    }

    @Test("1000 行を超えるファイルは複数チャンクに分かれる")
    func largeFileSplitsIntoChunks() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let lines = (1...2500).map { "line \($0)" }.joined(separator: "\n")
        let file = try tmp.file(named: "large.txt", contents: lines)

        let reader = try LineChunkReader(url: file)

        let chunk1 = try reader.readNextChunk()
        #expect(!reader.isAtEnd)
        let chunk1Lines = chunk1.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(chunk1Lines.count == 1000)

        let chunk2 = try reader.readNextChunk()
        #expect(!reader.isAtEnd)

        let chunk3 = try reader.readNextChunk()
        #expect(reader.isAtEnd)

        let reconstructed = chunk1 + chunk2 + chunk3
        #expect(reconstructed == lines)
    }

    @Test("UTF-8 BOM 付きファイルを正しく読める")
    func utf8BomFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let content = "こんにちは\n世界"
        let bom = Data([0xEF, 0xBB, 0xBF])
        let data = bom + Data(content.utf8)
        let file = try tmp.file(named: "bom.txt", data: data)

        let reader = try LineChunkReader(url: file)
        let chunk = try reader.readNextChunk()
        #expect(chunk == content)
        #expect(reader.isAtEnd)
    }

    @Test("UTF-16 BOM 付きファイルは unsupportedForChunking を throw する")
    func utf16BomThrows() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let data = Data([0xFF, 0xFE, 0x41, 0x00, 0x0A, 0x00])
        let file = try tmp.file(named: "utf16.txt", data: data)

        #expect(throws: TextEncodingError.unsupportedForChunking) {
            try LineChunkReader(url: file)
        }
    }

    @Test("CP932 ファイルを正しく読める")
    func cp932File() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "表示\n価格"
        guard let cp932Data = (text as NSString).data(
            using: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
            )
        ) else {
            Issue.record("CP932 エンコードに失敗")
            return
        }
        let file = try tmp.file(named: "cp932.csv", data: cp932Data)

        let reader = try LineChunkReader(url: file)
        let chunk = try reader.readNextChunk()
        #expect(chunk.contains("表示"))
        #expect(reader.isAtEnd)
    }

    @Test("改行なし巨大行は maxChunkBytes で切断される")
    func noNewlineForceSplitAtMaxBytes() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let longLine = String(repeating: "A", count: LineChunkReader.maxChunkBytes + 100)
        let file = try tmp.file(named: "noeol.txt", contents: longLine)

        let reader = try LineChunkReader(url: file)
        let chunk1 = try reader.readNextChunk()
        #expect(chunk1.count <= LineChunkReader.maxChunkBytes)
        #expect(!reader.isAtEnd)

        let chunk2 = try reader.readNextChunk()
        #expect(reader.isAtEnd)
        #expect(chunk1 + chunk2 == longLine)
    }

    @Test("UTF-8 マルチバイト文字の途中で切れない")
    func utf8MultibyteBoundary() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // 3 バイト文字 "あ" を maxChunkBytes 境界ぎりぎりに配置
        let padding = String(repeating: "A", count: LineChunkReader.maxChunkBytes - 1)
        let content = padding + "あいう"
        let file = try tmp.file(named: "multibyte.txt", contents: content)

        let reader = try LineChunkReader(url: file)
        let chunk1 = try reader.readNextChunk()
        // "あ" の 3 バイトのうち 1 バイトだけ読める位置では切断されず、
        // パディング末尾 or "あ" の直後で切れる
        #expect(chunk1.utf8.allSatisfy { byte in
            byte < 0x80 || (byte & 0xC0) != 0x80 || chunk1.utf8.count > 0
        })
        // chunk1 は valid UTF-8
        #expect(String(data: Data(chunk1.utf8), encoding: .utf8) != nil)
        #expect(!reader.isAtEnd)

        let chunk2 = try reader.readNextChunk()
        #expect(reader.isAtEnd)
        #expect(chunk1 + chunk2 == content)
    }

    @Test("空ファイルは空文字列 + isAtEnd")
    func emptyFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "empty.txt", contents: "")

        let reader = try LineChunkReader(url: file)
        let chunk = try reader.readNextChunk()
        #expect(chunk == "")
        #expect(reader.isAtEnd)
    }

    @Test("ちょうど 1000 行のファイルは isAtEnd = true")
    func exactly1000LinesIsAtEnd() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let lines = (1...1000).map { "line \($0)" }.joined(separator: "\n")
        let file = try tmp.file(named: "exact.txt", contents: lines)

        let reader = try LineChunkReader(url: file)
        let chunk = try reader.readNextChunk()
        let lineCount = chunk.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lineCount == 1000)
        #expect(reader.isAtEnd)
    }

    @Test("全チャンクを結合すると元の内容と一致する")
    func chunksReconstructOriginal() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let lines = (1...3333).map { "line \($0): content" }.joined(separator: "\n")
        let file = try tmp.file(named: "multi.txt", contents: lines)

        let reader = try LineChunkReader(url: file)
        var accumulated = ""
        while !reader.isAtEnd {
            accumulated += try reader.readNextChunk()
        }
        #expect(accumulated == lines)
    }
}
```

- [ ] テストを追加する
- [ ] `swift test --filter LineChunkReaderTests` で全テスト FAIL を確認

#### Step 6: LineChunkReader を実装する

```swift
// BefoldApp/BefoldKit/LineChunkReader.swift（プロトコルの下に追加）
public final class LineChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000
    public static let maxChunkBytes = 4 * 1024 * 1024

    public private(set) var isAtEnd = false

    private let handle: FileHandle
    private let encoding: String.Encoding
    private let bomLength: Int
    private var offset: UInt64
    private var remainder = Data()

    public init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        self.handle = handle

        guard let probe = try handle.read(upToCount: 8192), !probe.isEmpty else {
            self.encoding = .utf8
            self.bomLength = 0
            self.offset = 0
            self.isAtEnd = true
            return
        }

        guard TextEncoding.isChunkableEncoding(probe) else {
            try? handle.close()
            throw TextEncodingError.unsupportedForChunking
        }

        if let bom = TextEncoding.detectBOM(probe) {
            self.encoding = bom.encoding
            self.bomLength = bom.bomLength
        } else if let detected = TextEncoding.detectEncoding(probe) {
            self.encoding = detected
            self.bomLength = 0
        } else {
            self.encoding = .utf8
            self.bomLength = 0
        }

        self.offset = UInt64(bomLength)
        try handle.seek(toOffset: self.offset)
    }

    deinit {
        try? handle.close()
    }

    public func readNextChunk() throws -> String {
        guard !isAtEnd else { return "" }

        var buffer = remainder
        remainder = Data()
        let bytesToRead = Self.maxChunkBytes - buffer.count
        if bytesToRead > 0 {
            if let fresh = try handle.read(upToCount: bytesToRead) {
                buffer.append(fresh)
            }
        }

        if buffer.isEmpty {
            isAtEnd = true
            return ""
        }

        let atFileEnd = buffer.count < Self.maxChunkBytes && remainder.isEmpty

        var lineCount = 0
        var splitIndex: Data.Index?

        for i in buffer.indices where buffer[i] == 0x0A {
            lineCount += 1
            if lineCount >= Self.linesPerChunk {
                splitIndex = buffer.index(after: i)
                break
            }
        }

        let chunkData: Data
        if let splitIndex {
            chunkData = buffer[buffer.startIndex ..< splitIndex]
            remainder = Data(buffer[splitIndex...])
            let peekAtEnd = remainder.isEmpty && {
                guard let peek = try? handle.read(upToCount: 1) else { return true }
                if peek.isEmpty { return true }
                remainder.insert(contentsOf: peek, at: remainder.startIndex)
                return false
            }()
            isAtEnd = peekAtEnd
        } else if atFileEnd {
            chunkData = buffer
            isAtEnd = true
        } else {
            chunkData = trimToCharacterBoundary(buffer)
            remainder = Data(buffer[chunkData.endIndex...])
            isAtEnd = false
        }

        guard let text = String(data: chunkData, encoding: encoding) else {
            throw TextEncodingError.decodeFailed
        }
        return text
    }

    private func trimToCharacterBoundary(_ data: Data) -> Data {
        guard encoding == .utf8 else { return data }
        var end = data.endIndex
        while end > data.startIndex {
            let byte = data[data.index(before: end)]
            if byte & 0x80 == 0 { break }
            if byte & 0xC0 != 0x80 {
                end = data.index(before: end)
                break
            }
            end = data.index(before: end)
        }
        return data[data.startIndex ..< end]
    }
}
```

- [ ] 実装を書く
- [ ] `swift test --filter LineChunkReaderTests` で全テスト PASS を確認
- [ ] `swift test` で全テスト PASS を確認

#### Step 7: コミット

```bash
git add BefoldApp/BefoldKit/TextEncoding.swift \
        BefoldApp/BefoldKit/LineChunkReader.swift \
        BefoldApp/BefoldKit/FileReading.swift \
        BefoldApp/befoldTests/LineChunkReaderTests.swift
git commit -m "feat: 行チャンクリーダーとエンコーディング検出ユーティリティを追加する"
```

- [ ] コミットする

---

### Task 2: FileType.isLineOriented + ContentLoader 変更

**Files:**
- Modify: `BefoldApp/BefoldKit/FileType.swift:146-166`
- Modify: `BefoldApp/BefoldKit/ContentLoader.swift`（全体）
- Modify: `BefoldApp/befoldTests/FileTypeTests.swift`
- Modify: `BefoldApp/befoldTests/ContentLoaderTests.swift`

**Interfaces:**
- Consumes: `LineChunkReader`（Task 1）、`ChunkedTextReading`（Task 1）
- Produces:
  - `FileType.isLineOriented: Bool`（csv/code が true、他は false）
  - `ContentLoader.openChunked(from: URL) throws -> LineChunkReader`
  - `ContentLoader.maxTextFileSizeBytes: Int`（`previewSizeBytes` と同値の別名。Task 4 で `previewSizeBytes` を削除）

#### Step 1: FileType.isLineOriented のテストを書く

```swift
// BefoldApp/befoldTests/FileTypeTests.swift に追加
@Test(arguments: [
    (FileType.csv(delimiter: ","), true),
    (FileType.csv(delimiter: "\t"), true),
    (FileType.code(language: "swift"), true),
    (FileType.code(language: "plaintext"), true),
    (FileType.mmd, false),
    (FileType.markdown, false),
    (FileType.svg, false),
    (FileType.html, false),
    (FileType.image(mimeType: "image/png"), false),
    (FileType.pdf, false),
])
func isLineOriented(fileType: FileType, expected: Bool) {
    #expect(fileType.isLineOriented == expected)
}
```

- [ ] テストを追加する
- [ ] `swift test --filter FileTypeTests/isLineOriented` で FAIL を確認

#### Step 2: FileType.isLineOriented を実装する

```swift
// BefoldApp/BefoldKit/FileType.swift に追加（supportsSourceMode の後あたり）
/// 行指向の形式かどうか。チャンク読み込みの対象判定に使う。
/// CSV/TSV とコード（プレーンテキスト含む）が該当する。
/// Markdown/Mermaid/HTML/SVG は途中切断で描画が壊れるため対象外。
public var isLineOriented: Bool {
    switch self {
    case .csv, .code: true
    default: false
    }
}
```

- [ ] 実装を追加する
- [ ] `swift test --filter FileTypeTests` で全テスト PASS を確認

#### Step 3: ContentLoader.openChunked のテストを書く

```swift
// BefoldApp/befoldTests/ContentLoaderTests.swift に追加
@Test("openChunked は行指向ファイルの LineChunkReader を返す")
func openChunkedReturnsReader() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file = try tmp.file(named: "data.csv", contents: "a,b\n1,2\n3,4")
    let loader = ContentLoader(fileReader: DefaultFileReader())

    let reader = try loader.openChunked(from: file)
    let chunk = try reader.readNextChunk()
    #expect(chunk == "a,b\n1,2\n3,4")
    #expect(reader.isAtEnd)
}

@Test("openChunked は UTF-16 ファイルで unsupportedForChunking を throw する")
func openChunkedThrowsForUtf16() throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let data = Data([0xFF, 0xFE, 0x41, 0x00, 0x0A, 0x00])
    let file = try tmp.file(named: "utf16.csv", data: data)
    let loader = ContentLoader(fileReader: DefaultFileReader())

    #expect(throws: TextEncodingError.unsupportedForChunking) {
        try loader.openChunked(from: file)
    }
}
```

- [ ] テストを追加する
- [ ] `swift test --filter ContentLoaderTests/openChunked` で FAIL を確認

#### Step 4: ContentLoader に openChunked と maxTextFileSizeBytes を追加する

`loadPreview` と `previewSizeBytes` はこの時点では**削除しない**（ViewerStore が参照しているため）。Task 4 で ViewerStore を書き換えた後に削除する。

```swift
// BefoldApp/BefoldKit/ContentLoader.swift に追加
public struct ContentLoader: Sendable {
    // 既存の maxFileSizeBytes, previewSizeBytes はそのまま残す

    /// 非行指向テキスト（Markdown/Mermaid/HTML/SVG）の上限。
    /// previewSizeBytes と同値。Task 4 完了後に previewSizeBytes を削除する。
    public static let maxTextFileSizeBytes = 10 * 1024 * 1024

    // 既存の LoadedContent, init, load, loadPreview はそのまま残す

    /// 行指向ファイルのチャンク読み込みセッションを開く。
    /// URL のシンボリックリンクを解決してから LineChunkReader を生成する。
    public func openChunked(from url: URL) throws -> LineChunkReader {
        let resolved = url.resolvingSymlinksInPath()
        return try LineChunkReader(url: resolved)
    }
}
```

- [ ] `openChunked` と `maxTextFileSizeBytes` を追加する（既存コードは変更しない）
- [ ] `swift test --filter ContentLoaderTests` で全テスト PASS を確認
- [ ] `swift test` で全テスト PASS を確認（プロジェクト全体がコンパイルできることを保証）

#### Step 5: コミット

```bash
git add BefoldApp/BefoldKit/FileType.swift \
        BefoldApp/BefoldKit/ContentLoader.swift \
        BefoldApp/befoldTests/FileTypeTests.swift \
        BefoldApp/befoldTests/ContentLoaderTests.swift
git commit -m "feat: FileType.isLineOriented と ContentLoader.openChunked を追加する"
```

- [ ] コミットする

---

### Task 3: JS appendChunk + バナー刷新 + ローカライズ + ViewerBridge

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/viewer.html:24`
- Modify: `BefoldApp/BefoldKit/Resources/viewer.js`（末尾に追加）
- Modify: `BefoldApp/BefoldKit/Resources/style.css:141-153`
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`
- Modify: `BefoldApp/befold/Resources/Localizable.xcstrings`
- Modify: `BefoldApp/befoldTests/ViewerBridgeTests.swift`

**Interfaces:**
- Consumes: `ViewerBridge.truncatedScript`（既存、シグネチャ変更）
- Produces:
  - JS: `appendChunk(text, type, lang)` / `_mmdSetTruncated(isTruncated, lineCount)` / `_mmdLoadMore()`
  - Swift: `ViewerBridge.appendChunkScript(chunk:fileType:) -> String?`
  - Swift: `ViewerBridge.truncatedScript(_:lineCount:) -> String`（パラメータ追加）
  - Swift: `ViewerBridge.bannerStringsScript(bundle:) -> String`
  - Swift: `ViewerBridge.loadMoreLinesMessageName: String`
  - xcstrings: `banner.showing` / `banner.loadMore`

#### Step 1: ViewerBridge のテストを書く

```swift
// BefoldApp/befoldTests/ViewerBridgeTests.swift に追加
@Test("appendChunkScript は JSON エスケープされた appendChunk 呼び出しを生成する")
func appendChunkScriptGeneratesCall() throws {
    let chunk = "line1\nline2\n\"quoted\""
    let script = try #require(
        ViewerBridge.appendChunkScript(chunk: chunk, fileType: .csv(delimiter: ","))
    )
    #expect(script.hasPrefix("appendChunk("))
    #expect(script.contains("'csv'"))
    #expect(!script.contains("\n"))
}

@Test("truncatedScript にカウントを渡せる")
func truncatedScriptWithLineCount() {
    let script = ViewerBridge.truncatedScript(true, lineCount: 1000)
    #expect(script == "_mmdSetTruncated(true, 1000)")
}

@Test("truncatedScript false はカウント 0")
func truncatedScriptFalse() {
    let script = ViewerBridge.truncatedScript(false, lineCount: 0)
    #expect(script == "_mmdSetTruncated(false, 0)")
}

@Test
func loadMoreLinesMessageNameIsDefined() {
    #expect(!ViewerBridge.loadMoreLinesMessageName.isEmpty)
}
```

- [ ] テストを追加する
- [ ] `swift test --filter ViewerBridgeTests` で新テスト FAIL を確認

#### Step 2: ViewerBridge にメソッドを追加する

```swift
// BefoldApp/BefoldKit/ViewerBridge.swift に追加

/// JS 側「続きを読み込む」ボタン押下時に postMessage されるメッセージハンドラ名。
public static let loadMoreLinesMessageName = "loadMoreLines"

/// appendChunk(content, type[, lang]) 呼び出しを組み立てる。
/// renderScript と同じ JSON エスケープを適用する。
public static func appendChunkScript(chunk: String, fileType: FileType) -> String? {
    guard let jsonData = try? JSONEncoder().encode(chunk),
          let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
    guard let lang = fileType.renderLangArgument else {
        return "appendChunk(\(jsonString), '\(fileType.jsValue)')"
    }
    let escaped = lang == "\t" ? "\\t" : lang
    return "appendChunk(\(jsonString), '\(fileType.jsValue)', '\(escaped)')"
}

/// バナーのローカライズ済み文字列を JS 側へ注入するスクリプト。
/// findStringsScript と同じ JSON 注入パターンに従う。
public static func bannerStringsScript(bundle: Bundle = .main) -> String {
    let strings: [String: String] = [
        "showing": String(localized: "banner.showing", bundle: bundle),
        "loadMore": String(localized: "banner.loadMore", bundle: bundle),
    ]
    guard let jsonData = try? JSONEncoder().encode(strings),
          let jsonString = String(data: jsonData, encoding: .utf8)
    else {
        return "window._mmdBannerStrings = {};"
    }
    return "window._mmdBannerStrings = \(jsonString);"
}
```

既存の `truncatedScript(_ isTruncated: Bool)` は**削除せず、オーバーロードを追加する**（ViewerWebView.Coordinator.applyRender が旧シグネチャを参照しているため。Task 4 で旧版を削除する）:

```swift
/// _mmdSetTruncated(isTruncated, lineCount) 呼び出しを組み立てる。
/// lineCount 付きの新バージョン。旧 truncatedScript(Bool) は Task 4 で削除する。
public static func truncatedScript(_ isTruncated: Bool, lineCount: Int) -> String {
    "_mmdSetTruncated(\(isTruncated), \(lineCount))"
}
```

- [ ] 上記オーバーロードを追加する（既存の `truncatedScript(Bool)` は残す）
- [ ] `swift test --filter ViewerBridgeTests` で新テスト PASS を確認

#### Step 3: Localizable.xcstrings にバナー文字列を追加する

`BefoldApp/befold/Resources/Localizable.xcstrings` に以下のキーを追加する:

- `banner.showing`: en = `"Showing %lld lines"`, ja = `"%lld 行を表示中"`
- `banner.loadMore`: en = `"Load More"`, ja = `"続きを読み込む"`

xcstrings の JSON 構造は既存エントリ（`viewer.find.*` 等）のパターンに従う。`%lld` は JS 側で `{count}` プレースホルダーに置き換えて使う（LocalizedStringResource のフォーマットは使わず、生文字列として注入するため `String(localized:)` でフォーマット引数は渡さない）。

**注意**: xcstrings の `%lld` は Swift 側で `String(localized:)` を通すと `String(format:)` の処理を期待する。しかし JS 側で `{count}` 置換する方がシンプルなので、xcstrings では `{count}` プレースホルダーを直接使い、Swift 側は生文字列として渡す:

- `banner.showing`: en = `"Showing {count} lines"`, ja = `"{count} 行を表示中"`
- `banner.loadMore`: en = `"Load More"`, ja = `"続きを読み込む"`

- [ ] xcstrings に 2 キーを追加する

#### Step 4: viewer.html のバナー HTML を更新する

```html
<!-- BefoldApp/BefoldKit/Resources/viewer.html:24 -->
<div id="mmd-truncated-banner" class="mmd-truncated-banner" style="display:none;">
  <span id="mmd-truncated-text"></span>
  <button id="mmd-load-more-btn" onclick="_mmdLoadMore()"></button>
</div>
```

- [ ] バナー HTML を書き換える

#### Step 5: viewer.js に appendChunk と _mmdLoadMore を追加する

```javascript
// BefoldApp/BefoldKit/Resources/viewer.js 末尾に追加

// チャンク追記: CSV は tbody に行追加、コード/テキストは既存 DOM に追記する。
// ソースモード中は呼ばれない（Swift 側が全文 re-render する）。
function appendChunk(text, type, lang) {
  var diagramWrap = document.getElementById('diagram-wrap');
  if (type === 'csv') {
    var rows = parseCsv(text, lang || ',');
    var tbody = diagramWrap.querySelector('tbody');
    if (!tbody) { return; }
    var maxCols = tbody.parentElement.querySelector('thead tr')
      ? tbody.parentElement.querySelector('thead tr').children.length : 0;
    for (var r = 0; r < rows.length; r++) {
      var tr = document.createElement('tr');
      var cols = Math.max(maxCols, rows[r].length);
      for (var c = 0; c < cols; c++) {
        var td = document.createElement('td');
        td.textContent = c < rows[r].length ? rows[r][c] : '';
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
  } else {
    // code / plaintext
    var codeEl = diagramWrap.querySelector('pre code');
    if (!codeEl) { return; }
    var table = codeEl.querySelector('table.code-table');
    if (table) {
      // 行番号付き: 行を追加
      var existingRows = table.querySelectorAll('tr');
      var startLine = existingRows.length + 1;
      var highlighted = highlightCode(window.hljs, text, lang);
      var inner = highlighted
        ? highlighted.replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '')
        : escapeHtml(text);
      var lines = inner.split('\n');
      if (lines.length > 1 && lines[lines.length - 1] === '') { lines.pop(); }
      var rows = '';
      for (var i = 0; i < lines.length; i++) {
        rows += '<tr><td class="line-number">' + (startLine + i)
          + '</td><td class="line-content">' + (lines[i] || '') + '</td></tr>';
      }
      table.insertAdjacentHTML('beforeend', rows);
    } else {
      // 行番号なし: テキスト追記
      var highlighted = highlightCode(window.hljs, text, lang);
      if (highlighted) {
        var inner = highlighted.replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '');
        codeEl.insertAdjacentHTML('beforeend', inner);
      } else {
        codeEl.insertAdjacentHTML('beforeend', escapeHtml(text));
      }
    }
  }
  _annotatePathRefs();
  _mmdFindRefreshAfterRender();
}
```

- [ ] `appendChunk` 関数を viewer.js 末尾に追加する

#### Step 6: viewer.html の _mmdSetTruncated と _mmdLoadMore を更新する

```javascript
// BefoldApp/BefoldKit/Resources/viewer.html
// 既存の _mmdSetTruncated (819-822行目) を置き換える。
// 旧呼び出し _mmdSetTruncated(bool) との後方互換のため lineCount は省略可能にする。
function _mmdSetTruncated(isTruncated, lineCount) {
    var banner = document.getElementById('mmd-truncated-banner');
    if (!isTruncated) {
        banner.style.display = 'none';
        return;
    }
    banner.style.display = 'flex';
    var strings = window._mmdBannerStrings || {};
    var textEl = document.getElementById('mmd-truncated-text');
    if (typeof lineCount === 'number') {
        textEl.textContent = (strings.showing || 'Showing {count} lines').replace('{count}', lineCount);
        var btn = document.getElementById('mmd-load-more-btn');
        btn.textContent = strings.loadMore || 'Load More';
        btn.style.display = 'inline-block';
    } else {
        textEl.textContent = strings.showing
            ? strings.showing.replace('{count}', '?')
            : 'Showing partial content';
        document.getElementById('mmd-load-more-btn').style.display = 'none';
    }
}

function _mmdLoadMore() {
    window.webkit.messageHandlers.loadMoreLines.postMessage({});
}
```

- [ ] `_mmdSetTruncated` を置き換え、`_mmdLoadMore` を追加する

#### Step 7: style.css のバナースタイルを更新する

```css
/* BefoldApp/BefoldKit/Resources/style.css — 既存の .mmd-truncated-banner を置き換える */
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
  color: var(--fg);
  border-top: 1px solid rgba(255, 204, 0, 0.3);
  display: none;
  align-items: center;
  justify-content: center;
  gap: 12px;
}

.mmd-truncated-banner button {
  background: rgba(255, 204, 0, 0.3);
  color: var(--fg);
  border: 1px solid rgba(255, 204, 0, 0.5);
  border-radius: 4px;
  padding: 2px 12px;
  font-size: 12px;
  cursor: pointer;
}

.mmd-truncated-banner button:hover {
  background: rgba(255, 204, 0, 0.5);
}
```

- [ ] CSS を更新する

#### Step 8: ViewerWebView にバナー文字列注入を追加する

`BefoldApp/befold/Viewer/ViewerWebView.swift` の `makeNSView` に、`findStringsScript` と同じパターンで `bannerStringsScript` を WKUserScript として注入する:

```swift
// makeNSView 内、findStringsScript の後に追加:
let bannerStringsScript = WKUserScript(
    source: ViewerBridge.bannerStringsScript(bundle: .l10n),
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(bannerStringsScript)
```

- [ ] WKUserScript を追加する

#### Step 9: 全テストの整合性を確認する

旧 `truncatedScript(Bool)` をオーバーロードとして残しているため、既存の呼び出し箇所はコンパイルが通る。プロジェクト全体のテストを実行して整合性を確認する。

- [ ] `swift test` で全テスト PASS を確認

#### Step 10: コミット

```bash
git add BefoldApp/BefoldKit/Resources/viewer.html \
        BefoldApp/BefoldKit/Resources/viewer.js \
        BefoldApp/BefoldKit/Resources/style.css \
        BefoldApp/BefoldKit/ViewerBridge.swift \
        BefoldApp/befold/Resources/Localizable.xcstrings \
        BefoldApp/befold/Viewer/ViewerWebView.swift \
        BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: チャンク追記用 JS 関数とバナー刷新を実装する"
```

- [ ] コミットする

---

### Task 4: ViewerStore + ViewerWebView 統合 + 旧コード削除

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift`（大幅変更）
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift:33-47`
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift`（メッセージハンドラ追加、Coordinator 変更）
- Modify: `BefoldApp/BefoldKit/ContentLoader.swift`（`loadPreview` / `previewSizeBytes` 削除）
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift`（旧 `truncatedScript(Bool)` 削除）
- Modify: `BefoldApp/befoldTests/ViewerStoreTests.swift`
- Modify: `BefoldApp/befoldTests/ContentLoaderTests.swift`（`loadPreview` テスト削除）
- Modify: `BefoldApp/befoldTests/ViewerBridgeTests.swift`（旧 `truncatedScript` テスト削除）

**Interfaces:**
- Consumes:
  - `ChunkedTextReading`（Task 1）
  - `LineChunkReader`（Task 1）
  - `FileType.isLineOriented`（Task 2）
  - `ContentLoader.openChunked(from:)`（Task 2）
  - `ContentLoader.maxTextFileSizeBytes`（Task 2）
  - `ViewerBridge.appendChunkScript(chunk:fileType:)`（Task 3）
  - `ViewerBridge.truncatedScript(_:lineCount:)`（Task 3）
  - `ViewerBridge.loadMoreLinesMessageName`（Task 3）
  - JS `appendChunk(text, type, lang)`（Task 3）
- Produces:
  - `ViewerStore.loadMoreLines() -> (chunk: String, isTruncated: Bool, lineCount: Int)?`
  - `ViewerStore.displayedLineCount: Int`
  - `ViewerWebView.onLoadMoreLines` コールバック

#### Step 1: ViewerStore のテストダブル（MockChunkedReader）を作成する

```swift
// BefoldApp/befoldTests/ViewerStoreTests.swift 冒頭の private 領域に追加
private final class MockChunkedReader: ChunkedTextReading {
    private var chunks: [String]
    private var index = 0

    init(chunks: [String]) {
        self.chunks = chunks
    }

    var isAtEnd: Bool { index >= chunks.count }

    func readNextChunk() throws -> String {
        guard index < chunks.count else { return "" }
        defer { index += 1 }
        return chunks[index]
    }
}
```

- [ ] テストダブルを追加する

#### Step 2: ViewerStore のチャンク読み込みテストを書く

```swift
// BefoldApp/befoldTests/ViewerStoreTests.swift に追加

@Test("行指向ファイルは初回チャンクのみ表示し isTruncated = true になる")
func lineOrientedFileShowsFirstChunk() {
    let file = URL(fileURLWithPath: "/files/data.csv")
    let reader = InMemoryFileReader()
    reader.setFile("a,b\n1,2\n3,4", at: file)
    let chunks = ["a,b\n1,2\n", "3,4"]
    let store = makeStore(
        reader: reader,
        chunkedReaderFactory: { _ in MockChunkedReader(chunks: chunks) }
    )
    store.openFile(file)

    #expect(store.content == "a,b\n1,2\n")
    #expect(store.isTruncated == true)
    #expect(store.displayedLineCount == 2)

    store.close()
}

@Test("loadMoreLines は次チャンクを蓄積し isTruncated を更新する")
func loadMoreLinesAccumulatesContent() {
    let file = URL(fileURLWithPath: "/files/data.csv")
    let reader = InMemoryFileReader()
    reader.setFile("a,b\n1,2\n3,4", at: file)
    let chunks = ["a,b\n1,2\n", "3,4"]
    let store = makeStore(
        reader: reader,
        chunkedReaderFactory: { _ in MockChunkedReader(chunks: chunks) }
    )
    store.openFile(file)

    let result = store.loadMoreLines()

    #expect(result != nil)
    #expect(result?.chunk == "3,4")
    #expect(store.content == "a,b\n1,2\n3,4")
    #expect(store.isTruncated == false)

    store.close()
}

@Test("loadMoreLines は全チャンク読み込み後は nil を返す")
func loadMoreLinesReturnsNilWhenComplete() {
    let file = URL(fileURLWithPath: "/files/data.csv")
    let reader = InMemoryFileReader()
    reader.setFile("a,b", at: file)
    let store = makeStore(
        reader: reader,
        chunkedReaderFactory: { _ in MockChunkedReader(chunks: ["a,b"]) }
    )
    store.openFile(file)

    #expect(store.isTruncated == false)
    #expect(store.loadMoreLines() == nil)

    store.close()
}

@Test("FileWatcher 発火でチャンクセッションがリセットされる")
func fileWatcherResetChunkSession() {
    let file = URL(fileURLWithPath: "/files/data.csv")
    let reader = InMemoryFileReader()
    reader.setFile("a,b\n1,2\n3,4\n5,6", at: file)
    let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
    var callCount = 0
    let store = makeStore(
        reader: reader,
        onChangeBox: onChangeBox,
        chunkedReaderFactory: { _ in
            callCount += 1
            return MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4\n5,6"])
        }
    )
    store.openFile(file)
    #expect(callCount == 1)
    #expect(store.isTruncated == true)

    // load more で 2 チャンク目まで読む
    _ = store.loadMoreLines()
    #expect(store.isTruncated == false)

    // FileWatcher 発火 → リセット
    onChangeBox.get()?()
    #expect(callCount == 2)
    #expect(store.content == "a,b\n1,2\n")
    #expect(store.isTruncated == true)

    store.close()
}

@Test("非行指向ファイルは従来の一括読み込み")
func nonLineOrientedFileUsesFullLoad() {
    let file = URL(fileURLWithPath: "/files/doc.md")
    let reader = InMemoryFileReader()
    reader.setFile("# Hello\n\nWorld", at: file)
    let store = makeStore(reader: reader)
    store.openFile(file)

    #expect(store.content == "# Hello\n\nWorld")
    #expect(store.isTruncated == false)

    store.close()
}

@Test("非行指向テキストが 10MB を超えると fileTooLarge")
func nonLineOrientedTextOverLimitIsRejected() {
    let file = URL(fileURLWithPath: "/files/huge.md")
    let reader = InMemoryFileReader()
    reader.setFile("# Big", at: file)
    reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)
    let store = makeStore(reader: reader)
    store.openFile(file)

    #expect(store.rejectReason == .fileTooLarge)

    store.close()
}
```

- [ ] テストを追加する
- [ ] `swift test --filter ViewerStoreTests` でコンパイルエラーを確認（`chunkedReaderFactory` / `loadMoreLines` / `displayedLineCount` が未定義）

#### Step 3: `makeStore` ヘルパーを更新する

```swift
// BefoldApp/befoldTests/ViewerStoreTests.swift — makeStore を更新
@MainActor
private func makeStore(
    reader: InMemoryFileReader,
    onChangeBox: LockedBox<(@MainActor @Sendable () -> Void)?>? = nil,
    onRenameBox: LockedBox<(@MainActor @Sendable (URL) -> Void)?>? = nil,
    chunkedReaderFactory: (@MainActor @Sendable (URL) throws -> any ChunkedTextReading)? = nil,
    clock: any Clock<Duration> = ContinuousClock()
) -> ViewerStore {
    ViewerStore(
        watcherFactory: { _, onChange, onRename in
            onChangeBox?.set(onChange)
            onRenameBox?.set(onRename)
            return MockFileWatcher()
        },
        fileReader: reader,
        chunkedReaderFactory: chunkedReaderFactory,
        defaults: makeIsolatedDefaults(prefix: "ViewerStoreTests"),
        clock: clock
    )
}
```

- [ ] `makeStore` を更新する

#### Step 4: ViewerStore を実装する

`BefoldApp/befold/Viewer/ViewerStore.swift` を以下のように変更する:

**削除するもの:**
- `fullLoadTask: Task<Void, Never>?` プロパティ（119 行目）
- `fullLoadTask` の `cancel()` 呼び出し（95, 130-131, 192-193 行目）
- `loadContent()` 内の `needsDeferred` 分岐と `fullLoadTask` 生成（133-155 行目）
- `close()` 内の `fullLoadTask` キャンセル（192-193 行目）

**追加するもの:**

```swift
// プロパティ
typealias ChunkedReaderFactory = @MainActor @Sendable (URL) throws -> any ChunkedTextReading

private(set) var displayedLineCount: Int = 0
private var chunkSession: (any ChunkedTextReading)?
private let makeChunkedReader: ChunkedReaderFactory

// init に chunkedReaderFactory パラメータ追加
init(
    watcherFactory: WatcherFactory? = nil,
    fileReader: any FileReading = DefaultFileReader(),
    chunkedReaderFactory: ChunkedReaderFactory? = nil,
    defaults: UserDefaults = .standard,
    clock: any Clock<Duration> = ContinuousClock()
) {
    // ... 既存の初期化 ...
    self.makeChunkedReader = chunkedReaderFactory ?? { url in
        try LineChunkReader(url: url)
    }
}

/// 次チャンクを読み込み、content に蓄積する。
/// 戻り値は Coordinator が appendChunk JS を評価するために使う。
func loadMoreLines() -> (chunk: String, isTruncated: Bool, lineCount: Int)? {
    guard let session = chunkSession, !session.isAtEnd else { return nil }
    guard let chunk = try? session.readNextChunk() else { return nil }
    content += chunk
    isTruncated = !session.isAtEnd
    displayedLineCount += chunk.split(
        separator: "\n", omittingEmptySubsequences: false
    ).count
    return (chunk, isTruncated, displayedLineCount)
}
```

**`loadContent()` の書き換え:**

```swift
private func loadContent() {
    guard let filePath else { return }
    let resolved = filePath.resolvingSymlinksInPath()
    guard fileReader.fileExists(at: resolved) else {
        scheduleFileGone()
        return
    }
    fileGoneTask?.cancel()
    fileGoneTask = nil
    chunkSession = nil
    displayedLineCount = 0

    if fileType.isLineOriented {
        do {
            let reader = try makeChunkedReader(resolved)
            let firstChunk = try reader.readNextChunk()
            chunkSession = reader
            rejectReason = nil
            isTruncated = !reader.isAtEnd
            content = firstChunk
            displayedLineCount = firstChunk.split(
                separator: "\n", omittingEmptySubsequences: false
            ).count
        } catch is TextEncodingError {
            // UTF-16/32 → 一括読み込みにフォールバック
            loadFullContent(resolved: resolved)
        } catch {
            rejectReason = .unsupportedFormat
            content = ""
            isTruncated = false
        }
    } else {
        loadFullContent(resolved: resolved)
    }
    onContentReloaded?()
}

private func loadFullContent(resolved: URL) {
    let size = fileReader.fileSize(at: resolved)
    // 非行指向テキスト: 10MB 上限
    if !fileType.isBinaryContent,
       let size, size > ContentLoader.maxTextFileSizeBytes
    {
        rejectReason = .fileTooLarge
        content = ""
        isTruncated = false
        return
    }
    let loaded = contentLoader.load(from: resolved, fileType: fileType)
    rejectReason = loaded.rejectReason
    isTruncated = false
    content = loaded.content
}
```

**`close()` の更新:**

```swift
func close() {
    fileGoneTask?.cancel()
    fileGoneTask = nil
    chunkSession = nil
    fileWatcher?.stop()
    fileWatcher = nil
}
```

- [ ] ViewerStore を上記のとおり書き換える

#### Step 5: ViewerContentView に onLoadMoreLines を追加する

```swift
// BefoldApp/befold/Viewer/ViewerContentView.swift
struct ViewerContentView: View {
    let store: ViewerStore
    // ... 既存プロパティ ...

    var body: some View {
        ZStack {
            ViewerWebView(
                // ... 既存パラメータ ...
                onLoadMoreLines: {
                    store.loadMoreLines()
                },
                // ... 残りの既存パラメータ ...
            )
            // ...
        }
    }
}
```

- [ ] `onLoadMoreLines` パラメータを追加する

#### Step 6: ViewerWebView に loadMoreLines を統合する

**ViewerWebView 構造体にプロパティ追加:**

```swift
/// 「続きを読み込む」ボタン押下時に呼ばれるコールバック。
/// 戻り値: (チャンク, まだ続きがあるか, 表示中の行数)。nil なら何もしない。
let onLoadMoreLines: @MainActor () -> (chunk: String, isTruncated: Bool, lineCount: Int)?
```

**makeNSView にメッセージハンドラ登録を追加:**

```swift
// findOptionsChanged ハンドラの後に追加:
config.userContentController.add(
    WeakScriptMessageHandler(delegate: context.coordinator),
    name: ViewerBridge.loadMoreLinesMessageName
)
```

**dismantleNSView にハンドラ削除を追加:**

```swift
nsView.configuration.userContentController
    .removeScriptMessageHandler(forName: ViewerBridge.loadMoreLinesMessageName)
```

**updateNSView でコールバックを渡す:**

```swift
context.coordinator.onLoadMoreLines = onLoadMoreLines
```

**Coordinator にプロパティとハンドラを追加:**

```swift
var onLoadMoreLines: (@MainActor () -> (chunk: String, isTruncated: Bool, lineCount: Int)?)?
```

`userContentController(_:didReceive:)` に分岐を追加:

```swift
} else if message.name == ViewerBridge.loadMoreLinesMessageName {
    guard let result = onLoadMoreLines?(), let webView else { return }
    // lastRenderedContent を先に更新して、SwiftUI の updateNSView で
    // 二重 render が起きるのを防ぐ
    lastRenderedContent = (lastRenderedContent ?? "") + result.chunk
    lastIsTruncated = result.isTruncated

    if lastIsSourceMode == true {
        // ソースモードでは全文を再描画する
        guard let script = ViewerBridge.renderScript(
            content: Self.renderableContent(
                lastRenderedContent ?? "", fileType: lastRenderedFileType ?? .code(language: "plaintext"),
                filePath: lastRenderedFilePath, isSourceMode: true
            ),
            fileType: lastRenderedFileType ?? .code(language: "plaintext")
        ) else { return }
        webView.evaluateJavaScript(script)
    } else {
        // レンダリングモードでは差分追記
        if let script = ViewerBridge.appendChunkScript(
            chunk: result.chunk,
            fileType: lastRenderedFileType ?? .code(language: "plaintext")
        ) {
            webView.evaluateJavaScript(script)
        }
    }
    webView.evaluateJavaScript(
        ViewerBridge.truncatedScript(result.isTruncated, lineCount: result.lineCount)
    )
}
```

**applyRender 内の truncatedScript 呼び出しを更新:**

`truncatedScript` のシグネチャが `(Bool, lineCount: Int)` に変わったため、applyRender 内の呼び出しを修正する。`lineCount` は ViewerStore から取得する必要があるが、applyRender の引数に `isTruncated` しか渡されていない。

解決策: `updateContent` に `lineCount` パラメータを追加する。

```swift
// ViewerWebView.Coordinator.updateContent のシグネチャ変更:
func updateContent(
    _ content: String,
    fileType: FileType,
    filePath: URL?,
    isSourceMode: Bool,
    showLineNumbers: Bool,
    isTruncated: Bool,
    lineCount: Int
)

// applyRender のシグネチャにも lineCount を追加:
private func applyRender(
    webView: WKWebView, content: String, fileType: FileType,
    filePath: URL?, isSourceMode: Bool, showLineNumbers: Bool,
    isTruncated: Bool, lineCount: Int,
    restoreFromPersistedPosition: Bool
)
```

applyRender 内の truncatedScript 呼び出し:

```swift
if isTruncated != lastIsTruncated {
    webView.evaluateJavaScript(ViewerBridge.truncatedScript(isTruncated, lineCount: lineCount))
    lastIsTruncated = isTruncated
}
```

**updateNSView の呼び出しも更新:**

```swift
// ViewerWebView.updateNSView 内:
context.coordinator.updateContent(
    content,
    fileType: fileType,
    filePath: filePath,
    isSourceMode: isSourceMode,
    showLineNumbers: showLineNumbers,
    isTruncated: isTruncated,
    lineCount: lineCount  // ViewerWebView に新パラメータ追加が必要
)
```

ViewerWebView に `lineCount` パラメータを追加:

```swift
let lineCount: Int
```

ViewerContentView から渡す:

```swift
ViewerWebView(
    // ...
    lineCount: store.displayedLineCount,
    // ...
)
```

- [ ] ViewerWebView にプロパティ追加・メッセージハンドラ登録・Coordinator 変更をすべて実施する
- [ ] ViewerContentView から `onLoadMoreLines` と `lineCount` を渡す

#### Step 7: 旧コードを削除する

ViewerStore が `loadPreview` / `previewSizeBytes` / 旧 `truncatedScript(Bool)` を参照しなくなったので、これらを削除する。

**ContentLoader（`BefoldApp/BefoldKit/ContentLoader.swift`）:**
- `loadPreview` メソッド（53-69 行目）を全削除する
- `previewSizeBytes` 定数を削除する（`maxTextFileSizeBytes` が代替）

**ViewerBridge（`BefoldApp/BefoldKit/ViewerBridge.swift`）:**
- 旧 `truncatedScript(_ isTruncated: Bool) -> String` を削除する（`truncatedScript(_:lineCount:)` が代替）

**ContentLoaderTests（`BefoldApp/befoldTests/ContentLoaderTests.swift`）:**
- `loadPreview` を参照するテスト（`loadPreviewReturnsTruncated` 等）を削除する

**ViewerStoreTests（`BefoldApp/befoldTests/ViewerStoreTests.swift`）:**
- `fullLoadTask` / `needsDeferred` に依存するテストを削除する

- [ ] 上記の旧コードとテストを削除する
- [ ] `swift test` でコンパイルエラーがないことを確認する
- [ ] `swift test --filter ViewerStoreTests` で全テスト PASS を確認
- [ ] `swift test` で全テスト PASS を確認

#### Step 8: `/webview-smoke` 手動検証

以下のシナリオを手動確認する:

1. **小さい CSV**（100 行未満）: バナーなしで全量表示
2. **大きい CSV**（1,000 行超）: 初回 1,000 行表示 + バナー表示 + 「続きを読み込む」ボタン → クリックで追加行表示
3. **コードファイル**（.swift）: 行番号あり/なしの両方で追記動作確認
4. **プレーンテキスト**（.txt）: 同上
5. **ソースモード切替**: チャンク追記後にソースモード ↔ レンダリングモード切替
6. **FileWatcher リロード**: ファイルを外部エディタで変更 → 先頭チャンクから再表示
7. **Markdown / Mermaid**: 従来どおり一括読み込み、サイズ上限 10MB 動作
8. **画像 / PDF**: 従来どおり、50MB 上限

- [ ] 上記シナリオを `/webview-smoke` で確認する

#### Step 9: コミット

```bash
git add BefoldApp/befold/Viewer/ViewerStore.swift \
        BefoldApp/befold/Viewer/ViewerContentView.swift \
        BefoldApp/befold/Viewer/ViewerWebView.swift \
        BefoldApp/BefoldKit/ContentLoader.swift \
        BefoldApp/BefoldKit/ViewerBridge.swift \
        BefoldApp/befoldTests/ViewerStoreTests.swift \
        BefoldApp/befoldTests/ContentLoaderTests.swift \
        BefoldApp/befoldTests/ViewerBridgeTests.swift
git commit -m "feat: チャンク読み込みを ViewerStore に統合し段階読み込みを削除する"
```

- [ ] コミットする
