import BefoldKit
import WebKit

/// ViewerRenderer が JS 側の出来事を通知する先。アプリ本体では ViewerWindowController が実装する。
///
/// 全メソッドに「何もしない」既定実装があるため、QuickLook 拡張のような
/// 静的 1 回描画ホストは必要なものだけを実装すればよい(delegate 自体を設定しなくてもよい)。
@MainActor
public protocol ViewerRendererDelegate: AnyObject {
    /// JS 側で表示倍率が変わった。
    ///
    /// `url` は **その倍率が属する文書**。スクロール位置(下記)と同じく JS が倍率を読むのと
    /// 同じターンで payload に載せた値で、配達の遅延と無関係に実 DOM の文書と一致する。
    /// 倍率もファイル単位で永続化されるため、受け取り側は現在表示中の URL ではなく必ず
    /// この `url` をキーに使うこと(現在値を参照すると、切替直後に届いた旧文書の通知が
    /// 切替先の倍率を上書きして誤って保存される = TASK-391)。
    /// 描画前など、出所の文書が定まらない場合は nil。
    func renderer(_ renderer: ViewerRenderer, didChangeZoom zoom: Double, for url: URL?)
    /// JS 側でスクロール位置が変わった。
    ///
    /// `url` は **その位置が属する文書**。JS が位置(scrollTop)を読むのと同じターンで
    /// 読んで payload に載せた値で、evaluateJavaScript のキューや postMessage 配達の
    /// 遅延と無関係に実 DOM の文書と一致する(TASK-393)。通知は JS 側で 200ms
    /// デバウンスされるため、ファイル切替の直後に切替前の文書の通知が届きうる。
    /// 受け取り側は現在表示中の URL ではなく必ずこの `url` をキーに使うこと
    /// (現在値を参照すると切替前の位置が切替先のキーへ保存される = TASK-400)。
    /// 描画前・直接 HTML モードなど、出所の文書が定まらない場合は nil。
    func renderer(
        _ renderer: ViewerRenderer, didChangeScrollPosition position: Double, for url: URL?,
        mode: ViewerBridge.ViewMode
    )
    /// リンクまたはパス参照がアクティベートされた。
    func renderer(_ renderer: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition)
    /// リンクまたはパス参照の上で ctrl+クリック(右クリック)された。
    func renderer(_ renderer: ViewerRenderer, didRequestContextMenuFor href: String)
    /// JS が検出したパス参照群の解決を要求した。
    /// 戻り値: 書かれたパス -> 解決済み絶対パス(実在するもののみ)。
    /// 解決は git subprocess を伴いうるため非同期。実装は MainActor をブロックせずに返すこと。
    func renderer(_ renderer: ViewerRenderer, resolveReferences paths: [String]) async -> [String: String]
    /// JS 側「続きを読み込む」が押された。次チャンクと更新後の表示状態を返す。
    func rendererDidRequestMoreLines(_ renderer: ViewerRenderer) async -> LoadMoreLinesResult?
}

public extension ViewerRendererDelegate {
    func renderer(_: ViewerRenderer, didChangeZoom _: Double, for _: URL?) {}
    func renderer(
        _: ViewerRenderer, didChangeScrollPosition _: Double, for _: URL?, mode _: ViewerBridge.ViewMode
    ) {}
    func renderer(_: ViewerRenderer, didActivateReference _: String, disposition _: OpenDisposition) {}
    func renderer(_: ViewerRenderer, didRequestContextMenuFor _: String) {}
    func renderer(_: ViewerRenderer, resolveReferences _: [String]) async -> [String: String] {
        [:]
    }

    func rendererDidRequestMoreLines(_: ViewerRenderer) async -> LoadMoreLinesResult? {
        nil
    }
}

