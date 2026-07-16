# NormalizedTextCache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace LineChunkReader's byte-level chunk processing with a two-layer architecture: NormalizedTextCache (全量デコード＋改行正規化) + StringChunkReader (String スライスによるチャンク分割).

**Architecture:** ファイルを全量読み込み→エンコーディング判定→デコード→CRLF/CR→LF正規化→行インデックス構築し、キャッシュとして保持する。チャンク切り出しはキャッシュの String をスライスするだけの純粋な文字列操作になる。検索は DOM 全量構築ではなくキャッシュの String を直接使う。

**Tech Stack:** Swift 6 / Swift Testing / BefoldKit

## Global Constraints

- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` の表示名で付ける
- Swift Testing フレームワーク (`import Testing`, `@Suite`, `@Test`, `#expect`)
- 行指向ファイルのサイズ上限: 100MB
- 非行指向テキストのサイズ上限: 10MB（既存の ContentLoader.maxTextFileSizeBytes）
- バイナリファイルのサイズ上限: 50MB（既存の ContentLoader.maxFileSizeBytes）
- UTF-16 / UTF-32 の行指向ファイルにも対応する

## File Structure

### New Files
- `BefoldApp/BefoldKit/NormalizedTextCache.swift` — 全量デコード＋改行正規化＋行インデックス
- `BefoldApp/BefoldKit/StringChunkReader.swift` — キャッシュからの String スライスチャンク
- `BefoldApp/befoldTests/NormalizedTextCacheTests.swift` — エンコーディング×改行コードの組み合わせテスト
- `BefoldApp/befoldTests/StringChunkReaderTests.swift` — チャンク分割テスト

### Modified Files
- `BefoldApp/befold/Viewer/ViewerStore.swift` — computeLoad / LoadOutcome / apply() をキャッシュベースに
- `BefoldApp/befold/Viewer/ViewerWebView.swift` — loadAllLinesForSearch ハンドラ削除
- `BefoldApp/BefoldKit/ViewerBridge.swift` — loadAllLinesForSearchMessageName / allLinesLoadedScript 削除
- `BefoldApp/BefoldKit/TextEncoding.swift` — 不要メソッド削除
- `BefoldApp/BefoldKit/ContentLoader.swift` — テキストパス削除、バイナリ専用に
- `BefoldApp/BefoldKit/Resources/viewer.html` — loadAllLinesForSearch 削除、部分検索対応
- `BefoldApp/befoldTests/LineChunkReaderTests.swift` — LineChunkReaderTests 削除、TextEncodingTests 更新
- `BefoldApp/befoldTests/ViewerStoreTests.swift` — ファクトリシグネチャ更新
- `BefoldApp/befoldTests/ContentLoaderTests.swift` — テキスト読み込みテスト削除

### Deleted Files
- `BefoldApp/BefoldKit/LineChunkReader.swift`

---

### Task 1: NormalizedTextCache

**Files:**
- Create: `BefoldApp/BefoldKit/NormalizedTextCache.swift`
- Test: `BefoldApp/befoldTests/NormalizedTextCacheTests.swift`

**Interfaces:**
- Consumes: `TextEncoding.detectEncoding(_:)` → `(encoding: String.Encoding, bomLength: Int)?`, `TextEncodingError.decodeFailed`
- Produces:
  - `NormalizedTextCache.init(data: Data) throws` — デコード＋正規化＋行インデックス構築
  - `NormalizedTextCache.text: String` — 正規化済み全文
  - `NormalizedTextCache.lineStartIndices: [String.Index]` — 各行の先頭位置
  - `NormalizedTextCache.lineCount: Int` — 総行数
  - `NormalizedTextCache.dataHash: Int` — 同一内容スキップ用ハッシュ
  - `NormalizedTextCache.maxFileSizeBytes: Int` = 100MB

- [ ] **Step 1: テストファイルを作成し、基本テストを書く**

