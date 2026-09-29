import BefoldKit
import Foundation
import Testing

@Suite
struct TextEncodingTests {
    @Test("BOM を検出しエンコーディングとバイト長を返す", arguments: [
        (data: Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8), encoding: String.Encoding.utf8, bomLength: 3),
        (Data([0xFF, 0xFE, 0x41, 0x00]), .utf16LittleEndian, 2),
        (Data([0xFE, 0xFF, 0x00, 0x41]), .utf16BigEndian, 2),
        (Data([0xFF, 0xFE, 0x00, 0x00]), .utf32LittleEndian, 4),
    ])
    func detectsBom(data: Data, encoding: String.Encoding, bomLength: Int) {
        let bom = TextEncoding.detectBOM(data)
        #expect(bom?.encoding == encoding)
        #expect(bom?.bomLength == bomLength)
    }

    @Test("BOM がなければ nil を返す")
    func noBomReturnsNil() {
        let data = Data("hello".utf8)
        #expect(TextEncoding.detectBOM(data) == nil)
    }

    /// detectEncoding のレガシー判定は先頭 sniffLength バイトしか見ない(巨大ファイルでも
    /// 判定の所要時間がデータ量に比例しないのはこのため)。所要時間の比で測ると 9MB の
    /// 入力と繰り返し計測が要るので、振る舞いで測る: 判定窓の後ろに Shift_JIS として
    /// 不正なバイトを置いても、判定結果は窓の中身だけで決まる。全体を見る実装へ戻ると、
    /// 後ろの不正バイトのせいで Shift_JIS と判定できなくなる。
    @Test("レガシーエンコーディングの判定は先頭 sniffLength バイトだけで決まる")
    func legacyDetectionLooksOnlyAtSniffWindow() throws {
        let line = "これはエンコーディング判定の窓を確認するためのテスト行です。\n"
        let head = try #require(String(repeating: line, count: 200).data(using: .shiftJIS))
        #expect(head.count > TextEncoding.sniffLength)
        // 0xFF は Shift_JIS のどの位置にも現れない。UTF-8 としても不正。
        let tail = Data(repeating: 0xFF, count: 1024)

        #expect(TextEncoding.detectEncoding(head)?.encoding == .shiftJIS)
        #expect(TextEncoding.detectEncoding(head + tail)?.encoding == .shiftJIS)
    }

    /// sniffLength を超えるASCIIヘッダーに続けて `body` を配置したShift_JISテストデータを組み立てる。
    private func makeShiftJISDataWithAsciiHeader(body: String) throws -> (text: String, data: Data) {
        let asciiHeader = String(repeating: "a", count: TextEncoding.sniffLength + 1000)
        let text = asciiHeader + body
        let data = try #require(text.data(using: .shiftJIS))
        return (text, data)
    }

    @Test("先頭8KB超がASCIIで後半に日本語があるShift_JISファイルを正しくデコードする")
    func decodesShiftJISWithAsciiHeaderExceedingSniffLength() throws {
        let (text, data) = try makeShiftJISDataWithAsciiHeader(body: "日本語の本文です。\n")

        let decoded = TextEncoding.decodeText(data)

        #expect(decoded == text)
    }

    @Test("先頭8KBがASCIIで本文にNULを含むShift_JISファイルを正しくデコードする")
    func decodesShiftJISWithNulByteAfterAsciiHeader() throws {
        let (text, data) = try makeShiftJISDataWithAsciiHeader(body: "\0" + "日本語の本文です。\n")

        let decoded = TextEncoding.decodeText(data)

        #expect(decoded == text)
    }

    @Test("先頭8KBがASCIIで本文にNULを含むShift_JISファイルでdetectEncodingがUTF-16と誤判定しない")
    func detectEncodingDoesNotMisdetectShiftJISWithNulByteAsUtf16() throws {
        let (_, data) = try makeShiftJISDataWithAsciiHeader(body: "\0" + "日本語の本文です。\n")

        let detected = TextEncoding.detectEncoding(data)

        #expect(detected?.encoding != .utf16LittleEndian)
        #expect(detected?.encoding != .utf16BigEndian)
    }

    @Test("先頭8KB以内に孤立したNULが1個だけあるUTF-8テキストはUTF-16と誤判定されずそのまま復号される")
    func decodesUTF8WithSingleStrayNulInSniffWindowWithoutMisdetection() throws {
        let text = "見出し\0本文の続き\n2行目です。"
        let data = try #require(text.data(using: .utf8))

        let detected = TextEncoding.detectEncoding(data)
        #expect(detected?.encoding == .utf8)

        let decoded = TextEncoding.decodeText(data)
        #expect(decoded == text)
    }

    @Test("2バイト文字がsniffLength境界をまたぐShift_JISファイルを正しくデコードする")
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

    // MARK: - fallbackScanLimit

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