/// WKWebView の構成・viewer.html ロード・render() 評価を担う WKWebView ドライバ。
/// find/loadMore/リンク遷移などアプリ専用機能はフック注入・オプショナルにしてあり、
/// QuickLook 拡張(.appex)のような静的1回描画ホストではそれらを省いて利用できる。
@MainActor
public final class ViewerRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    public var webView: WKWebView?
    public var webViewProxy: WebViewProxy?
    /// JS 側で起きた出来事の通知先。アプリ本体では ViewerWindowController が実装する。
    /// 循環参照を避けるため weak。QuickLook 拡張のような静的 1 回描画ホストは
    /// 設定しないままでよい(全メソッドに既定実装があり、通知は捨てられる)。
    public weak var delegate: (any ViewerRendererDelegate)?
    /// 「続きを読み込む」の実行中フラグ。非同期読み込み中の再押下を無視し、
    /// 追記の交錯(順序の入れ替わり)を防ぐ。
    var isLoadingMoreLines = false
    /// 解決応答(applyResolvedReferences 評価)の直列チェーン。JS は応答を要求へ FIFO で
    /// 対応づけるため、解決が非同期になっても評価順が要求順とずれてはならない。
    /// 各要求は直前の要求の完了を待ってから解決・評価する。
    var resolveResponseChain: Task<Void, Never>?
    /// JS コンテキストの世代。ページを読み直すと JS 側の状態は捨てられ、参照解決の
    /// FIFO キュー(_mmdPendingRefBatches)も空になる。世代をまたいだ応答をそのまま
    /// 評価すると、新しいページが積んだ別のバッチへ古いマップが当たり、実在する
    /// パスまで解決失敗表示になる(TASK-421)。飛行中の応答はこの値で捨てる。
    /// 増やすのは viewer.html を読み直す `reloadViewerHTML` の 1 箇所だけ。
    ///
    /// `contentUpdateGeneration` を流用してはならない。通常の再描画では JS 側が
    /// `_mmdInvalidatePendingRefs()` でバッチの中身だけを空にし、**キューの長さ
    /// (未応答の要求数)は保つ**。つまり再描画をまたぐ応答は捨てずに評価し続ける必要が
    /// あり、捨てるとキューが恒久的にずれて以後すべての参照が解決失敗表示になる。
    /// 捨ててよいのは、キューごと消える読み直しの場合だけ。
    var pageGeneration = 0
    /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
    /// QuickLook 拡張等、検索 UI を持たないホストでは nil のまま省略できる。
    public var findOptionsPreference: FindOptionsPreference?
    /// 直接 HTML モード・相対画像埋め込みの有効/無効フラグ。
    public var rendererFeatures: RendererFeatures = .allEnabled
    /// applyRender/applyAppend の画像埋め込み(embeddedContent)が使うインスタンス。
    /// render 経路とロード時ウォームアップ(ViewerLoadPipeline)が同じキャッシュを
    /// 引くため、本番は既定の .shared のまま使うこと。テストでは低速な FileReading を
    /// 注入したフェイクに差し替え、Task.detached の完了タイミングを制御する。
    var imageEmbedder: MarkdownImageEmbedder = .shared
    /// 呼び出し側から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用に使う。
    ///
    /// 生成時のユーザースクリプト(atDocumentStart)に焼き込むだけでは、ウィンドウの生成が
    /// 表示対象の確定より先に走ったときに既定倍率のまま取り残される。値の変化と
    /// viewer.html の準備完了の双方で適用し直し、「状態の投影」として扱う(ADR 0002 / TASK-270)。
    public var initialPageZoom: Double = 1.0 {
        didSet {
            guard initialPageZoom != oldValue else { return }
            applyInitialPageZoomIfReady()
        }
    }

    /// viewer.js へ適用済みの倍率。同じ値を何度も評価しないための記録。
    var appliedPageZoom: Double?
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    public var scrollPositionToRestore: Double = 0
    /// loadOneShot が描画完了(mermaid 等の非同期描画を含む)を待つ上限。
    /// QuickLook のプレビュー生成をハングさせないための保険で、超過した場合は
    /// その時点の DOM のまま完了として返す。負荷の高いテスト環境など、
    /// ホスト側の事情で待ち時間を伸ばしたい場合に差し替える。
    public var oneShotRenderTimeout: Duration = .seconds(3)
    /// HTML 直接ロード完了後に適用する pageZoom。適用後は nil に戻す。
    var pendingPageZoom: Double?
    var isReady = false
    /// この文書が画面に出ているか。ホスト(ViewerWebView)が毎回の更新で流し込む。
    /// false の間は再描画を行わない。見えていない文書の再レイアウトは、外部エディタや
    /// ビルドがファイルを書き換えるたびに走ってメインスレッドを使うだけで、誰も見ない。
    /// 見える状態へ戻ると、ホストが最新の内容で updateContent を呼び直すため、
    /// 抑止した更新は 1 回に畳まれる(ADR 0002 段 5)。
    public var isVisible = true
    var pendingUpdate: (() -> Void)?
    /// updateContent 呼び出しごとに増分する世代番号。applyRender/applyAppend は画像埋め込み
    /// (MainActor 外)の完了後、この値が呼び出し時と変わっていないかを確認してから
    /// evaluateJavaScript/recordRendered を行う。後続の updateContent に追い越された古い
    /// 埋め込み結果が rendered ミラーを巻き戻すのを防ぐ(ViewerStore.loadGeneration と同じ idiom)。
    var contentUpdateGeneration = 0
    /// 直近に描画した表示状態のミラー(型の定義は RenderedStateMirror.swift)。
    ///
    /// 確定の入口を `recordRendered` の 1 つに限るため setter をこのファイルに閉じてある。
    /// 部分更新できる入口を残すと、ミラーへフィールドを足したときにそこだけ確定漏れが起き、
    /// 状態変化が 1 周期失われる(TASK-320 / TASK-334 で 2 度起きた形)。
    private(set) var rendered = RenderedStateMirror()

    /// 描画済みミラーをまるごと確定させる。render()/append() を実際に
    /// evaluateJavaScript した後にだけ呼ぶこと(`applyRender` の解説を参照)。
    /// 一部のフィールドだけを変えたい呼び出し元は、現在の `rendered` を複製して
    /// 書き換えてから渡すこと。
    func recordRendered(_ state: RenderedStateMirror) {
        rendered = state
    }

    /// ソース表示へ重ねる git 差分。ホストが更新のたびに設定する
    /// (updateContent の引数にせず、rendererFeatures や initialPageZoom と同じ
    /// 「レンダラの設定」として持つ。QuickLook 等のホストは既定の .none のまま)。
    public var diffState: DiffState = .none

    var pendingAppend: PendingAppend?
    var isDirectHTMLMode = false
    var lastDirectHTMLPath: URL?

    override public init() {}

    /// WKWebView を構成し、viewer.html をロードして返す。
    /// - Parameters:
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    ///   - findOptionsPreference: 検索バー3トグルの永続化ストア。QuickLook 等では nil を渡す。
    ///   - codeFontFamily: ロード前に JS へ注入するソースビュー等幅フォントファミリー名。
    ///     nil はシステム既定(QuickLook 等では nil を渡す)。
    ///   - codeFontSizePoints: ロード前に JS へ注入するソースビューのコードフォントサイズ(pt)。
    ///     nil は未カスタマイズ(CSS 側の calc(本文*0.75) フォールバックへ委ね、
    ///     アクセシビリティ文字サイズに追従する)。
    public func makeWebView(
        initialZoom: Double, findOptionsPreference: FindOptionsPreference?,
        codeFontFamily: String? = nil, codeFontSizePoints: Double? = nil
    ) -> WKWebView {
        self.findOptionsPreference = findOptionsPreference
        initialPageZoom = initialZoom
        let webView = ViewerWebViewFactory.makeWebView(
            options: ViewerWebViewFactory.Options(
                initialZoom: initialZoom, findOptions: findOptionsPreference,
                codeFontFamily: codeFontFamily, codeFontSizePoints: codeFontSizePoints,
                features: rendererFeatures
            ),
            messageHandler: self
        )
        webView.navigationDelegate = self
        self.webView = webView
        ViewerWebViewFactory.loadViewerHTML(into: webView)
        return webView
    }

    /// makeWebView で登録した postMessage ハンドラを解除する。
    public func dismantle(_ webView: WKWebView) {
        ViewerWebViewFactory.dismantle(webView, features: rendererFeatures)
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        if isDirectHTMLMode, let zoom = pendingPageZoom {
            webView.pageZoom = zoom
            pendingPageZoom = nil
        }
        applyInitialPageZoomIfReady()
        pendingUpdate?()
        pendingUpdate = nil
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(webView: webView)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(webView: webView)
    }

    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
    /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
    /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
    /// (実装は type_body_length 対策で ViewerRenderer+DirectHTMLLinkPolicy.swift に分離)
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        decidePolicyForDirectHTMLAware(webView: webView, navigationAction: navigationAction)
    }

    /// 直接 HTML モードを解除し、viewer.html へ復帰する。
    /// 現在の initialPageZoom を viewer.js へ適用する。viewer.html の準備前・
    /// HTML 直接ロード中(viewer.js が無い)・同じ値を適用済みのときは何もしない。
    func applyInitialPageZoomIfReady() {
        guard isReady, !isDirectHTMLMode, let webView else { return }
        guard appliedPageZoom != initialPageZoom else { return }
        appliedPageZoom = initialPageZoom
        webView.evaluateJavaScript(ViewerBridge.applyZoomScript(initialPageZoom))
    }

    /// 直接 HTML モードの判定状態(`isDirectHTMLMode` / `webViewProxy?.isDirectHTMLMode` /
    /// `lastDirectHTMLPath`)と、`rendered` ミラー 6 値を必ずセットで破棄してから
    /// viewer.html を再ロードする。ミラーは `rendered.reset()` で一括リセットする
    /// (再ロードで JS 側状態 `_mmdViewOptions`(行番号 false / モード rendered)が
    /// 初期化されるため、Swift 側のミラーも全て破棄して次回更新時に再注入させる)。
    /// 一部だけ倒すと直接 HTML モードの判定と再描画キャッシュの整合性が崩れるため、
    /// 呼び出し側で個別にリセットしないこと。`pendingAppend` は `rendered` の一部ではないが、
    /// 直接 HTML モードへの切替(pendingAppend 消費前に return する分岐)を挟んで残留した
    /// 増分チャンクが復帰後に誤って古い内容へ適用されないよう、ここで併せて破棄する。
    func exitDirectHTMLMode(webView: WKWebView, completion: @escaping () -> Void) {
        isDirectHTMLMode = false
        webViewProxy?.isDirectHTMLMode = false
        // viewer.html を読み直すと JS 側の倍率も初期化されるため、適用済みの記録も捨てる。
        appliedPageZoom = nil
        lastDirectHTMLPath = nil
        rendered.reset()
        pendingAppend = nil
        reloadViewerHTML(webView: webView, then: completion)
    }

    /// ナビゲーション失敗時に isReady のハングを防ぐ。直接ロード失敗なら viewer.html へ
    /// 安全にフォールバックする。
    private func handleNavigationFailure(webView: WKWebView) {
        pendingPageZoom = nil
        if isDirectHTMLMode {
            // 削除起因の失敗は呼び出し側がウィンドウを閉じる等の対応をするため、
            // ここでは viewer.html へ戻すだけでよい
            exitDirectHTMLMode(webView: webView) {}
        } else {
            isReady = true
            pendingUpdate?()
            pendingUpdate = nil
        }
    }
}
