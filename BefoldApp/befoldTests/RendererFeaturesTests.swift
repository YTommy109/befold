import BefoldKit
import BefoldRenderKit
import Foundation
import Testing

/// QuickLook 拡張(.appex)向けプリセットの内容と、それを渡したときに
/// ネイティブ経路が実際に閉じることを検証する。
@Suite
struct RendererFeaturesTests {
    @Test("quickLookRestricted は 3 フラグすべてが false")
    func quickLookRestrictedDisablesAllFeatures() {
        let features = RendererFeatures.quickLookRestricted

        #expect(!features.allowDirectHTML)
        #expect(!features.embedImages)
        #expect(!features.allowsInteractiveBridging)
    }

    /// 親ディレクトリへの read を要求する直接 HTML ロードへ入らないこと。
    /// 直接 HTML モードの他の条件(html・レンダリング表示・ファイルパス有り)を
    /// すべて満たした状態で false になることを見る。
    @Test("quickLookRestricted では直接 HTML ロード経路に入らない")
    func quickLookRestrictedBlocksDirectHTML() {
        let result = ViewerRenderer.shouldEnterDirectHTMLMode(
            fileType: .html, isSourceMode: false,
            filePath: URL(fileURLWithPath: "/tmp/page.html"),
            features: .quickLookRestricted
        )

        #expect(!result)
    }

    /// JS → Swift の postMessage ブリッジのうち、リンク遷移・追加読込・
    /// 参照解決の 3 種のハンドラを登録しないこと。
    @Test("quickLookRestricted ではインタラクティブなメッセージハンドラを登録しない")
    func quickLookRestrictedRegistersNoInteractiveHandlers() {
        let names = ViewerRenderer.messageHandlerNames(for: .quickLookRestricted)

        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.resolveReferencesMessageName))
        #expect(names.count == 3)
    }
}
