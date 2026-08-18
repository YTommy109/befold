import BefoldKit
@testable import BefoldRenderKit
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
        let result = DirectHTMLModeController.shouldEnter(
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
        let names = ViewerWebViewFactory.messageHandlerNames(for: .quickLookRestricted)

        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.resolveReferencesMessageName))
        #expect(names.count == 4)
    }

    @Test("allowsSpaceScroll は静的プレビューで false、本体アプリで true")
    func allowsSpaceScrollFollowsInteractivePreset() {
        #expect(!RendererFeatures.quickLookRestricted.allowsSpaceScroll)
        #expect(RendererFeatures.allEnabled.allowsSpaceScroll)
    }

    /// QuickLook では Space はホストのプレビューを閉じるジェスチャなので、
    /// viewer 側が preventDefault しないよう hostFeatures へ false を伝える。
    @MainActor
    @Test("makeWebView が spaceScroll をプリセットに応じて注入する")
    func makeWebViewInjectsSpaceScrollFlag() {
        #expect(injectedSpaceScroll(for: .quickLookRestricted) == false)
        #expect(injectedSpaceScroll(for: .allEnabled) == true)
    }

    /// makeWebView がロード前に登録した hostFeatures スクリプトから
    /// spaceScroll の値だけを取り出す。見つからなければ nil。
    @MainActor
    private func injectedSpaceScroll(for features: RendererFeatures) -> Bool? {
        let renderer = ViewerRenderer()
        renderer.rendererFeatures = features
        let webView = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        let sources = webView.configuration.userContentController.userScripts.map(\.source)
        guard let script = sources.first(where: { $0.contains("_mmdHostFeatures") }) else {
            return nil
        }
        let json = script
            .replacingOccurrences(of: "window._mmdHostFeatures = ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Bool]
        else {
            return nil
        }
        return decoded["spaceScroll"]
    }
}
