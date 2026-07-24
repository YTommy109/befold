@testable import BefoldKit
import Foundation
import Testing

/// NormalizedTextCache(data:normalizeFully:false) の増分正規化(ensureNormalized)を検証する。
/// task-1.8: 先頭チャンク描画に必要な範囲だけをデコード/正規化/インデックス化し、
/// ファイル全体を materialize しない読込経路があることを確認する。
@Suite
struct NormalizedTextCacheLazyGrowthTests {
    private func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line\($0)\n" }.joined()
    }

    @Test("normalizeFully: false は初期化時点でファイル全体を正規化しない")
    func lazyInitDoesNotFullyNormalize() throws {
        // normalizationWindowBytes(2MiB) を大きく超えるサイズにする。
        let text = makeLines(400_000)
        #expect(text.utf8.count > 2 * 1024 * 1024)

        let cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)
        #expect(cache.isFullyNormalized == false)
        #expect(cache.lineCount < 400_000)
        #expect(cache.normalizedByteCount < text.utf8.count)
    }

    @Test("QuickLook 相当(先頭チャンク1回だけ読む)では、正規化済み範囲が元ファイルサイズよりずっと小さいまま留まる")
    func singleChunkReadKeepsNormalizedRangeMuchSmallerThanFileSize() async throws {
        // QuickLook はファイル全体を読み切らず先頭チャンクしか使わない。
        // normalizationWindowBytes(2MiB)を十分超えていれば増分正規化の経路に入るため、
        // フィクスチャはその条件を満たす最小限のサイズでよい。
        let text = makeLines(400_000)
        let fileSize = text.utf8.count
        #expect(fileSize > 4 * 1024 * 1024)

        let cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)
        let reader = StringChunkReader(cache: cache)
        let first = await reader.readNextChunk()

        #expect(first.isAtEnd == false)
        // 先頭チャンクのサイズは linesPerChunk 行分で決まり、元ファイルサイズに
        // 比例しない(実測 ≈ 7.9KB)。fileSize との相対比較にすると、フィクスチャを
        // 大きくするほど条件が緩くなって検証の意味が薄れるため、絶対値で押さえる。
        #expect(first.text.utf8.count < 64 * 1024)
    }

    @Test("ensureNormalized は要求された行数に達するかファイル全体正規化のどちらか早い方で停止する")
    func ensureNormalizedStopsAtEarlierTarget() throws {
        let text = makeLines(400_000)
        var cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)

        cache.ensureNormalized(minimumLineCount: 1500, minimumByteCount: .max)
        #expect(cache.lineCount >= 1500)
        #expect(cache.isFullyNormalized == false)
        #expect(cache.lineCount < 400_000)
    }

    @Test("ensureNormalized はバイト数の下限に達するかファイル全体正規化のどちらか早い方で停止する")
    func ensureNormalizedStopsAtByteTarget() throws {
        let text = String(repeating: "A", count: StringChunkReader.maxChunkBytes * 5)
        var cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)

        cache.ensureNormalized(minimumLineCount: .max, minimumByteCount: StringChunkReader.maxChunkBytes)
        #expect(cache.normalizedByteCount >= StringChunkReader.maxChunkBytes)
        #expect(cache.isFullyNormalized == false)
    }

    @Test("段階的に ensureFullyNormalized まで進めると eager 正規化と一致する(改行混在)")
    func incrementalGrowthMatchesEagerResultForMixedLineEndings() throws {
        var text = ""
        for rowIndex in 0 ..< 5000 {
            switch rowIndex % 3 {
            case 0: text += "row\(rowIndex)\r\n"
            case 1: text += "row\(rowIndex)\r"
            default: text += "row\(rowIndex)\n"
            }
        }
        text += String(repeating: "あ", count: 10000)

        let data = Data(text.utf8)
        let eager = try NormalizedTextCache(data: data, normalizeFully: true)

        var lazy = try NormalizedTextCache(data: data, normalizeFully: false)
        lazy.ensureFullyNormalized()

        #expect(lazy.isFullyNormalized == true)
        #expect(lazy.text == eager.text)
        #expect(lazy.lineCount == eager.lineCount)
        #expect(lazy.lineStartIndices == eager.lineStartIndices)
    }

    @Test("段階的に ensureFullyNormalized まで進めると eager 正規化と一致する(改行なし巨大1行)")
    func incrementalGrowthMatchesEagerResultForHugeSingleLine() throws {
        let text = String(repeating: "x", count: StringChunkReader.maxChunkBytes * 3 + 12345)
        let data = Data(text.utf8)

        let eager = try NormalizedTextCache(data: data, normalizeFully: true)

        var lazy = try NormalizedTextCache(data: data, normalizeFully: false)
        lazy.ensureFullyNormalized()

        #expect(lazy.text == eager.text)
        #expect(lazy.lineCount == eager.lineCount)
    }

    @Test("段階的な readNextChunk 相当のアクセスでも、増分正規化した内容が eager 版と一致する")
    func chunkedIncrementalReadMatchesEagerAcrossManyGrowthCalls() async throws {
        let text = makeLines(50000)
        let data = Data(text.utf8)

        let eager = try NormalizedTextCache(data: data, normalizeFully: true)

        let lazyCache = try NormalizedTextCache(data: data, normalizeFully: false)
        let reader = StringChunkReader(cache: lazyCache)
        var chunks: [String] = []
        while true {
            let result = await reader.readNextChunk()
            if !result.text.isEmpty { chunks.append(result.text) }
            if result.isAtEnd { break }
        }

        #expect(chunks.joined() == eager.text)
    }
}
