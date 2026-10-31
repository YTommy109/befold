@testable import BefoldKit
import Foundation
import Testing

/// NormalizedTextCache(data:normalizeFully:false) の増分正規化(ensureNormalized)を検証する。
/// 先頭チャンク描画に必要な範囲だけをデコード/正規化/インデックス化し、
/// ファイル全体を materialize しない読込経路があることを確認する。
@Suite
struct NormalizedTextCacheLazyGrowthTests {
    private static func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line\($0)\n" }.joined()
    }

    /// 増分正規化の経路に入る条件は「normalizationWindowBytes(2MiB)を超えること」だけなので、
    /// 行数はその条件を満たすことが一目で分かる値(約 4.5MB = 閾値の約 2 倍)に固定する。
    /// Swift Testing はテストごとに Suite を再生成するため、テスト関数から直接生成すると
    /// 同じ文字列を毎回組み立てることになる。内容は不変なので static let で 1 回だけ生成し共有する。
    private static let largeText = makeLines(largeTextLineCount)
    private static let largeTextLineCount = 400_000

    @Test("normalizeFully: false は初期化時点でファイル全体を正規化しない")
    func lazyInitDoesNotFullyNormalize() throws {
        let text = Self.largeText
        #expect(text.utf8.count > 2 * 1024 * 1024)

        let cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)
        #expect(cache.isFullyNormalized == false)
        #expect(cache.lineCount < Self.largeTextLineCount)
        #expect(cache.normalizedByteCount < text.utf8.count)
    }

    @Test("QuickLook 相当(先頭チャンク1回だけ読む)では、正規化済み範囲が元ファイルサイズよりずっと小さいまま留まる")
    func singleChunkReadKeepsNormalizedRangeMuchSmallerThanFileSize() async throws {
        // QuickLook はファイル全体を読み切らず先頭チャンクしか使わない。
        // normalizationWindowBytes(2MiB)を十分超えていれば増分正規化の経路に入るため、
        // フィクスチャはその条件を満たしていればよい。
        let text = Self.largeText
        #expect(text.utf8.count > 2 * 1024 * 1024)

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
        let text = Self.largeText
        var cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)

        cache.ensureNormalized(minimumLineCount: 1500, minimumByteCount: .max)
        #expect(cache.lineCount >= 1500)
        #expect(cache.isFullyNormalized == false)
        #expect(cache.lineCount < Self.largeTextLineCount)
    }

    @Test("ensureNormalized はバイト数の下限に達するかファイル全体正規化のどちらか早い方で停止する")
    func ensureNormalizedStopsAtByteTarget() throws {
        // minimumByteCount = maxChunkBytes まで進めた時点で「まだ全体正規化されていない」ことを
        // 検証するので、フィクスチャは maxChunkBytes より確実に大きければよい(倍率は余裕分)。
        let text = String(repeating: "A", count: StringChunkReader.defaultMaxChunkBytes * 5)
        var cache = try NormalizedTextCache(data: Data(text.utf8), normalizeFully: false)

        cache.ensureNormalized(minimumLineCount: .max, minimumByteCount: StringChunkReader.defaultMaxChunkBytes)
        #expect(cache.normalizedByteCount >= StringChunkReader.defaultMaxChunkBytes)
        #expect(cache.isFullyNormalized == false)
    }

    /// 1 窓目は CR で終わり、2 窓目の上限は「あ」の途中に当たる。
    /// 4 窓以上に成長させ、CRLF 吸収・UTF-8 境界補正・末尾改行処理をまとめて通す。
    private static let boundaryText: String = {
        let window = NormalizedTextCache.normalizationWindowBytes
        return String(repeating: "a", count: window - 1) + "\r\n"
            + String(repeating: "b", count: window - 2) + "あ\r"
            + String(repeating: "🙂\r\n", count: window / 3) + "終わり\r\n"
    }()

    @Test("複数窓の増分正規化で CRLF・UTF-8 境界と全行オフセットを保つ")
    func incrementalGrowthPreservesWindowBoundaries() throws {
        let source = Self.boundaryText
        let expected = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cache = try NormalizedTextCache(data: Data(source.utf8), normalizeFully: false)
        #expect(cache.normalizedByteCount == 0)
        var growthCount = 0
        while !cache.isFullyNormalized {
            let previousCount = cache.normalizedByteCount
            cache.ensureNormalized(minimumLineCount: .max, minimumByteCount: previousCount + 1)
            #expect(cache.normalizedByteCount > previousCount)
            #expect(cache.normalizedByteCount - previousCount <= NormalizedTextCache.normalizationWindowBytes)
            if growthCount == 0 {
                #expect(!cache.isFullyNormalized)
                #expect(cache.normalizedByteCount == NormalizedTextCache.normalizationWindowBytes)
            }
            growthCount += 1
        }
        #expect(growthCount >= 4)
        #expect(cache.text == expected)
        let bytes = Array(expected.utf8)
        let offsets = [0] + bytes.indices.filter { bytes[$0] == 0x0A && $0 + 1 < bytes.count }.map { $0 + 1 }
        #expect(cache.lineCount == offsets.count)
        #expect((0 ..< cache.lineCount).map { cache.lineStart($0) } == offsets)
        let indices = cache.lineStartIndices
        #expect(indices == offsets.map { expected.utf8.index(expected.utf8.startIndex, offsetBy: $0) })
    }

    @Test("段階的に ensureFullyNormalized まで進めると eager 正規化と一致する(改行なし巨大1行)")
    func incrementalGrowthMatchesEagerResultForHugeSingleLine() throws {
        // 改行が 1 つも無い入力で、チャンク境界を複数回またいでも eager と一致することを見る。
        // 端数(12345)は境界がちょうど揃った場合だけ通る実装を弾くために付けている。
        let text = String(repeating: "x", count: StringChunkReader.defaultMaxChunkBytes * 3 + 12345)
        let data = Data(text.utf8)

        let eager = try NormalizedTextCache(data: data, normalizeFully: true)

        var lazy = try NormalizedTextCache(data: data, normalizeFully: false)
        lazy.ensureFullyNormalized()

        #expect(lazy.text == eager.text)
        #expect(lazy.lineCount == eager.lineCount)
    }

    @Test("段階的な readNextChunk 相当のアクセスでも、増分正規化した内容が eager 版と一致する")
    func chunkedIncrementalReadMatchesEagerAcrossManyGrowthCalls() async throws {
        let text = Self.boundaryText
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

        #expect(chunks.count > 3)
        #expect(chunks.joined() == eager.text)
    }
}
