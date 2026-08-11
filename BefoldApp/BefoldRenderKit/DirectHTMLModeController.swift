import AppKit
import BefoldKit
import WebKit

/// HTML を viewer.html を介さず loadFileURL で直接ロードするモードの状態機械。
///
/// 「いま直接ロード中か」「どのファイルを直接ロードしたか」「ロード完了後に当てる倍率」を
/// 1 型へ集め、`webViewProxy` への同期も didSet に閉じる(分離前は 3 箇所へ散っていた)。
@MainActor
final class DirectHTMLModeController {
    private unowned let renderer: ViewerRenderer

    /// 直接ロード中かどうか。ホスト側の判定に使う `webViewProxy` へ必ず同時に反映する。
    private(set) var isActive = false {
        didSet { renderer.webViewProxy?.isDirectHTMLMode = isActive }
    }

    /// 直接ロード中のファイル。切替の検出に使う。
    private(set) var lastPath: URL?

    /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
    private var pendingPageZoom: Double?

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    #if DEBUG
        /// 直接ロード中の状態をテストから組み立てるための唯一の seam。
        /// 実ロードを伴わずに状態だけを立てられる入口をここ 1 つに限る
        /// (プロパティを個別に書ける形に戻すと、webViewProxy への同期漏れが再発する)。
        func simulateForTesting(active: Bool, lastPath: URL? = nil) {
            isActive = active
            self.lastPath = lastPath
        }
    #endif

    /// 直接 HTML モードへ入るべきかどうかを判定する。
    /// features.allowDirectHTML が false の場合は常に入らず、viewer.html 経由の通常描画に
    /// フォールバックする(QuickLook 等、親ディレクトリへの read 権限がない実行環境向け)。
    nonisolated static func shouldEnter(
        fileType: FileType, isSourceMode: Bool, filePath: URL?, features: RendererFeatures
    ) -> Bool {
        fileType == .html && !isSourceMode && filePath != nil && features.allowDirectHTML
    }

    /// 直接ロードを実行する。同一ファイル・同一内容で既に直接ロード中なら何もしない。
    /// - Returns: ロードを行った(または不要と判断した)場合 true。呼び出し側はここで打ち切る。
    func enter(webView: WKWebView, filePath: URL, request: DirectHTMLLoadRequest) -> Bool {
        let pathChanged = filePath != lastPath
        let contentChanged = request.contentRevision != renderer.rendered.contentRevision
        guard !isActive || pathChanged || contentChanged else { return true }

        // 初回ロード・ファイル切替では保存済みの per-file 倍率を使い、
        // ライブリロード（同一ファイルの content 変更）では現在の倍率を維持する。
        let isFirstLoadOrSwitch = !isActive || pathChanged
        pendingPageZoom = isFirstLoadOrSwitch ? renderer.initialPageZoom : webView.pageZoom
        // 直接ロードでは viewer.js が居らず行番号・切り詰め・差分は適用されないため、
        // それらは現在のミラー値のまま持ち越す(復帰時に exit が rendered.reset() で
        // 一括破棄する)。フィールドを並べず現在値から組み立てて丸ごと確定させるのは、
        // ミラーへフィールドを足したときの確定漏れを防ぐため。
        var state = renderer.rendered
        state.contentRevision = request.contentRevision
        state.fileType = request.fileType
        state.filePath = filePath
        state.isSourceMode = request.isSourceMode
        renderer.recordRendered(state)
        lastPath = filePath
        isActive = true
        renderer.readiness.markNotReady()
        // 直接ロードへ入ると viewer.js が居なくなる。復帰時に再適用させる。
        renderer.appliedPageZoom = nil
        // 直接ロードする HTML 内の <script> 実行を無効化する（設計スコープ外）。
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        load(webView: webView, filePath: filePath, request: request)
        return true
    }

