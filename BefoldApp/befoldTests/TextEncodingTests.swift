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

    @Test("巨大な Shift_JIS データでもエンコーディング判定が高速に完了する(task-31)")
    func detectEncodingStaysFastForLargeLegacyData() throws {
        let line = "これはエンコーディング判定の速度を確認するためのテスト行です。\n"
        let repeated = String(repeating: line, count: 100_000)
        let data = try #require(repeated.data(using: .shiftJIS))
        #expect(data.count > 5_000_000)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = TextEncoding.detectEncoding(data)
        }
        #expect(elapsed < .seconds(3))
    }

    /// sniffLength を超えるASCIIヘッダーに続けて `body` を配置したShift_JISテストデータを組み立てる。
    private func makeShiftJISDataWithAsciiHeader(body: String) throws -> (text: String, data: Data) {
        let asciiHeader = String(repeating: "a", count: TextEncoding.sniffLength + 1000)
        let text = asciiHeader + body
        let data = try #require(text.data(using: .shiftJIS))
        return (text, data)
    }

    @Test("先頭8KB超がASCIIで後半に日本語があるShift_JISファイルを正しくデコードする(task-36)")
    func decodesShiftJISWithAsciiHeaderExceedingSniffLength() throws {
        let (text, data) = try makeShiftJISDataWithAsciiHeader(body: "日本語の本文です。\n")

        let decoded = TextEncoding.decodeText(data)

        #expect(decoded == text)
    }

    @Test("先頭8KBがASCIIで本文にNULを含むShift_JISファイルを正しくデコードする(task-47)")
    func decodesShiftJISWithNulByteAfterAsciiHeader() throws {
        let (text, data) = try makeShiftJISDataWithAsciiHeader(body: "\0" + "日本語の本文です。\n")

        let decoded = TextEncoding.decodeText(data)

        #expect(decoded == text)
    }

    @Test("先頭8KBがASCIIで本文にNULを含むShift_JISファイルでdetectEncodingがUTF-16と誤判定しない(task-47)")
    func detectEncodingDoesNotMisdetectShiftJISWithNulByteAsUtf16() throws {
        let (_, data) = try makeShiftJISDataWithAsciiHeader(body: "\0" + "日本語の本文です。\n")

        let detected = TextEncoding.detectEncoding(data)

        #expect(detected?.encoding != .utf16LittleEndian)
        #expect(detected?.encoding != .utf16BigEndian)
    }

    @Test("2バイト文字がsniffLength境界をまたぐShift_JISファイルを正しくデコードする(task-36)")
    func decodesShiftJISWithMultiByteCharacterCrossingSniffBoundary() throws {
        let line = "日本語のテスト文字列です。"
        var text = ""
        while (text.data(using: .shiftJIS)?.count ?? 0) < TextEncoding.sniffLength - 1 {
            text += line
        }
        // 現在のテキストは sniffLength 境界のすぐ手前で終わっている。
        // ここに全角文字を追加すると、その2バイトが境界をまたぐ。
        text += "日本語続き\n"
        let data = try #require(text.data(using: .shiftJIS))
        #expect(data.count > TextEncoding.sniffLength)

        let decoded = TextEncoding.decodeText(data)

        #expect(decoded == text)
    }

    // MARK: - fallbackScanLimit (TASK-1.11)

    @Test("ASCIIヘッダーが oneShotFallbackScanBytes を超えるレガシーファイルは、通常読込では全量フォールバックで正しくデコードされる")
    func decodesShiftJISWithHeaderExceedingOneShotLimitUsingUnlimitedFallback() throws {
        let asciiHeader = String(repeating: "a", count: TextEncoding.oneShotFallbackScanBytes + 1000)
        let fullText = asciiHeader + "日本語の本文です。\n"
        let data = try #require(fullText.data(using: .shiftJIS))

        // NormalizedTextCache の既定(oneShotLoad: false)は全データを判定窓として
        // 再試行するため、sniffLength や oneShotFallbackScanBytes を超えるヘッダーでも
        // 正しくデコードできる(回帰なし)。
        let cache = try NormalizedTextCache(data: data)
        #expect(cache.text == fullText)
    }

    @Test("ASCIIヘッダーが oneShotFallbackScanBytes を超えるレガシーファイルは、静的1回読込ではフォールバック判定窓が制限されデコードに失敗する")
    func oneShotLoadLimitsFallbackScanWindow() throws {
        let asciiHeader = String(repeating: "a", count: TextEncoding.oneShotFallbackScanBytes + 1000)
        let fullText = asciiHeader + "日本語の本文です。\n"
        let data = try #require(fullText.data(using: .shiftJIS))

        // oneShotLoad: true では2回目の判定窓が oneShotFallbackScanBytes に制限されるため、
        // 本文(日本語)がその範囲外にあるこのケースでは正しいエンコーディングを判定できず、
        // デコードに失敗する。全データを読まずに判定窓を打ち切っていることの直接的な証跡。
        #expect(throws: TextEncodingError.decodeFailed) {
            try NormalizedTextCache(data: data, oneShotLoad: true)
        }
    }
}
