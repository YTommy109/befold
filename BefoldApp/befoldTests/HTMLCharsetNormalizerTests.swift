import BefoldKit
import Foundation
import Testing

/// charset 未宣言 HTML の文字化け対応(TASK-178)の判定・正規化ロジックを検証する。
/// WKWebView の実描画は自動テスト対象外のため、直接ロード分岐が使う純粋関数を担保する。
@Suite
struct HTMLCharsetNormalizerTests {
    private let japanese = "見出し 日本語テキスト"

    @Test("charset 宣言の無い UTF-8 HTML は UTF-8 文字列へ正規化される")
    func normalizesUTF8WithoutDeclaration() throws {
        let html = "<h1>\(japanese)</h1>"
        let data = try #require(html.data(using: .utf8))

        #expect(!HTMLCharsetNormalizer.hasCharsetDeclaration(data))
    }

    @Test("charset 宣言のある HTML は正規化せず nil を返す(loadFileURL に委ねる)")
    func keepsDeclaredHTMLForFileURLLoad() throws {
        let html = "<html><head><meta charset=\"UTF-8\"></head><body>\(japanese)</body></html>"
        let data = try #require(html.data(using: .utf8))

        #expect(HTMLCharsetNormalizer.hasCharsetDeclaration(data))
    }

    @Test("charset 宣言の無い Shift_JIS HTML は正しく復号して UTF-8 文字列にする")
    func normalizesShiftJISWithoutDeclaration() throws {
        let html = "<h1>\(japanese)</h1>"
        let data = try #require(html.data(using: .shiftJIS))

        #expect(!HTMLCharsetNormalizer.hasCharsetDeclaration(data))
    }

    @Test("charset を Shift_JIS と宣言した HTML は正規化せず nil(WebKit の宣言解釈に委ねる)")
    func keepsDeclaredShiftJISForFileURLLoad() throws {
        let html = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=shift_jis\"><h1>\(japanese)</h1>"
        let data = try #require(html.data(using: .shiftJIS))

        #expect(HTMLCharsetNormalizer.hasCharsetDeclaration(data))
    }

    @Test("UTF-8 BOM 付き HTML は宣言ありとみなし nil を返す")
    func treatsBOMAsDeclaration() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        try data.append(#require("<h1>\(japanese)</h1>".data(using: .utf8)))

        #expect(HTMLCharsetNormalizer.hasCharsetDeclaration(data))
    }
}