    /// charset 宣言(BOM/<meta charset>)のある HTML は WebKit の解釈で正しく読めるため、
    /// 相対リソースを読める loadFileURL のまま。宣言の無い HTML だけは WebKit が既定
    /// エンコーディングを誤推定して文字化けするので、ViewerLoadPipeline が MainActor 外で
    /// 判定・UTF-8 正規化済みの content を明示エンコーディングでロードする。loadData は
    /// allowingReadAccessTo を伴わず宣言なし HTML から相対参照した兄弟リソースは読めなく
    /// なるが、宣言なし HTML は簡易な断片が大半で影響は小さい。判定不能(nil)時は
    /// loadFileURL へフォールバックする。
    private func load(webView: WKWebView, filePath: URL, request: DirectHTMLLoadRequest) {
        if request.hasDeclaredHTMLCharset == false {
            webView.load(
                Data(request.content.utf8), mimeType: "text/html",
                characterEncodingName: "UTF-8", baseURL: filePath
            )
        } else {
            webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
        }
    }

    /// 直接 HTML モードを解除し、viewer.html へ復帰する。
    ///
    /// 判定状態(`isActive` / `webViewProxy?.isDirectHTMLMode` / `lastPath`)と
    /// `rendered` ミラーを必ずセットで破棄してから再ロードする(再ロードで JS 側状態
    /// `_mmdViewOptions`(行番号 false / モード rendered)が初期化されるため、Swift 側の
    /// ミラーも全て破棄して次回更新時に再注入させる)。一部だけ倒すと直接 HTML モードの
    /// 判定と再描画キャッシュの整合性が崩れるため、呼び出し側で個別にリセットしないこと。
    /// `pendingAppend` は `rendered` の一部ではないが、直接 HTML モードへの切替
    /// (pendingAppend 消費前に return する分岐)を挟んで残留した増分チャンクが復帰後に
    /// 誤って古い内容へ適用されないよう、ここで併せて破棄する。
    func exit(webView: WKWebView, completion: @escaping () -> Void) {
        isActive = false
        // viewer.html を読み直すと JS 側の倍率も初期化されるため、適用済みの記録も捨てる。
        renderer.appliedPageZoom = nil
        lastPath = nil
        renderer.recordRendered(RenderedStateMirror())
        renderer.pendingAppend = nil
        renderer.reloadViewerHTML(webView: webView, then: completion)
    }

    /// ロード完了時に、直接ロードへ入る前に控えた倍率を当てる。
    func applyPendingZoom(to webView: WKWebView) {
        guard isActive, let zoom = pendingPageZoom else { return }
        webView.pageZoom = zoom
        pendingPageZoom = nil
    }

    /// ナビゲーション失敗時に控えた倍率を捨てる。
    func discardPendingZoom() {
        pendingPageZoom = nil
    }

    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードでは
    /// それ以外のナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。
    /// 直接 HTML モードではリンククリック(.linkActivated)のみ分類して処理する。
    func decidePolicy(
        webView: WKWebView, navigationAction: WKNavigationAction
    ) -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .other {
            return .allow
        }
        guard isActive else { return .cancel }
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            return .cancel
        }

        switch DirectHTMLLinkPolicy.classify(
            url: url, currentURL: webView.url, modifierFlags: navigationAction.modifierFlags
        ) {
        case .allowNativeNavigation:
            return .allow
        case let .openLocalFile(fileURL, disposition):
            renderer.delegate?.renderer(renderer, didActivateReference: fileURL.path, disposition: disposition)
            return .cancel
        case let .openExternal(externalURL):
            NSWorkspace.shared.open(externalURL)
            return .cancel
        case .ignore:
            return .cancel
        }
    }
}

/// `DirectHTMLModeController.enter` の引数をまとめた入力。
struct DirectHTMLLoadRequest {
    let content: String
    let contentRevision: Int
    let fileType: FileType
    let isSourceMode: Bool
    let hasDeclaredHTMLCharset: Bool?
}
