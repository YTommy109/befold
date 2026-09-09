import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// XSLT 変換表示への差し替えが、描画済みミラーの種別へ漏れていないことを見る。
///
/// 差し替えは render() の引数(`Renderable.type`)にだけ効く。`Renderable` は
/// `FileType` を持たないため取り違えはコンパイルエラーになるが、この経路で
/// 実際に差し替えが起きていること自体はここでしか測れない。
@Suite(testTimeLimit())
struct ViewerRendererXSLTMirrorTests {
    private static let truncation = ViewerRenderer.TruncationState(
        isTruncated: false, lineCount: 0, failed: false
    )
    private static let xml = "<?xml version=\"1.0\"?>\n<doc><title>通知</title></doc>"

    @Test("xsl を伴う XML を描画してもミラーの種別は .xml のまま")
    @MainActor
    func mirrorKeepsRequestFileTypeAfterXSLTRender() async throws {
        // 実ファイルが要る。ディスパッチャ経由の解決は DefaultFileReader を使う。
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("task596-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let xmlURL = directory.appendingPathComponent("notice.xml")
        try Self.xml.write(to: xmlURL, atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:template match="/"><div><xsl:value-of select="doc/title"/></div></xsl:template>
        </xsl:stylesheet>
        """.write(to: directory.appendingPathComponent("notice.xsl"), atomically: true, encoding: .utf8)

        let renderer = ViewerRenderer()
        let surface = ViewerRendererMessageStubs.Surface()
        renderer.surface = surface
        renderer.readiness.markReady()
        let fileType = FileType.xml

        renderer.updateContent(
            Self.xml, contentRevision: 1, fileType: fileType, filePath: xmlURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        await waitUntilYielding { renderer.rendered.filePath == xmlURL }

        // 昇格が実際に起きていることを先に確かめる(起きていなければ下の検証は空振りする)。
        let renderScript = try #require(surface.evaluatedScripts.first { $0.hasPrefix("render(") })
        #expect(renderScript.hasSuffix(", '\(ViewerXSLTBridge.renderType)')"))
        #expect(renderScript.contains("xsl:stylesheet"))

        #expect(renderer.rendered.fileType == fileType)
    }
}
