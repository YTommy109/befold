import BefoldKit
import Foundation
import Testing

/// markdown をチャンク読み込みに載せるためのブロック境界判定(Issue #307)。
///
/// markdown は段落やコードフェンスの途中で切ると、分割後の各チャンクを
/// markdown-it が別のブロックとして解釈してしまう(段落が 2 つに割れる、
/// コードフェンスが閉じずに以降がすべてコード扱いになる)。
/// そのため空行(かつコードフェンス外)でのみチャンクを終える。
@Suite
struct StringChunkReaderMarkdownTests {
    private func makeCache(_ text: String) throws -> NormalizedTextCache {
        try NormalizedTextCache(data: Data(text.utf8))
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

    /// 段落 1 つ(本文 + 空行)を繰り返してチャンク上限を跨がせる。
    private func paragraphs(_ count: Int, prefix: String = "para") -> String {
        (0 ..< count).map { "\(prefix) \($0)\n\n" }.joined()
    }

    private func fenceCount(in chunk: String, marker: String) -> Int {
        chunk.split(separator: "\n", omittingEmptySubsequences: false)
            .count { $0.hasPrefix(marker) }
    }

    @Test("markdown チャンクはコードフェンスの内側で終わらない")
    func markdownChunkDoesNotEndInsideFence() async throws {
        // チャンク上限に達した直後がフェンスの内側になるよう、手前を埋めてから開く。
        var text = paragraphs(StringChunkReader.linesPerChunk - 1)
        text += "```swift\n"
        text += paragraphs(50, prefix: "let value =")
        text += "```\n\nafter fence\n"

        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, boundary: .markdownBlocks)
        let chunks = await readAll(reader)

        #expect(chunks.joined() == text)
        // フェンス内で終わっていなければ、各チャンクの開閉数は必ず偶数になる。
        for chunk in chunks {
            #expect(fenceCount(in: chunk, marker: "```") % 2 == 0)
        }
    }

    @Test("markdown チャンクは空行で終わる")
    func markdownChunkEndsAtBlankLine() async throws {
        let text = paragraphs(StringChunkReader.linesPerChunk * 2)

        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, boundary: .markdownBlocks)
        let chunks = await readAll(reader)

        #expect(chunks.count >= 2)
        #expect(chunks.joined() == text)
        // 最終チャンク以外は空行で終わっている(= 段落の途中で切れていない)。
        for chunk in chunks.dropLast() {
            #expect(chunk.hasSuffix("\n\n"))
        }
    }

    @Test("markdown チャンクは ~~~ のコードフェンスも尊重する")
    func markdownChunkRespectsTildeFence() async throws {
        var text = paragraphs(StringChunkReader.linesPerChunk - 1)
        text += "~~~\n"
        text += paragraphs(50, prefix: "raw")
        text += "~~~\n\nafter\n"

        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, boundary: .markdownBlocks)
        let chunks = await readAll(reader)

        #expect(chunks.joined() == text)
        for chunk in chunks {
            #expect(fenceCount(in: chunk, marker: "~~~") % 2 == 0)
        }
    }

    /// 空行を探して際限なくチャンクが伸びないこと。バイト上限による強制分割は
    /// 境界判定より優先される(巨大な 1 行や空行の無い文書での保険)。
    @Test("空行の無い markdown でもバイト上限で強制分割される")
    func markdownStillForceSplitsWithoutBlankLines() async throws {
        let text = String(repeating: "a", count: StringChunkReader.maxChunkBytes * 2)

        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, boundary: .markdownBlocks)
        let chunks = await readAll(reader)

        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        #expect(chunks.joined() == text)
    }

    /// 既定の境界(.lines)は従来どおり行数だけで切る。markdown 対応を入れても
    /// コード/CSV 経路の分割位置が変わっていないことを固定する。
    @Test("boundary を指定しなければ従来どおり行数で分割される")
    func defaultBoundaryKeepsLineSplitting() async throws {
        let text = (0 ..< (StringChunkReader.linesPerChunk + 10))
            .map { "line\($0)\n" }.joined()

        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)

        #expect(chunks.count == 2)
        #expect(chunks[0].split(separator: "\n").count == StringChunkReader.linesPerChunk)
    }
}
