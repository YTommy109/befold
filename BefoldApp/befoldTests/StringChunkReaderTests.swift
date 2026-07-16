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
}