```swift
// BefoldApp/befoldTests/NormalizedTextCacheTests.swift
import BefoldKit
import Foundation
import Testing

@Suite
struct NormalizedTextCacheTests {
    @Test("UTF-8 LF テキストをそのまま保持する")
    func utf8LFPreserved() throws {
        let text = "line1\nline2\nline3\n"
        let cache = try NormalizedTextCache(data: Data(text.utf8))
        #expect(cache.text == text)
        #expect(cache.lineCount == 3)
    }

    @Test("CRLF を LF に正規化する")
    func crlfNormalized() throws {
        let cache = try NormalizedTextCache(data: Data("a\r\nb\r\nc\r\n".utf8))
        #expect(cache.text == "a\nb\nc\n")
    }

    @Test("CR を LF に正規化する")
    func crNormalized() throws {
        let cache = try NormalizedTextCache(data: Data("a\rb\rc\r".utf8))
        #expect(cache.text == "a\nb\nc\n")
    }

    @Test("混在した改行コードを LF に統一する")
    func mixedLineEndings() throws {
        let cache = try NormalizedTextCache(data: Data("a\r\nb\rc\n".utf8))
        #expect(cache.text == "a\nb\nc\n")
    }

    @Test("行インデックスが各行の先頭を正しく指す")
    func lineStartIndicesAreAccurate() throws {
        let cache = try NormalizedTextCache(data: Data("ab\ncd\nef".utf8))
        #expect(cache.lineCount == 3)
        #expect(String(cache.text[cache.lineStartIndices[0]...]).hasPrefix("ab"))
        #expect(String(cache.text[cache.lineStartIndices[1]...]).hasPrefix("cd"))
        #expect(String(cache.text[cache.lineStartIndices[2]...]).hasPrefix("ef"))
    }

    @Test("末尾改行なしのテキストの行数")
    func noTrailingNewline() throws {
        let cache = try NormalizedTextCache(data: Data("a\nb".utf8))
        #expect(cache.lineCount == 2)
    }

    @Test("空データは空キャッシュを返す")
    func emptyData() throws {
        let cache = try NormalizedTextCache(data: Data())
        #expect(cache.text == "")
        #expect(cache.lineCount == 0)
    }

    @Test("UTF-8 BOM を除去してデコードする")
    func utf8BomStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello\n".utf8))
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "hello\n")
    }

    @Test("UTF-16 LE BOM 付きテキストをデコードする")
    func utf16LEBom() throws {
        var data = Data([0xFF, 0xFE])
        data.append("line1\r\nline2\n".data(using: .utf16LittleEndian)!)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "line1\nline2\n")
    }

    @Test("UTF-16 BE BOM 付きテキストをデコードする")
    func utf16BEBom() throws {
        var data = Data([0xFE, 0xFF])
        data.append("abc\n".data(using: .utf16BigEndian)!)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "abc\n")
    }

    @Test("Shift_JIS テキストをデコードする")
    func shiftJIS() throws {
        let text = "日本語テスト\n"
        let data = text.data(using: .shiftJIS)!
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == text)
    }

    @Test("EUC-JP テキストをデコードする")
    func eucJP() throws {
        let text = "日本語テスト\n"
        let data = text.data(using: .japaneseEUC)!
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == text)
    }

    @Test("デコード不可能なデータは decodeFailed を投げる")
    func undecodableThrows() {
        // UTF-16 LE BOM + 奇数バイト(不正な UTF-16)
        let data = Data([0xFF, 0xFE, 0x41])
        #expect(throws: TextEncodingError.decodeFailed) {
            try NormalizedTextCache(data: data)
        }
    }

    @Test("同一データは同一ハッシュを返す")
    func sameDataSameHash() throws {
        let data = Data("test\n".utf8)
        let a = try NormalizedTextCache(data: data)
        let b = try NormalizedTextCache(data: data)
        #expect(a.dataHash == b.dataHash)
    }

    @Test("異なるデータは異なるハッシュを返す")
    func differentDataDifferentHash() throws {
        let a = try NormalizedTextCache(data: Data("aaa\n".utf8))
        let b = try NormalizedTextCache(data: Data("bbb\n".utf8))
        #expect(a.dataHash != b.dataHash)
    }

    @Test("日本語マルチバイト文字の行インデックスが正しい")
    func multibyteLinesIndices() throws {
        let cache = try NormalizedTextCache(data: Data("あ\nい\nう".utf8))
        #expect(cache.lineCount == 3)
        let line2Start = cache.lineStartIndices[1]
        let line3Start = cache.lineStartIndices[2]
        #expect(String(cache.text[line2Start..<line3Start]) == "い\n")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter NormalizedTextCacheTests 2>&1 | tail -5`
