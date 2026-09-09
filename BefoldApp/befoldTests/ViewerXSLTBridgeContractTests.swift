import BefoldKit
import Foundation
import Testing

/// `ViewerXSLTBridge` の Swift → JS 契約が、実際の viewer-bundle.js と一致していること。
///
/// type トークンと content の JSON キーはどちらも「Swift が書き、JS が読む」値で、
/// 片側だけ変えても Swift はビルドが通りテストも通ってしまう(相互参照コメントだけでは
/// 守られない)。ここは成果物のソースを読んで実際に照合する。
@Suite("ViewerXSLTBridge の JS 契約")
struct ViewerXSLTBridgeContractTests {
    @Test("render の type トークンを viewer 側が同じ名前で分岐している")
    func rendererDispatchesOnTheSameRenderType() throws {
        let bundle = try ViewerBridgeContractSupport.viewerBundleSource()
        // renderShape の分岐と render() のディスパッチの両方に現れる。
        #expect(bundle.contains("=== \"\(ViewerXSLTBridge.renderType)\""))
    }

    @Test("payload の JSON キーを viewer 側が同じ名前で読んでいる")
    func rendererReadsTheSamePayloadKeys() throws {
        let bundle = try ViewerBridgeContractSupport.viewerBundleSource()
        let payload = try #require(ViewerXSLTBridge.payload(xml: "<doc/>", xsl: "<xsl/>"))
        for key in ["xml", "xsl"] {
            #expect(payload.contains("\"\(key)\":"), "payload に \(key) キーが無い")
            // _renderXslt は `'xml' in parsed && typeof parsed.xml === 'string'` の形で読む。
            #expect(bundle.contains("\"\(key)\" in parsed"), "viewer 側が \(key) キーを読んでいない")
        }
    }
}
