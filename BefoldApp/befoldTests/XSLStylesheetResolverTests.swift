import BefoldKit
import Foundation
import Testing

@Suite("XSLStylesheetResolver")
struct XSLStylesheetResolverTests {
    private let xmlURL = URL(fileURLWithPath: "/docs/notice.xml")

    private func reader(_ files: [String: String]) -> InMemoryFileReader {
        InMemoryFileReader(files: files)
    }

    @Test("処理命令が指す .xsl を解決して本文を返す")
    func resolvesStylesheetFromProcessingInstruction() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <?xml-stylesheet type="text/xsl" href="official.xsl"?>
        <doc><title>通知</title></doc>
        """
        let resolved = XSLStylesheetResolver.resolve(
            xml: xml, fileURL: xmlURL,
            fileReader: reader(["/docs/official.xsl": "<xsl:stylesheet/>"])
        )
        #expect(resolved == "<xsl:stylesheet/>")
    }

    @Test("処理命令が無ければ同名の .xsl をフォールバックとして使う")
    func fallsBackToSameNamedStylesheet() {
        let resolved = XSLStylesheetResolver.resolve(
            xml: "<doc/>", fileURL: xmlURL,
            fileReader: reader(["/docs/notice.xsl": "<xsl:stylesheet/>"])
        )
        #expect(resolved == "<xsl:stylesheet/>")
    }

    @Test("処理命令の指す先が無ければ同名の .xsl へ落ちる")
    func fallsBackWhenReferencedStylesheetIsMissing() {
        let xml = "<?xml-stylesheet type=\"text/xsl\" href=\"missing.xsl\"?>\n<doc/>"
        let resolved = XSLStylesheetResolver.resolve(
            xml: xml, fileURL: xmlURL,
            fileReader: reader(["/docs/notice.xsl": "same-named"])
        )
        #expect(resolved == "same-named")
    }

    @Test("どちらも見つからなければ nil")
    func returnsNilWhenNoStylesheetExists() {
        #expect(XSLStylesheetResolver.resolve(xml: "<doc/>", fileURL: xmlURL, fileReader: reader([:])) == nil)
    }

    @Test("本文中のコメントに書かれた処理命令は拾わない")
    func ignoresProcessingInstructionInsideBody() {
        // ルート要素より後ろの同じ形は処理命令ではない。ここを拾うと、文書が
        // 例示として載せた href が実ファイルの選択に効いてしまう。
        let xml = """
        <doc>
          <!-- <?xml-stylesheet type="text/xsl" href="attacker.xsl"?> -->
        </doc>
        """
        let resolved = XSLStylesheetResolver.resolve(
            xml: xml, fileURL: xmlURL,
            fileReader: reader(["/docs/attacker.xsl": "bad", "/docs/notice.xsl": "good"])
        )
        #expect(resolved == "good")
    }

    @Test("ディレクトリを跨ぐ href は使わない", arguments: ["../secret.xsl", "sub/child.xsl", "file:///etc/x.xsl"])
    func rejectsHrefOutsideTheDirectory(href: String) {
        let xml = "<?xml-stylesheet type=\"text/xsl\" href=\"\(href)\"?>\n<doc/>"
        let files = ["/secret.xsl": "escaped", "/docs/sub/child.xsl": "escaped", "/etc/x.xsl": "escaped"]
        #expect(XSLStylesheetResolver.resolve(xml: xml, fileURL: xmlURL, fileReader: reader(files)) == nil)
    }

    @Test("href より前に置かれた疑似属性を href と取り違えない")
    func picksHrefRatherThanTheFirstPseudoAttribute() {
        let xml = "<?xml-stylesheet type=\"text/xsl\" media=\"screen\" href=\"style.xsl\"?>\n<doc/>"
        let resolved = XSLStylesheetResolver.resolve(
            xml: xml, fileURL: xmlURL, fileReader: reader(["/docs/style.xsl": "picked"])
        )
        #expect(resolved == "picked")
    }

    @Test("空のスタイルシートは見つからなかったものとして扱う")
    func treatsEmptyStylesheetAsMissing() {
        // 空ファイルを渡すと XSLTProcessor がパースエラーになるだけなので、
        // ソース表示へ落とす経路(nil)に寄せる。
        #expect(
            XSLStylesheetResolver.resolve(
                xml: "<doc/>", fileURL: xmlURL, fileReader: reader(["/docs/notice.xsl": ""])
            ) == nil
        )
    }
}
