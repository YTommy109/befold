import BefoldKit
import Foundation
import Testing

@Suite
struct TextEncodingTests {
    @Test("UTF-8 BOM を検出する")
    func detectsUtf8Bom() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf8)
        #expect(bom?.bomLength == 3)
    }

    @Test("UTF-16 LE BOM を検出する")
    func detectsUtf16LeBom() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf16LittleEndian)
        #expect(bom?.bomLength == 2)
    }

    @Test("UTF-16 BE BOM を検出する")
    func detectsUtf16BeBom() {
        let data = Data([0xFE, 0xFF, 0x00, 0x41])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf16BigEndian)
        #expect(bom?.bomLength == 2)
    }

    @Test("UTF-32 LE BOM を検出する")
    func detectsUtf32LeBom() {
        let data = Data([0xFF, 0xFE, 0x00, 0x00])
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == .utf32LittleEndian)
        #expect(bom?.bomLength == 4)
    }

    @Test("BOM がなければ nil を返す")
    func noBomReturnsNil() {
        let data = Data("hello".utf8)
        #expect(TextEncoding.detectBOM(data) == nil)
    }

    @Test("UTF-16 はチャンク読み込み不可")
    func utf16IsNotChunkable() {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        #expect(!TextEncoding.isChunkableEncoding(data))
    }

    @Test("UTF-8 BOM はチャンク読み込み可能")
    func utf8BomIsChunkable() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        #expect(TextEncoding.isChunkableEncoding(data))
    }

    @Test("BOM なし UTF-8 はチャンク読み込み可能")
    func plainUtf8IsChunkable() {
        let data = Data("hello\nworld".utf8)
        #expect(TextEncoding.isChunkableEncoding(data))
    }

    @Test("NUL を含むデータはチャンク読み込み不可")
    func nulContainingDataIsNotChunkable() {
        let data = Data("hello".utf8) + Data([0x00]) + Data("world".utf8)
        #expect(!TextEncoding.isChunkableEncoding(data))
    }
}

@Suite(.serialized)
struct LineChunkReaderTests {
    private func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line \($0)" }.joined(separator: "\n") + "\n"
    }

    private func readAll(_ reader: LineChunkReader) throws -> (chunks: [String], joined: String) {
        var chunks: [String] = []
        while !reader.isAtEnd {
            let chunk = try reader.readNextChunk()
            chunks.append(chunk)
        }
        return (chunks, chunks.joined())
    }

    @Test("500 行のファイルは 1 チャンクで完了する")
    func smallFileCompletesInOneChunk() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(500)
        let file = try tmp.file(named: "small.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try readAll(reader)
        #expect(chunks.count == 1)
        #expect(joined == text)
        #expect(reader.isAtEnd)
    }

    @Test("2500 行のファイルは 3 チャンクに分割され原文を再構成する")
    func largeFileSplitsIntoChunks() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(2500)
        let file = try tmp.file(named: "large.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try readAll(reader)
        #expect(chunks.count == 3)
        #expect(joined == text)
    }

    @Test("UTF-8 BOM ファイルを正しく読める")
    func utf8BomFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "こんにちは\n世界"
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        let file = try tmp.file(named: "bom.txt", data: data)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try readAll(reader)
        #expect(joined == text)
    }

    @Test("UTF-16 ファイルは unsupportedForChunking を投げる")
    func utf16BomThrows() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let data = try #require("hello\nworld".data(using: .utf16LittleEndian))
        let file = try tmp.file(named: "u16.txt", data: data)

        #expect(throws: TextEncodingError.unsupportedForChunking) {
            _ = try LineChunkReader(url: file)
        }
    }

    @Test("Shift_JIS(CP932)ファイルを正しく読める")
    func cp932File() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "表示\n価格"
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        )
        let encoding = String.Encoding(rawValue: cfEncoding)
        let data = try #require(text.data(using: encoding))
        let file = try tmp.file(named: "sjis.txt", data: data)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try readAll(reader)
        #expect(joined == text)
    }

    @Test("maxChunkBytes を超える改行なし単一行は強制分割される")
    func noNewlineForceSplitAtMaxBytes() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = String(repeating: "A", count: LineChunkReader.maxChunkBytes + 1000)
        let file = try tmp.file(named: "oneline.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try readAll(reader)
        #expect(chunks.count >= 2)
        #expect(joined == text)
    }

    @Test("UTF-8 マルチバイト境界で有効な UTF-8 チャンクに分割する")
    func utf8MultibyteBoundary() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // maxChunkBytes 直前にマルチバイト文字が跨る位置を作る。
        let padCount = LineChunkReader.maxChunkBytes - 2
        let text = String(repeating: "A", count: padCount) + "あいう"
        let file = try tmp.file(named: "multibyte.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try readAll(reader)
        #expect(joined == text)
    }

    @Test("空ファイルは空文字列と isAtEnd を返す")
    func emptyFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "empty.txt", contents: "")

        let reader = try LineChunkReader(url: file)
        #expect(reader.isAtEnd)
        #expect(try reader.readNextChunk() == "")
    }

    @Test("ちょうど 1000 行のファイルは isAtEnd になる")
    func exactly1000LinesIsAtEnd() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(1000)
        let file = try tmp.file(named: "thousand.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try readAll(reader)
        #expect(joined == text)
        #expect(reader.isAtEnd)
        #expect(chunks.allSatisfy { !$0.isEmpty })
    }

    @Test("3333 行の全チャンクを結合すると原文と一致する")
    func chunksReconstructOriginal() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(3333)
        let file = try tmp.file(named: "many.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try readAll(reader)
        #expect(joined == text)
    }
}
