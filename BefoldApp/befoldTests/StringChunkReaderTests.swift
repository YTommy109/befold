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
        var lines = (0 ..< 998).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == true)
        #expect(result.text.contains("\"quoted\nfield\""))
    }

    @Test("CSV 引用符なしモードでは全改行がチャンク境界になる")
    func withoutCSVQuotes() async throws {
        var lines = (0 ..< 999).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: false)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == false)
    }

    @Test("読了後の再呼び出しは空チャンクを返す")
    func readAfterEnd() async throws {
        let cache = try makeCache("abc\n")
        let reader = StringChunkReader(cache: cache)
        let first = await reader.readNextChunk()
        #expect(first.isAtEnd == true)
        let second = await reader.readNextChunk()
        #expect(second.text == "")
        #expect(second.isAtEnd == true)
    }

    @Test("末尾改行なしテキストのチャンク分割が正しい")
    func noTrailingNewline() async throws {
        let text = makeLines(1000) + "lastline"
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 2)
        #expect(chunks.joined() == text)
    }

    @Test("不平衡クォートを含む巨大CSVでもチャンクサイズが上限内に収まる")
    func unbalancedQuoteLargeCSVIsChunked() async throws {
        let hugeAfterUnbalancedQuote = String(repeating: "a,b,c\n", count: 300_000)
        let text = "\"unbalanced\n" + hugeAfterUnbalancedQuote
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        #expect(chunks.joined() == text)
    }

    @Test("改行なしの巨大1行ファイルでもチャンクサイズが上限内に収まる")
    func noNewlineHugeSingleLineIsChunked() async throws {
        let text = String(repeating: "A", count: StringChunkReader.maxChunkBytes + 500_000)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        #expect(chunks.joined() == text)
    }

    @Test("対のない引用符は規定長を超えると不均衡とみなされ通常の行ベース分割に復帰する")
    func unbalancedQuoteGivesUpAfterGuaranteedLengthAndRecovers() async throws {
        // 先頭の対のない `"` により一時的にクォート内と判定されるが、閉じずに
        // 規定長(500バイト)を超えたら不均衡クォートとみなして inQuotes を
        // 強制的に閉じ、以降は通常の 1000 行ベースのチャンクに復帰するはずである。
        // リセットせず永久にクォート内とみなしてしまうと、ファイル全体が
        // 巨大な1チャンク(または少数のバイト上限チャンク)のまま行数が把握できなくなる。
        let plainRows = String(repeating: "a,b,c\n", count: 5000)
        let text = "\"" + plainRows
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        // 復帰していれば 5000 行 / 1000 行 = 5 チャンク程度に分かれる。
        // 復帰しなければ強制分割前提の巨大チャンク(1〜2個)にしかならない。
        #expect(chunks.count >= 4)
    }

    @Test("改行なしテキストの長さがちょうど maxChunkBytes のとき境界外アクセスせずに読み切れる")
    func exactMaxChunkBytesNoTrailingNewlineDoesNotCrash() async throws {
        let text = String(repeating: "A", count: StringChunkReader.maxChunkBytes)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 1)
        #expect(chunks.joined() == text)
    }

    @Test("1MB超の単一行日本語テキストの強制分割がマルチバイト文字境界を尊重する")
    func forcedSplitRespectsMultibyteCharacterBoundary() async throws {
        let text = String(repeating: "あ", count: StringChunkReader.maxChunkBytes)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        // 分割位置が文字境界からずれていれば、結合結果が元テキストと一致しない、
        // または不正な UTF-8 途中断片から構築された文字列が混入して文字数が変化する。
        #expect(chunks.joined() == text)
        // 各分割点が文字境界を尊重していれば、3 バイト文字「あ」のみの列である以上
        // 各チャンクのバイト数は常に 3 の倍数になる。
        #expect(chunks.allSatisfy { $0.utf8.count % 3 == 0 })
    }
}