Expected: コンパイルエラー（NormalizedTextCache が存在しない）

- [ ] **Step 3: NormalizedTextCache を実装する**

```swift
// BefoldApp/BefoldKit/NormalizedTextCache.swift
import Foundation

/// ファイルの全量デコード＋改行正規化＋行インデックスを保持するキャッシュ。
/// 生成時に I/O・デコード・正規化を 1 回だけ行い、以降はメモリ上の String として
/// チャンク切り出しや検索に使う。
public struct NormalizedTextCache: Sendable {
    /// 行指向テキストファイルのサイズ上限(100MB)。
    public static let maxFileSizeBytes = 100 * 1024 * 1024

    /// デコード＋正規化済みの全文(CRLF/CR → LF 済み)。
    public let text: String

    /// 各行の先頭位置。lineStartIndices[n] = n 行目の先頭。
    /// 空テキストでは空配列。
    public let lineStartIndices: [String.Index]

    /// 元データのハッシュ。同一内容スキップの比較に使う。
    public let dataHash: Int

    /// 総行数。
    public var lineCount: Int { lineStartIndices.count }

    /// 生データからキャッシュを生成する。
    /// エンコーディング判定・BOM 除去・デコード・改行正規化・行インデックス構築を行う。
    public init(data: Data) throws {
        dataHash = data.hashValue

        if data.isEmpty {
            text = ""
            lineStartIndices = []
            return
        }

        guard let detected = TextEncoding.detectEncoding(data) else {
            throw TextEncodingError.decodeFailed
        }
        guard let decoded = String(
            data: data.dropFirst(detected.bomLength),
            encoding: detected.encoding
        ) else {
            throw TextEncodingError.decodeFailed
        }

        text = Self.normalizeLineEndings(decoded)
        lineStartIndices = Self.buildLineStartIndices(text)
    }

    static func normalizeLineEndings(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func buildLineStartIndices(_ text: String) -> [String.Index] {
        guard !text.isEmpty else { return [] }
        var indices: [String.Index] = [text.startIndex]
        for i in text.utf8.indices where text.utf8[i] == 0x0A {
            let next = text.utf8.index(after: i)
            if next < text.utf8.endIndex {
                indices.append(next)
            }
        }
        return indices
    }
}
```

- [ ] **Step 4: テストが全て通ることを確認する**

Run: `cd BefoldApp && swift test --filter NormalizedTextCacheTests 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 5: コミットする**

```bash
cd BefoldApp
git add BefoldKit/NormalizedTextCache.swift befoldTests/NormalizedTextCacheTests.swift
git commit -m "feat: NormalizedTextCache を追加する

全量読み込み＋エンコーディング判定＋デコード＋CRLF/CR→LF 正規化＋
行インデックス構築を 1 回で行うキャッシュ構造体。"
```

---

### Task 2: StringChunkReader

**Files:**
- Create: `BefoldApp/BefoldKit/StringChunkReader.swift`
- Test: `BefoldApp/befoldTests/StringChunkReaderTests.swift`

**Interfaces:**
- Consumes: `NormalizedTextCache` (Task 1), `ChunkedTextReading` protocol
- Produces:
  - `StringChunkReader.init(cache: NormalizedTextCache, respectsCSVQuotes: Bool)` — キャッシュ参照を保持
  - `StringChunkReader.readNextChunk() -> (text: String, isAtEnd: Bool)` — 行インデックスからスライス
  - `StringChunkReader.linesPerChunk: Int` = 1000

- [ ] **Step 1: テストを書く**

```swift
// BefoldApp/befoldTests/StringChunkReaderTests.swift
import BefoldKit
import Foundation
import Testing

