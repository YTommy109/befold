import BefoldKit
import Foundation
import Testing

@Suite
struct NormalizedTextCacheTests {
    // MARK: - エンコーディング

    @Test("UTF-8 LF テキストをそのまま保持する")
    func utf8LFPreserved() throws {
        let text = "line1\nline2\nline3\n"
        let cache = try NormalizedTextCache(data: Data(text.utf8))
        #expect(cache.text == text)
        #expect(cache.lineCount == 3)
    }

    @Test("BOM 有無を問わず様々なエンコーディングのテキストを正しくデコードする", arguments: [
        (bom: [UInt8]([0xEF, 0xBB, 0xBF]), encoding: String.Encoding.utf8, text: "hello\n", expected: "hello\n"),
        ([0xFF, 0xFE], .utf16LittleEndian, "line1\r\nline2\n", "line1\nline2\n"),
        ([0xFE, 0xFF], .utf16BigEndian, "abc\n", "abc\n"),
        ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian, "test\n", "test\n"),
        ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian, "test\n", "test\n"),
        ([], .shiftJIS, "日本語テスト\n", "日本語テスト\n"), // BOM 無し
        ([], .japaneseEUC, "日本語テスト\n", "日本語テスト\n"), // BOM 無し
    ])
    func bomAndEncodingVariantsDecodeCorrectly(
        bom: [UInt8], encoding: String.Encoding, text: String, expected: String
    ) throws {
        var data = Data(bom)
        try data.append(#require(text.data(using: encoding)))
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == expected)
    }

    // MARK: - 改行正規化

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

    // MARK: - 行インデックス

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

    @Test("日本語マルチバイト文字の行インデックスが正しい")
    func multibyteLinesIndices() throws {
        let cache = try NormalizedTextCache(data: Data("あ\nい\nう".utf8))
        #expect(cache.lineCount == 3)
        let line2Start = cache.lineStartIndices[1]
        let line3Start = cache.lineStartIndices[2]
        #expect(String(cache.text[line2Start ..< line3Start]) == "い\n")
    }

    @Test("1行テキストは lineCount == 1 で先頭インデックスが startIndex")
    func singleLine() throws {
        let cache = try NormalizedTextCache(data: Data("hello".utf8))
        #expect(cache.lineCount == 1)
        #expect(cache.lineStartIndices[0] == cache.text.startIndex)
    }

    // MARK: - 空データ

    @Test("空データは空キャッシュを返す")
    func emptyData() throws {
        let cache = try NormalizedTextCache(data: Data())
        #expect(cache.text == "")
        #expect(cache.lineCount == 0)
    }

    // MARK: - エラー

    @Test("デコード不可能なデータは decodeFailed を投げる")
    func undecodableThrows() {
        let data = Data([0xFF, 0xFE, 0x41])
        #expect(throws: TextEncodingError.decodeFailed) {
            try NormalizedTextCache(data: data)
        }
    }

    @Test("100MB 超のデータは fileTooLarge を投げる")
    func oversizedDataThrows() {
        let data = Data(count: NormalizedTextCache.maxFileSizeBytes + 1)
        #expect(throws: NormalizedTextCacheError.fileTooLarge) {
            try NormalizedTextCache(data: data)
        }
    }

    // MARK: - dataHash

    @Test("同一データは同一ハッシュを返す")
    func sameDataSameHash() throws {
        let data = Data("test\n".utf8)
        let cache1 = try NormalizedTextCache(data: data)
        let cache2 = try NormalizedTextCache(data: data)
        #expect(cache1.dataHash == cache2.dataHash)
    }

    @Test("異なるデータは異なるハッシュを返す")
    func differentDataDifferentHash() throws {
        let cacheAAA = try NormalizedTextCache(data: Data("aaa\n".utf8))
        let cacheBBB = try NormalizedTextCache(data: Data("bbb\n".utf8))
        #expect(cacheAAA.dataHash != cacheBBB.dataHash)
    }

    // MARK: - oneShotLoad

    @Test("oneShotLoad: true では dataHash が nil になる(SHA256計算を省略する)")
    func oneShotLoadSkipsHash() throws {
        let cache = try NormalizedTextCache(data: Data("test\n".utf8), oneShotLoad: true)
        #expect(cache.dataHash == nil)
    }

    @Test("oneShotLoad: false(既定)では従来どおり dataHash が計算される")
    func defaultLoadStillComputesHash() throws {
        let cache = try NormalizedTextCache(data: Data("test\n".utf8))
        #expect(cache.dataHash != nil)
    }

    @Test("oneShotLoad: true でも通常どおりデコード・正規化・行分割される(回帰なし)")
    func oneShotLoadStillDecodesCorrectly() throws {
        let cache = try NormalizedTextCache(data: Data("a\r\nb\rc\n".utf8), oneShotLoad: true)
        #expect(cache.text == "a\nb\nc\n")
        #expect(cache.lineCount == 3)
    }
}
