import AppKit
import BefoldKit
import WebKit

/// WKWebView の構成・viewer.html のロード・postMessage ハンドラの登録解除を担う。
///
/// ViewerRenderer の stored property を一切参照しないため独立した型として切り出してある
/// (必要な値はすべて `Options` で受け取る)。
public enum ViewerWebViewFactory {
    /// WKWebView 生成時に JS へ焼き込む値。
    struct Options {
        /// ロード前に JS へ注入する初期倍率。
        let initialZoom: Double
        /// 検索バー 3 トグルの永続化ストア。QuickLook 等では nil。
        let findOptions: FindOptionsPreference?
        /// ソースビュー等幅フォントファミリー名。nil はシステム既定。
        let codeFontFamily: String?
        /// ソースビューのコードフォントサイズ(pt)。nil は未カスタマイズで、
        /// CSS 側の calc(本文*0.75) フォールバックへ委ねてアクセシビリティ文字サイズに追従する。
        let codeFontSizePoints: Double?
        /// 直接 HTML モード・相対画像埋め込み・対話的ブリッジの有効/無効。
        let features: RendererFeatures
    }

    /// WKUserContentController はハンドラを強参照するため、実ハンドラへの参照を弱めて
    /// dismantle の呼び出しに依存せずリークを防ぐプロキシ。
    final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var delegate: WKScriptMessageHandler?

        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    /// JS → Swift の postMessage ハンドラ名一覧。生成での登録・dismantle での解除を
    /// 一箇所から駆動する(新規メッセージ追加時はここに加えるだけでよい)。
    /// referenceActivated/loadMoreLines は features.allowsInteractiveBridging が false の
    /// (QuickLook 拡張等の静的1回描画ホストを想定した)場合、そもそも登録しない
    /// (多層防御: XSS が postMessage を直接呼んでもハンドラ未登録のため Swift 側に届かない)。
    public nonisolated static func messageHandlerNames(for features: RendererFeatures) -> [String] {
        ViewerBridgeMessage.allCases
            .filter { features.allowsInteractiveBridging || !$0.requiresInteractiveBridging }
            .map(\.rawValue)
    }

    /// バンドル同梱の viewer.html を WebView へ読み込む。
    /// リソース名(`"viewer"` / `"html"`)の出現箇所をここに一本化する。
    /// 既定 bundle は BefoldRenderKit 自身のリソースバンドルではなく、viewer.html
    /// 本体を同梱する BefoldKit のリソースバンドル(`Bundle.main` 非依存)を指す。
    public nonisolated static func loadViewerHTML(into webView: WKWebView, bundle: Bundle = .befoldKitResources) {
        guard let htmlURL = bundle.url(forResource: "viewer", withExtension: "html") else { return }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }

    /// 構成済みの WKWebView を返す。ナビゲーション delegate の設定と viewer.html の
    /// ロードは呼び出し側(ViewerRenderer)が行う。
    @MainActor
    static func makeWebView(options: Options, messageHandler: WKScriptMessageHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if DEBUG
            // Web インスペクタを有効化する（公開 API がないため KVC を使用）。
            // 開発ビルドのみで有効にし、リリースビルドには含めない
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        for source in userScriptSources(options: options) {
            config.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        // JS → Swift の postMessage ハンドラをまとめて登録する(同一 delegate のため一括化)。
        for name in messageHandlerNames(for: options.features) {
            config.userContentController.add(
                WeakScriptMessageHandler(delegate: messageHandler), name: name
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        setDocumentOwnsCanvas(false, on: webView)
        // トラックパッドのピンチジェスチャーでズームできるようにする。
        // viewer.html 経由のコンテンツは既存の ctrl+wheel ハンドラ(viewer.html)で
        // 対応済みだが、.html ファイル直接ロード時はこの経路を通らないため必要。
        webView.allowsMagnification = true
        // WebKit標準の「2本指スワイプでページ履歴を戻る/進む」は本アプリの
        // ページ内履歴(loadFileURLのみ)とは無関係なため無効化し、呼び出し側が
        // 二本指スワイプでファイル履歴を扱えるようにする。
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    /// 表示するコンテンツが「外部の HTML 文書」かどうか。canvas(地)の所有者判定はここが唯一。
    ///
    /// ソース表示中の HTML は befold がコードとして描画するので該当しない。直接ロード経路
    /// (DirectHTMLModeController)と viewer.html 内の iframe 経路(QuickLook 等)の両方が
    /// この判定を共有する。
    static func documentOwnsCanvas(fileType: FileType, isSourceMode: Bool) -> Bool {
        fileType == .html && !isSourceMode
    }

    /// canvas を文書に所有させるかどうかを WebView へ適用する。
    ///
    /// 既定は透過(false)。キャンバス色は `ViewerTheme.canvas` が唯一の定義で、CSS は地を
    /// 塗らない(style.css 冒頭の設計コメント)。**外部の HTML 文書だけがこの原則の例外**で、
    /// ブラウザと同じく文書が canvas ごと所有する。透過のままだと、明るい背景を前提に
    /// 文字色だけを指定した HTML が befold のダークキャンバス上に載って読めなくなる
    /// (TASK-511)。
    ///
    /// 実測(ダークアピアランス / `WKWebView.takeSnapshot` のピクセル):
    /// - false … a=0.00(WebView は塗らない)。透過は iframe の子文書へも伝播し、子の
    ///   `color-scheme` 宣言は届かなくなる(親側で `background: white` を当てると今度は
    ///   `color-scheme: dark` を宣言した子が壊れる)
    /// - true … `color-scheme` 宣言なしの文書は #FFFFFF、`dark` / `light dark` 宣言時は
    ///   #282828 を WebKit が塗る。iframe の srcdoc 子文書も**子自身の宣言**に従うため、
    ///   iframe 経路に CSS の手当ては要らない
    static func setDocumentOwnsCanvas(_ owned: Bool, on webView: WKWebView) {
        // drawsBackground に公開 API がないため KVC を使う。
        webView.setValue(owned, forKey: "drawsBackground")
    }

    /// makeWebView で登録した postMessage ハンドラを解除する。
    @MainActor
    static func dismantle(_ webView: WKWebView, features: RendererFeatures) {
        for name in messageHandlerNames(for: features) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    /// ロード前に注入する JS を一括で組み立てる(全て atDocumentStart / メインフレーム限定)。
    /// Markdown 本文をシステム設定のテキストサイズに合わせる際は preferredFont(.body) を使う
    /// (アクセシビリティのテキストサイズ変更に追従、既定 13pt)。
    @MainActor
    private static func userScriptSources(options: Options) -> [String] {
        [
            ViewerBridge.initialZoomScript(options.initialZoom),
            ViewerBridge.systemFontSizeScript(NSFont.preferredFont(forTextStyle: .body).pointSize),
            ViewerBridge.monoFontFamilyScript(options.codeFontFamily),
            ViewerBridge.codeFontSizeScript(options.codeFontSizePoints),
            ViewerBridge.initialFindOptionsScript(
                ViewerBridge.FindOptions(
                    caseSensitive: options.findOptions?.caseSensitive ?? false,
                    wholeWord: options.findOptions?.wholeWord ?? false,
                    useRegex: options.findOptions?.useRegex ?? false
                )
            ),
            ViewerBridge.findStringsScript(),
            ViewerBridge.bannerStringsScript(),
            ViewerBridge.hostFeaturesScript(
                loadMore: options.features.allowsInteractiveBridging,
                spaceScroll: options.features.allowsSpaceScroll,
                referenceActivation: options.features.allowsInteractiveBridging
            ),
        ]
    }
}
