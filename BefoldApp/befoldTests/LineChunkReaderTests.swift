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

    @Test("trimIncompleteUTF8Tail は途中で切れたマルチバイト文字を切り詰める")
    func trimIncompleteUTF8TailRemovesPartialCharacter() {
        let full = Data("abcあ".utf8) // 「あ」は 3 バイト
        // 「あ」の 1〜2 バイト目までで切れたデータは "abc" まで戻る
        #expect(TextEncoding.trimIncompleteUTF8Tail(full.prefix(4)) == Data("abc".utf8))
        #expect(TextEncoding.trimIncompleteUTF8Tail(full.prefix(5)) == Data("abc".utf8))
        // 末尾のマルチバイト文字は完結していても保守的に切り詰める
        // (切り落とした分は呼び出し側が remainder / 判定対象外として扱うため無害)
        #expect(TextEncoding.trimIncompleteUTF8Tail(full) == Data("abc".utf8))
        // ASCII で終わっていればそのまま
        #expect(TextEncoding.trimIncompleteUTF8Tail(Data("abc".utf8)) == Data("abc".utf8))
    }
}

@Suite(.serialized)
struct LineChunkReaderTests {
    private func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line \($0)" }.joined(separator: "\n") + "\n"
    }

    /// 末尾(isAtEnd)に達するまで readNextChunk を繰り返し、チャンク列と結合結果を返す。
    private func readAll(_ reader: LineChunkReader) async throws -> (chunks: [String], joined: String) {
        var chunks: [String] = []
        while true {
            let (text, isAtEnd) = try await reader.readNextChunk()
            if !text.isEmpty {
                chunks.append(text)
            }
            if isAtEnd {
                return (chunks, chunks.joined())
            }
        }
    }

    @Test("500 行のファイルは 1 チャンクで完了する")
    func smallFileCompletesInOneChunk() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(500)
        let file = try tmp.file(named: "small.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try await readAll(reader)
        #expect(chunks.count == 1)
        #expect(joined == text)
    }

    @Test("2500 行のファイルは 3 チャンクに分割され原文を再構成する")
    func largeFileSplitsIntoChunks() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(2500)
        let file = try tmp.file(named: "large.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try await readAll(reader)
        #expect(chunks.count == 3)
        #expect(joined == text)
    }

    @Test("UTF-8 BOM ファイルを正しく読める")
    func utf8BomFile() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "こんにちは\n世界"
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        let file = try tmp.file(named: "bom.txt", data: data)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try await readAll(reader)
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

    @Test("Shift_JIS ファイルをチャンク読みできる")
    func shiftJISChunkReading() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "表示\n価格\n"
        let data = try #require(text.data(using: .shiftJIS))
        let file = try tmp.file(named: "sjis.txt", data: data)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try await readAll(reader)
        #expect(joined == text)
    }

    @Test("先頭 8192 バイト目がマルチバイト文字を跨いでも UTF-8 と判定して読める")
    func probeBoundaryInsideMultibyteCharStillDetectsUTF8() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // 8191 バイトの ASCII の直後に 3 バイト文字「あ」を置くと、
        // 8192 バイトのプローブが「あ」の 1 バイト目で切れる。
        let text = String(repeating: "A", count: 8191) + "あ日本語のテキスト\n続きの行\n"
        let file = try tmp.file(named: "boundary.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try await readAll(reader)
        #expect(joined == text)
    }

    @Test("maxChunkBytes を超える改行なし単一行は強制分割される")
    func noNewlineForceSplitAtMaxBytes() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = String(repeating: "A", count: LineChunkReader.maxChunkBytes + 1000)
        let file = try tmp.file(named: "oneline.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try await readAll(reader)
        #expect(chunks.count >= 2)
        #expect(joined == text)
    }

    @Test("UTF-8 マルチバイト境界で有効な UTF-8 チャンクに分割する")
    func utf8MultibyteBoundary() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // maxChunkBytes 直前にマルチバイト文字が跨る位置を作る。
        let padCount = LineChunkReader.maxChunkBytes - 2
        let text = String(repeating: "A", count: padCount) + "あいう"
        let file = try tmp.file(named: "multibyte.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try await readAll(reader)
        #expect(joined == text)
    }

    @Test("空ファイルは空文字列と isAtEnd を返す")
    func emptyFile() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "empty.txt", contents: "")

        let reader = try LineChunkReader(url: file)
        let result = try await reader.readNextChunk()
        #expect(result.text == "")
        #expect(result.isAtEnd)
    }

    @Test("ちょうど 1000 行のファイルは 1 チャンクで isAtEnd になる")
    func exactly1000LinesIsAtEnd() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(1000)
        let file = try tmp.file(named: "thousand.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try await readAll(reader)
        #expect(joined == text)
        // 末尾の空チャンクを追加で読まされることなく、1 回で isAtEnd に達する。
        #expect(chunks.count == 1)
    }

    @Test("respectsCSVQuotes は引用フィールド内の改行をチャンク境界にしない")
    func csvQuotedNewlineIsNotAChunkBoundary() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // 999 行の通常行の後、1000 個目の改行が引用フィールド内に来るようにする。
        let normalLines = (0 ..< 999).map { "id\($0),value\($0)" }.joined(separator: "\n") + "\n"
        let quotedLine = "a,\"x\ny\",b\n"
        let text = normalLines + quotedLine + "c,d\ne,f\n"
        let file = try tmp.file(named: "quoted.csv", contents: text)

        let reader = try LineChunkReader(url: file, respectsCSVQuotes: true)
        let (chunks, joined) = try await readAll(reader)
        // チャンク境界は引用フィールドを跨がず、引用行末尾の(引用符外の)改行まで進む。
        #expect(chunks.count == 2)
        #expect(chunks[0].hasSuffix(quotedLine))
        #expect(joined == text)
    }

    @Test("respectsCSVQuotes なしでは引用フィールド内の改行もチャンク境界になる")
    func withoutCSVQuotesQuotedNewlineIsABoundary() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let normalLines = (0 ..< 999).map { "id\($0),value\($0)" }.joined(separator: "\n") + "\n"
        let text = normalLines + "a,\"x\ny\",b\n"
        let file = try tmp.file(named: "naive.csv", contents: text)

        let reader = try LineChunkReader(url: file)
        let (chunks, joined) = try await readAll(reader)
        #expect(chunks.count == 2)
        #expect(chunks[0].hasSuffix("a,\"x\n"))
        #expect(joined == text)
    }

    @Test("3333 行の全チャンクを結合すると原文と一致する")
    func chunksReconstructOriginal() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = makeLines(3333)
        let file = try tmp.file(named: "many.txt", contents: text)

        let reader = try LineChunkReader(url: file)
        let (_, joined) = try await readAll(reader)
        #expect(joined == text)
    }
}
