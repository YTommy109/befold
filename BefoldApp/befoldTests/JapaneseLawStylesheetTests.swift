import BefoldKit
import Foundation
import Testing

@Suite("JapaneseLawStylesheet")
struct JapaneseLawStylesheetTests {
    private let lawRoot = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Law Era="Showa" Year="21" Num="000" LawType="Constitution" Lang="ja">
      <LawNum>昭和二十一年憲法</LawNum>
      <LawBody><LawTitle>日本国憲法</LawTitle></LawBody>
    </Law>
    """

    /// バンドルへの登録漏れは実行時まで気づけない(`swift build` はディレクトリを
    /// 走査するだけなので通る)。Package.swift / project.yml の両方に載っていることを
    /// 実際に読んで確かめる。
    @Test("内蔵スタイルシートがバンドルから読める")
    func bundledStylesheetIsReadable() throws {
        let xsl = try #require(JapaneseLawStylesheet.stylesheet(forXML: lawRoot))
        #expect(xsl.contains("xsl:stylesheet"))
        #expect(xsl.contains("law-article"))
    }

    @Test("法令標準XMLのルート要素を判定する", arguments: [
        // (説明, XML, 期待値)
        ("Era と Num を持つ Law", "<Law Era=\"Heisei\" Year=\"1\" Num=\"1\"/>", true),
        ("属性の無い Law", "<Law/>", false),
        ("Era だけの Law", "<Law Era=\"Heisei\"/>", false),
        ("別のルート要素", "<Document Era=\"Heisei\" Num=\"1\"/>", false),
        // 前方一致で LawBody 等を拾わないこと。
        ("名前が Law で始まる別要素", "<LawSet Era=\"Heisei\" Num=\"1\"/>", false),
    ])
    func detectsLawRootElement(name _: String, xml: String, expected: Bool) {
        #expect((JapaneseLawStylesheet.stylesheet(forXML: xml) != nil) == expected)
    }

    @Test("プロローグの処理命令やコメントを跨いでルート要素を見つける")
    func skipsPrologBeforeRootElement() {
        let xml = """
        <?xml version="1.0"?>
        <!-- 法令標準XML -->
        <Law Era="Reiwa" Year="2" Num="10"><LawNum>x</LawNum></Law>
        """
        #expect(JapaneseLawStylesheet.stylesheet(forXML: xml) != nil)
    }

    @Test("本文中に現れる Law 開始タグでは判定しない")
    func ignoresLawTagInsideBody() {
        // ルート要素だけを見る。本文の例示に引きずられて内蔵 XSL を当てると、
        // 法令ではない XML が法令の体裁で描かれる。
        let xml = "<doc><example>&lt;Law Era=\"Showa\" Num=\"1\"&gt;</example></doc>"
        #expect(JapaneseLawStylesheet.stylesheet(forXML: xml) == nil)
    }

    @Test("文書に添えられた .xsl は内蔵スタイルシートより優先される")
    func siblingStylesheetWinsOverBundled() {
        let url = URL(fileURLWithPath: "/laws/kenpo.xml")
        let resolved = XSLStylesheetResolver.resolve(
            xml: lawRoot, fileURL: url,
            fileReader: InMemoryFileReader(files: ["/laws/kenpo.xsl": "sibling"])
        )
        #expect(resolved == "sibling")
    }

    @Test("添えられた .xsl が無い法令XMLは内蔵スタイルシートへ落ちる")
    func fallsBackToBundledStylesheet() throws {
        let url = URL(fileURLWithPath: "/laws/kenpo.xml")
        let resolved = try #require(
            XSLStylesheetResolver.resolve(
                xml: lawRoot, fileURL: url, fileReader: InMemoryFileReader(files: [:])
            )
        )
        #expect(resolved == JapaneseLawStylesheet.stylesheet(forXML: lawRoot))
    }

    @Test("法令XMLでない XML は従来どおり nil のまま(回帰なし)")
    func nonLawXMLStillResolvesToNil() {
        let url = URL(fileURLWithPath: "/docs/notice.xml")
        #expect(
            XSLStylesheetResolver.resolve(
                xml: "<doc/>", fileURL: url, fileReader: InMemoryFileReader(files: [:])
            ) == nil
        )
    }
}
