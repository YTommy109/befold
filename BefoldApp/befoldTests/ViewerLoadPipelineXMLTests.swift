@testable import befold
import BefoldKit
import BefoldPDFProbe
import BefoldTestSupport
import Foundation
import Testing

/// XSL を伴う XML の読み込み経路(TASK-608 / TASK-609)。
/// `ViewerLoadPipelineTests` から分けてあるのは、同居させると
/// `type_body_length` を超えるため(規約どおり型を分割する)。
@Suite
struct ViewerLoadPipelineXMLTests {
    private let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
        try ViewerLoadPipeline.defaultChunkedReaderFactory(cache, fileType)
    }

    private func inputs(
        _ url: URL, _ fileType: FileType, _ fileReader: any FileReading
    ) -> ViewerLoadPipeline.Inputs {
        ViewerLoadPipeline.Inputs(
            resolved: url,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            isPDFReadable: PDFDataProbe.isReadable
        )
    }

    /// 1000 行(`StringChunkReader.linesPerChunk`)を超える XML。
    /// XSL があれば全量読み込みへ、無ければ従来どおりチャンク読み込みへ落ちる。
    private func longXML() -> String {
        "<?xml version=\"1.0\"?>\n<root>\n"
            + String(repeating: "  <item>x</item>\n", count: 2000)
            + "</root>\n"
    }

    private let stylesheet = """
    <?xml version="1.0"?>
    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:template match="/"><div/></xsl:template>
    </xsl:stylesheet>
    """

    @Test("XSL を解決できる XML は 1000 行を超えても全量読み込みになる")
    func xmlWithStylesheetLoadsWhole() async {
        let url = URL(fileURLWithPath: "/tmp/law.xml")
        let xml = longXML()
        let fileReader = InMemoryFileReader(files: [
            url.path: xml,
            "/tmp/law.xsl": stylesheet,
        ])

        let outcome = await ViewerLoadPipeline.load(inputs(url, .xml, fileReader))

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.rejectReason == nil)
        // 打ち切られていれば末尾の閉じタグが欠ける = XSLT 変換が必ず失敗する。
        #expect(loaded.content.hasSuffix("</root>\n"))
    }

    @Test("XSL を解決できない XML は従来どおりチャンク読み込みで段階描画する")
    func xmlWithoutStylesheetStaysChunked() async {
        let url = URL(fileURLWithPath: "/tmp/plain.xml")
        let fileReader = InMemoryFileReader(files: [url.path: longXML()])

        let outcome = await ViewerLoadPipeline.load(inputs(url, .xml, fileReader))

        guard case let .chunked(_, _, _, isAtEnd) = outcome else {
            Issue.record("chunked outcome を期待したが \(outcome) だった")
            return
        }
        #expect(!isAtEnd)
    }

    @Test("10MB を超える XML も XSL があれば全量読み込みになる")
    func largeXMLWithStylesheetLoadsWhole() async {
        let url = URL(fileURLWithPath: "/tmp/large-law.xml")
        // 非行指向テキストの上限(10MB)は超えるが XSLT 変換の上限(20MB)には収まる規模。
        let body = String(
            repeating: "  <item>x</item>\n", count: ContentLoader.maxTextFileSizeBytes / 12
        )
        let fileReader = InMemoryFileReader(files: [
            url.path: "<?xml version=\"1.0\"?>\n<root>\n" + body + "</root>\n",
            "/tmp/large-law.xsl": stylesheet,
        ])

        let outcome = await ViewerLoadPipeline.load(inputs(url, .xml, fileReader))

        guard case let .full(loaded, _) = outcome else {
            Issue.record("full outcome を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.rejectReason == nil)
    }

    @Test("XSLT 変換の上限は本体だけに効き、QuickLook は従来の上限のまま")
    func xmlTransformLimitAppliesToMainAppOnly() {
        #expect(
            ViewerLoadPipeline.fullLoadSizeLimit(fileType: .xml, oneShotLoad: false)
                == ContentLoader.maxXMLTransformSizeBytes
        )
        #expect(
            ViewerLoadPipeline.fullLoadSizeLimit(fileType: .xml, oneShotLoad: true)
                == ContentLoader.maxOneShotTextFileSizeBytes
        )
        #expect(
            ViewerLoadPipeline.fullLoadSizeLimit(fileType: .html, oneShotLoad: false)
                == ContentLoader.maxTextFileSizeBytes
        )
    }

    @Test("全量読み込みの上限を超える XML は XSL があってもチャンク読み込みのまま")
    func oversizedXMLWithStylesheetStaysChunked() async {
        let url = URL(fileURLWithPath: "/tmp/huge.xml")
        // 1 行 17 バイト × 上限バイト数 / 16 で、上限をわずかに超える規模にする。
        let body = String(
            repeating: "  <item>x</item>\n", count: ContentLoader.maxXMLTransformSizeBytes / 16
        )
        let fileReader = InMemoryFileReader(files: [
            url.path: "<?xml version=\"1.0\"?>\n<root>\n" + body + "</root>\n",
            "/tmp/huge.xsl": stylesheet,
        ])

        let outcome = await ViewerLoadPipeline.load(inputs(url, .xml, fileReader))

        guard case .chunked = outcome else {
            Issue.record("chunked outcome を期待したが \(outcome) だった")
            return
        }
    }
}