@Suite(.serialized)
struct StringChunkReaderTests {
    private func makeCache(_ text: String) throws -> NormalizedTextCache {
        try NormalizedTextCache(data: Data(text.utf8))
    }

    private func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line\($0)\n" }.joined()
    }

    private func readAll(_ reader: StringChunkReader) async -> [String] {
        var chunks: [String] = []
        while true {
            let result = await reader.readNextChunk()
            if !result.text.isEmpty { chunks.append(result.text) }
            if result.isAtEnd { break }
        }
        return chunks
    }

    @Test("500 行のファイルが 1 チャンクで完結する")
    func smallFileOneChunk() async throws {
        let text = makeLines(500)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.text == text)
        #expect(result.isAtEnd == true)
    }

    @Test("2500 行のファイルが 3 チャンクに分割される")
    func largeFileSplits() async throws {
        let text = makeLines(2500)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 3)
        #expect(chunks.joined() == text)
    }

    @Test("空キャッシュは空チャンクと isAtEnd を返す")
    func emptyCache() async throws {
        let cache = try makeCache("")
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.text == "")
        #expect(result.isAtEnd == true)
    }

    @Test("ちょうど 1000 行は 1 チャンクで isAtEnd")
    func exactly1000Lines() async throws {
        let text = makeLines(1000)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == true)
        #expect(result.text == text)
    }

    @Test("全チャンクを結合すると元テキストに一致する")
    func chunksReconstructOriginal() async throws {
        let text = makeLines(3333)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
    }

    @Test("CSV 引用符内の改行はチャンク境界にならない")
    func csvQuotedNewline() async throws {
        // 999 通常行 + 1 引用符内に改行を含む行 = 1000 物理行だが論理行は 1000 未満
        var lines = (0 ..< 998).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"  // 1 論理行 = 2 物理行
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let result = await reader.readNextChunk()
        // 引用符内の改行を数えないので 999 論理行 < 1000、1 チャンクで完結
        #expect(result.isAtEnd == true)
        #expect(result.text.contains("\"quoted\nfield\""))
    }

    @Test("CSV 引用符なしモードでは全改行がチャンク境界になる")
    func withoutCSVQuotes() async throws {
        var lines = (0 ..< 999).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"  // CSV quotes OFF → 物理行で数える
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: false)
        let result = await reader.readNextChunk()
        // 1002 物理行 > 1000 なので分割される
        #expect(result.isAtEnd == false)
    }

    @Test("読了後の再呼び出しは空チャンクを返す")
    func readAfterEnd() async throws {
        let cache = try makeCache("a\n")
        let reader = StringChunkReader(cache: cache)
        let first = await reader.readNextChunk()
        #expect(first.isAtEnd == true)
        let second = await reader.readNextChunk()
        #expect(second.text == "")
        #expect(second.isAtEnd == true)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd BefoldApp && swift test --filter StringChunkReaderTests 2>&1 | tail -5`
Expected: コンパイルエラー（StringChunkReader が存在しない）

- [ ] **Step 3: StringChunkReader を実装する**

```swift
// BefoldApp/BefoldKit/StringChunkReader.swift
import Foundation

/// NormalizedTextCache の行インデックスから String スライスでチャンクを切り出す actor。
/// LineChunkReader を置き換え、バイトレベルの複雑さを排除する。
public actor StringChunkReader: ChunkedTextReading {
    public static let linesPerChunk = 1000

    private let cache: NormalizedTextCache
    private let respectsCSVQuotes: Bool
    private var currentLine: Int = 0
    private var inQuotes: Bool = false

    public init(cache: NormalizedTextCache, respectsCSVQuotes: Bool = false) {
        self.cache = cache
        self.respectsCSVQuotes = respectsCSVQuotes
    }

    public func readNextChunk() -> (text: String, isAtEnd: Bool) {
        guard currentLine < cache.lineCount else { return ("", true) }

        let startIndex = cache.lineStartIndices[currentLine]
        let endLine: Int

        if respectsCSVQuotes {
            endLine = advanceRespectingQuotes()
        } else {
            endLine = min(currentLine + Self.linesPerChunk, cache.lineCount)
        }

        let endIndex = endLine < cache.lineCount
            ? cache.lineStartIndices[endLine]
            : cache.text.endIndex
        let chunk = String(cache.text[startIndex ..< endIndex])
        currentLine = endLine
        return (chunk, currentLine >= cache.lineCount)
    }

    private func advanceRespectingQuotes() -> Int {
        var linesConsumed = 0
        var scanLine = currentLine

        while scanLine < cache.lineCount {
            let lineStart = cache.lineStartIndices[scanLine]
            let lineEnd = scanLine + 1 < cache.lineCount
                ? cache.lineStartIndices[scanLine + 1]
                : cache.text.endIndex

            for ch in cache.text[lineStart ..< lineEnd] where ch == "\"" {
                inQuotes.toggle()
            }

            scanLine += 1

            if !inQuotes {
                linesConsumed += 1
                if linesConsumed >= Self.linesPerChunk {
                    break
                }
            }
        }

        return scanLine
    }
}
```

- [ ] **Step 4: テストが全て通ることを確認する**

Run: `cd BefoldApp && swift test --filter StringChunkReaderTests 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 5: コミットする**

```bash
cd BefoldApp
git add BefoldKit/StringChunkReader.swift befoldTests/StringChunkReaderTests.swift
git commit -m "feat: StringChunkReader を追加する

NormalizedTextCache の行インデックスから String スライスで
チャンクを切り出す actor。LineChunkReader のバイトレベル処理を
純粋な文字列操作に置き換える。"
```

---

### Task 3: ViewerStore 統合

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift`
- Modify: `BefoldApp/befoldTests/ViewerStoreTests.swift`

**Interfaces:**
- Consumes: `NormalizedTextCache` (Task 1), `StringChunkReader` (Task 2)
- Produces: ViewerStore が NormalizedTextCache を保持し、computeLoad が新フローを使う

- [ ] **Step 1: ViewerStore のファクトリ型とプロパティを更新する**

`ViewerStore.swift` に以下の変更を加える:

1. `ChunkedReaderFactory` の第一引数を `URL` から `NormalizedTextCache` に変更:

```swift
typealias ChunkedReaderFactory = @Sendable (NormalizedTextCache, FileType) throws -> any ChunkedTextReading
```

2. `textCache` プロパティを追加:

```swift
@ObservationIgnored private var textCache: NormalizedTextCache?
```

3. `contentHash` プロパティを追加（同一内容スキップ用）:

```swift
@ObservationIgnored private var contentHash: Int?
```

4. `init` のデフォルトファクトリを更新:

```swift
makeChunkedReader = chunkedReaderFactory ?? { cache, fileType in
    StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
}
```

5. `close()` でキャッシュを解放:

```swift
func close() {
    loadTask?.cancel()
    loadTask = nil
    fileGoneTask?.cancel()
    fileGoneTask = nil
    chunkSession = nil
    textCache = nil
    contentHash = nil
    fileWatcher?.stop()
    fileWatcher = nil
}
```

- [ ] **Step 2: LoadOutcome にキャッシュを追加する**

```swift
private enum LoadOutcome: Sendable {
    case missing
    case chunked(session: any ChunkedTextReading, cache: NormalizedTextCache, firstChunk: String, isAtEnd: Bool)
    case full(ContentLoader.LoadedContent, cache: NormalizedTextCache?)
}
```

- [ ] **Step 3: computeLoad を新フローに書き換える**

```swift
private nonisolated static func computeLoad(
    resolved: URL,
    fileType: FileType,
    fileReader: any FileReading,
    contentLoader: ContentLoader,
    chunkedReaderFactory: ChunkedReaderFactory
) async -> LoadOutcome {
    guard fileReader.fileExists(at: resolved) else { return .missing }

    if fileType.isBinaryContent {
        return .full(contentLoader.load(from: resolved, fileType: fileType), cache: nil)
    }

    if fileReader.isBinary(at: resolved) {
        return .full(
            ContentLoader.LoadedContent(rejectReason: .unsupportedFormat, content: ""),
            cache: nil
        )
    }

    if let size = fileReader.fileSize(at: resolved),
       size > NormalizedTextCache.maxFileSizeBytes
    {
        return .full(
            ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
            cache: nil
        )
    }

    do {
        let data = try fileReader.readData(from: resolved)
        let cache = try NormalizedTextCache(data: data)

        if fileType.isLineOriented {
            let reader = try chunkedReaderFactory(cache, fileType)
            let firstChunk = try await reader.readNextChunk()
            return .chunked(
                session: reader, cache: cache,
                firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
            )
        } else {
            if cache.text.utf8.count > ContentLoader.maxTextFileSizeBytes {
                return .full(
                    ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                    cache: nil
                )
            }
            return .full(
                ContentLoader.LoadedContent(rejectReason: nil, content: cache.text),
                cache: cache
            )
        }
    } catch {
        if !fileReader.fileExists(at: resolved) { return .missing }
        return .full(
            ContentLoader.LoadedContent(rejectReason: .unsupportedFormat, content: ""),
            cache: nil
        )
    }
}
```

- [ ] **Step 4: apply() を更新してキャッシュを保持し、同一内容スキップを行う**

```swift
private func apply(_ outcome: LoadOutcome) {
    switch outcome {
    case .missing:
        scheduleFileGone()
        return
    case let .chunked(session, cache, firstChunk, isAtEnd):
        if cache.dataHash == contentHash {
            return
        }
        textCache = cache
        contentHash = cache.dataHash
        chunkSession = session
        rejectReason = nil
        isTruncated = !isAtEnd
        content = firstChunk
        contentRevision += 1
        newlineCount = firstChunk.utf8.count(where: { $0 == 0x0A })
        updateDisplayedLineCount()
    case let .full(loaded, cache):
        if let cache, cache.dataHash == contentHash {
            return
        }
        textCache = cache
        contentHash = cache?.dataHash
        chunkSession = nil
        rejectReason = loaded.rejectReason
        isTruncated = false
        content = loaded.content
        contentRevision += 1
        newlineCount = 0
        displayedLineCount = 0
    }
    fileGoneTask?.cancel()
    fileGoneTask = nil
    onContentReloaded?()
}
```

- [ ] **Step 5: ViewerStoreTests のファクトリシグネチャを更新する**

`ViewerStoreTests.swift` の `makeStore` ヘルパーと各テストで使っている
`chunkedReaderFactory` クロージャの第一引数を `URL` から `NormalizedTextCache` に変更:

```swift
// Before:
chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: [...]) }
// After:
chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: [...]) }
```

モックは引数を無視するため、クロージャの本体は変わらない。
型アノテーションが明示されている場合のみパラメータ型を更新する:

```swift
// Before:
chunkedReaderFactory: { (url: URL, type: FileType) in ... }
// After:
chunkedReaderFactory: { (cache: NormalizedTextCache, type: FileType) in ... }
```

`chunkedReaderFactoryReceivesFileType` テストはファクトリの第一引数が
`NormalizedTextCache` であることを反映して型を更新する。

`InMemoryFileReader` で設定済みのテキストファイルは `readData` でも
UTF-8 バイト列を返す必要がある。`setFile(_:at:)` がすでに
内部で UTF-8 Data を保持しているか確認し、必要なら更新する。

- [ ] **Step 6: テストが全て通ることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: 全テスト pass（LineChunkReaderTests 含む — まだ削除していない）

- [ ] **Step 7: コミットする**

```bash
cd BefoldApp
git add befold/Viewer/ViewerStore.swift befoldTests/ViewerStoreTests.swift befoldTests/ViewerStoreFileGoneTests.swift
git commit -m "refactor: ViewerStore を NormalizedTextCache ベースに移行する

computeLoad が NormalizedTextCache でデコード＋正規化を行い、
StringChunkReader でチャンクを切り出す。ファクトリシグネチャを
(URL, FileType) から (NormalizedTextCache, FileType) に変更。
同一内容スキップ(dataHash 比較)を apply() に追加。"
```

---

### Task 4: デッドコード削除

**Files:**
- Delete: `BefoldApp/BefoldKit/LineChunkReader.swift`
- Modify: `BefoldApp/BefoldKit/TextEncoding.swift` — 不要メソッド削除
- Modify: `BefoldApp/befoldTests/LineChunkReaderTests.swift` — LineChunkReaderTests 削除、TextEncodingTests 更新

**Interfaces:**
- Consumes: なし（削除のみ）
- Produces: なし

- [ ] **Step 1: LineChunkReader.swift を削除する**

```bash
cd BefoldApp
git rm BefoldKit/LineChunkReader.swift
```

- [ ] **Step 2: TextEncoding から不要メソッドを削除する**

`BefoldApp/BefoldKit/TextEncoding.swift` から以下を削除:

- `isChunkableEncoding(_:)` メソッド（行 39-54）
- `trimIncompleteUTF8Tail(_:)` メソッド（行 97-111）
- `trimIncompleteTail(_:encoding:)` メソッド（行 116-130）

`TextEncodingError` から `unsupportedForChunking` case を削除:

```swift
public enum TextEncodingError: Error, Sendable {
    /// 検出したエンコーディングでの復号に失敗した。
    case decodeFailed
}
```

- [ ] **Step 3: LineChunkReaderTests.swift を更新する**

ファイルを `TextEncodingTests.swift` にリネーム:

```bash
cd BefoldApp
git mv befoldTests/LineChunkReaderTests.swift befoldTests/TextEncodingTests.swift
```

`LineChunkReaderTests` suite を完全に削除する。

`TextEncodingTests` から削除したメソッドのテストを除去:
- `utf16IsNotChunkable` — `isChunkableEncoding` 削除のため
- `utf8BomIsChunkable` — 同上
- `plainUtf8IsChunkable` — 同上
- `nulContainingDataIsNotChunkable` — 同上
- `trimIncompleteUTF8TailRemovesPartialCharacter` — `trimIncompleteUTF8Tail` 削除のため

残す `TextEncodingTests`:
- `detectsUtf8Bom`
- `detectsUtf16LeBom`
- `detectsUtf16BeBom`
- `detectsUtf32LeBom`
- `noBomReturnsNil`

(BOM 検出テストは NormalizedTextCache が使う `detectEncoding` の入力として維持)

- [ ] **Step 4: ContentLoader からテキスト読み込みパスを削除する**

`BefoldApp/BefoldKit/ContentLoader.swift` を簡素化。
`computeLoad` からテキストファイルで呼ばれなくなったため、
バイナリパスのみ残す:

```swift
public struct ContentLoader: Sendable {
    public static let maxFileSizeBytes = 50 * 1024 * 1024
    public static let maxTextFileSizeBytes = 10 * 1024 * 1024

    public struct LoadedContent: Sendable, Equatable {
        public let rejectReason: RejectReason?
        public let content: String

        public init(rejectReason: RejectReason?, content: String) {
            self.rejectReason = rejectReason
            self.content = content
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
        }
        if let data = try? fileReader.readData(from: resolved) {
            return LoadedContent(rejectReason: nil, content: data.base64EncodedString())
        }
        return LoadedContent(rejectReason: .unsupportedFormat, content: "")
    }
}
```

`maxTextFileSizeBytes` は `computeLoad` から参照されるため定数として残す。

- [ ] **Step 5: ContentLoaderTests を更新する**

`loadTextFile` テストを削除（テキスト読み込みは NormalizedTextCache テストでカバー）。
`binaryFileIsRejected` テストは ContentLoader のバイナリ判定を
テストしていたが、バイナリ判定は `computeLoad` に移ったため
ViewerStoreTests でカバーされている。削除する。

残す:
- `oversizedFileIsRejected` — バイナリファイルのサイズ上限テスト
- `imageFileIsBase64Encoded` — base64 エンコードテスト

- [ ] **Step 6: テストが全て通ることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: 全テスト pass

- [ ] **Step 7: コミットする**

```bash
cd BefoldApp
git add -A
git commit -m "refactor: LineChunkReader と関連デッドコードを削除する

LineChunkReader.swift を削除し、TextEncoding から
isChunkableEncoding / trimIncompleteTail / trimIncompleteUTF8Tail /
unsupportedForChunking を削除。ContentLoader をバイナリ専用に簡素化。
テストを更新。"
```

---

### Task 5: 検索の修正（TASK-20/24）

**Files:**
- Modify: `BefoldApp/BefoldKit/Resources/viewer.html` — loadAllLinesForSearch 削除、部分検索対応
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift` — loadAllLinesForSearch ハンドラ削除
- Modify: `BefoldApp/BefoldKit/ViewerBridge.swift` — loadAllLinesForSearchMessageName / allLinesLoadedScript 削除

**Interfaces:**
- Consumes: `_mmdIsTruncated`, `_mmdFindRun()` (既存 JS)
- Produces: 切り詰め中は読み込み済み DOM のみ検索し、部分検索であることを表示する

- [ ] **Step 1: viewer.html の `_mmdOpenFind` を修正する**

`_mmdOpenFind()` 関数（viewer.html 内）の truncated 分岐を変更。
全チャンク読み込みの代わりに、読み込み済み DOM をそのまま検索する:

```javascript
// Before (in _mmdOpenFind):
if (_mmdIsTruncated) {
    window.webkit.messageHandlers.loadAllLinesForSearch.postMessage(null);
    _mmdSetFindLoading(true);
    return;
}
_mmdFindRun();

// After:
_mmdFindRun();
```

- [ ] **Step 2: `_mmdFindUpdateCount` に部分検索表示を追加する**

`_mmdFindUpdateCount()` 関数を修正し、`_mmdIsTruncated` が true の場合に
部分検索であることを表示する:

```javascript
// In _mmdFindUpdateCount():
function _mmdFindUpdateCount() {
    var countEl = document.getElementById('mmd-find-count');
    if (!countEl) { return; }
    var total = _mmdFindMatches.length;
    if (total === 0) {
        countEl.textContent = _mmdFindQuery ? '0/0' : '';
    } else {
        countEl.textContent = (_mmdFindCurrentIndex + 1) + '/' + total;
    }
    if (_mmdIsTruncated && _mmdFindQuery) {
        countEl.textContent += ' (' + (_mmdFindStrings.partialSearch || 'partial') + ')';
    }
}
```

- [ ] **Step 3: `_mmdOnAllLinesLoaded` と `_mmdSetFindLoading` を削除する**

viewer.html から以下を削除:
- `_mmdOnAllLinesLoaded()` 関数
- `_mmdSetFindLoading(isLoading)` 関数
- `_mmdSetFindLoading` の呼び出し箇所

- [ ] **Step 4: ViewerBridge から検索全量読み込み関連を削除する**

`BefoldApp/BefoldKit/ViewerBridge.swift` から:
- `loadAllLinesForSearchMessageName` 定数を削除
- `allLinesLoadedScript` 定数を削除

- [ ] **Step 5: ViewerWebView から loadAllLinesForSearch ハンドラを削除する**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の
`userContentController(_:didReceive:)` から
`loadAllLinesForSearchMessageName` の case を削除。

WKUserContentController への `loadAllLinesForSearch` メッセージハンドラ登録も削除。

- [ ] **Step 6: ViewerBridge.findStringsScript にローカライズキーを追加する**

`findStringsScript(bundle:)` で生成される `_mmdFindStrings` に
`partialSearch` キーを追加し、バナーの `loadingAll` キーを削除:

```swift
// In findStringsScript:
// Add: "partialSearch": NSLocalizedString("partial search indicator", ...)
// Remove: "loadingAll" key
```

Localizable.strings に対応する翻訳を追加:
- en: `"partial"` → `"in view"`
- ja: `"partial"` → `"表示範囲内"`

- [ ] **Step 7: ビルドしてテストが通ることを確認する**

Run: `cd BefoldApp && swift build && swift test 2>&1 | tail -10`
Expected: ビルド成功、全テスト pass

- [ ] **Step 8: コミットする**

```bash
cd BefoldApp
git add -A
git commit -m "fix: 検索を表示範囲のみに変更し全量読み込みフリーズを解消する

loadAllLinesForSearch を削除し、切り詰め中はロード済み DOM のみ
検索する。検索件数に部分検索であることを表示する。
TASK-20 と TASK-24 を解消する。"
```
