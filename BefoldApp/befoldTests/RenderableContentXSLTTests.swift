@testable import befold
import BefoldKit
@testable import BefoldRenderKit
import Foundation
import Testing

/// XML を XSLT 変換表示へ差し替える条件。
@Suite("RenderableContent (XSLT 差し替え)")
struct RenderableContentXSLTTests {
    private static let xmlURL = URL(fileURLWithPath: "/docs/notice.xml")
    private static let xml = "<?xml version=\"1.0\"?>\n<doc/>"
    private static let xmlType = FileType.xml

    private func reader(withStylesheet: Bool = true) -> InMemoryFileReader {
        InMemoryFileReader(files: withStylesheet ? ["/docs/notice.xsl": "<xsl:stylesheet/>"] : [:])
    }

    private func make(
        isSourceMode: Bool = false, allowsXSLT: Bool = true, allowsSiblingFileReads: Bool = true,
        filePath: URL? = xmlURL, fileType: FileType = xmlType, withStylesheet: Bool = true
    ) -> RenderableContent.Renderable {
        RenderableContent.make(
            Self.xml, fileType: fileType, filePath: filePath, isSourceMode: isSourceMode,
            allowsXSLT: allowsXSLT, allowsSiblingFileReads: allowsSiblingFileReads,
            fileReader: reader(withStylesheet: withStylesheet)
        )
    }

    @Test("xsl を解決できたら種別が xslt になり、内容は {xml, xsl} の JSON になる")
    func promotesWhenStylesheetResolves() throws {
        let renderable = make()
        #expect(renderable.type == ViewerXSLTBridge.renderType)
        #expect(renderable.lang == nil)
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: Data(renderable.content.utf8)) as? [String: String]
        )
        #expect(decoded == ["xml": Self.xml, "xsl": "<xsl:stylesheet/>"])
    }

    @Test("xsl が無ければ素通しし、従来どおりコード表示へ落ちる")
    func staysCodeWhenNoStylesheet() {
        let renderable = make(withStylesheet: false)
        #expect(renderable.type == "code")
        #expect(renderable.lang == "xml")
        #expect(renderable.content == Self.xml)
    }

    @Test("ソース表示中は差し替えない")
    func doesNotPromoteInSourceMode() {
        expectUnpromoted(make(isSourceMode: true))
    }

    @Test("変換を許さない呼び出し(追記チャンク・切り詰め)では差し替えない")
    func doesNotPromoteWhenXSLTIsNotAllowed() {
        // 断片や切り詰めた XML は構文として閉じておらず、変換にかければ必ずパースエラーになる。
        expectUnpromoted(make(allowsXSLT: false))
    }

    @Test("兄弟ファイルを読めないホスト(QuickLook 等)では差し替えない")
    func doesNotPromoteWhenSiblingReadsAreDisallowed() {
        expectUnpromoted(make(allowsSiblingFileReads: false))
    }

    @Test("パスが無ければ差し替えない")
    func doesNotPromoteWithoutFilePath() {
        expectUnpromoted(make(filePath: nil))
    }

    @Test("XML 以外の種別は差し替えない")
    func doesNotPromoteOtherFileTypes() {
        expectUnpromoted(make(fileType: .code(language: "json")))
    }

    private func expectUnpromoted(
        _ renderable: RenderableContent.Renderable, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(renderable.type != ViewerXSLTBridge.renderType, sourceLocation: sourceLocation)
        #expect(renderable.content == Self.xml, sourceLocation: sourceLocation)
    }
}
