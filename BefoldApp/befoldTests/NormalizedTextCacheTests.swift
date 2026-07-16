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
        let encoded = try #require("line1\r\nline2\n".data(using: .utf16LittleEndian))
        data.append(encoded)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "line1\nline2\n")
    }

    @Test("UTF-16 BE BOM 付きテキストをデコードする")
    func utf16BEBom() throws {
        var data = Data([0xFE, 0xFF])
        let encoded = try #require("abc\n".data(using: .utf16BigEndian))
        data.append(encoded)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "abc\n")
    }

    @Test("UTF-32 LE BOM 付きテキストをデコードする")
    func utf32LEBom() throws {
        var data = Data([0xFF, 0xFE, 0x00, 0x00])
        let encoded = try #require("test\n".data(using: .utf32LittleEndian))
        data.append(encoded)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "test\n")
    }

    @Test("UTF-32 BE BOM 付きテキストをデコードする")
    func utf32BEBom() throws {
        var data = Data([0x00, 0x00, 0xFE, 0xFF])
        let encoded = try #require("test\n".data(using: .utf32BigEndian))
        data.append(encoded)
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == "test\n")
    }

    @Test("Shift_JIS テキストをデコードする")
    func shiftJIS() throws {
        let text = "日本語テスト\n"
        let data = try #require(text.data(using: .shiftJIS))
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == text)
    }

    @Test("EUC-JP テキストをデコードする")
    func eucJP() throws {
        let text = "日本語テスト\n"
        let data = try #require(text.data(using: .japaneseEUC))
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == text)
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
}
