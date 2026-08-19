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
public final class ViewerRenderer {
    public var webView: WKWebView?
    public var webViewProxy: WebViewProxy?
    /// JS 側で起きた出来事の通知先。アプリ本体では ViewerWindowController が実装する。
    /// 循環参照を避けるため weak。QuickLook 拡張のような静的 1 回描画ホストは
    /// 設定しないままでよい(全メソッドに既定実装があり、通知は捨てられる)。
    public weak var delegate: (any ViewerRendererDelegate)?
    /// 「続きを読み込む」の実行中フラグ。非同期読み込み中の再押下を無視し、
    /// 追記の交錯(順序の入れ替わり)を防ぐ。
    var isLoadingMoreLines = false
    /// JS からの postMessage の受信・デコード・配達。
    /// makeWebView が WKUserContentController へ登録する実ハンドラ。
    private(set) lazy var messageRouter = BridgeMessageRouter(renderer: self)
    /// パス参照解決の FIFO 直列化とページ世代の管理。
    private(set) lazy var referenceQueue = ReferenceResolutionQueue(renderer: self)
    /// WKWebView のナビゲーション事象の受け口。makeWebView が navigationDelegate へ設定する
    /// 実ハンドラで、ViewerRenderer 側に転送メソッドは置かない(受け口をここ 1 つに限る)。
    private(set) lazy var navigationCoordinator = ViewerNavigationCoordinator(renderer: self)
    /// 検索バーの3トグルの永続化ストア。findOptionsChanged 受信時に書き戻す。
    /// QuickLook 拡張等、検索 UI を持たないホストでは nil のまま省略できる。
    public var findOptionsPreference: FindOptionsPreference?

    /// 見出しジャンプのレベル設定を**記録するだけ**の口（TASK-485.2）。
    /// 読み取り API を持たない型にしてあるため、窓が保存値を読み直す経路は作れない。
    public weak var headingJumpLevelRecording: (any HeadingJumpLevelRecording)?
    /// 直接 HTML モード・相対画像埋め込みの有効/無効フラグ。
    public var rendererFeatures: RendererFeatures = .allEnabled
    /// applyRender/applyAppend の画像埋め込み(embeddedContent)が使うインスタンス。
    /// render 経路とロード時ウォームアップ(ViewerLoadPipeline)が同じキャッシュを
    /// 引くため、本番は既定の .shared のまま使うこと。テストでは低速な FileReading を
    /// 注入したフェイクに差し替え、withBlockingWork の完了タイミングを制御する。
    var imageEmbedder: MarkdownImageEmbedder = .shared
    /// 初期倍率の投影(望む倍率と適用済みの記録)。詳細は PageZoomProjector.swift を参照。
    private(set) lazy var pageZoom = PageZoomProjector(renderer: self)

    /// 呼び出し側から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用にも使う。
    /// 実体は `pageZoom.desired`(ホスト向けの公開名だけをここに残す転送プロパティ)。
    public var initialPageZoom: Double {
        get { pageZoom.desired }
        set { pageZoom.desired = newValue }
    }

    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    public var scrollPositionToRestore: Double = 0
    /// 直接 HTML モードの状態機械(判定・ロード・復帰・リンクポリシー)。
    private(set) lazy var directHTML = DirectHTMLModeController(renderer: self)
    /// viewer.html のロード完了ゲート。
    let readiness = ViewerReadinessGate()
    /// 描画のための evaluateJavaScript 発行点。
    private(set) lazy var scriptDispatcher = ViewerScriptDispatcher(renderer: self)
    /// この文書が画面に出ているか。ホスト(ViewerWebView)が毎回の更新で流し込む。
    /// false の間は再描画を行わない。見えていない文書の再レイアウトは、外部エディタや
    /// ビルドがファイルを書き換えるたびに走ってメインスレッドを使うだけで、誰も見ない。
    /// 見える状態へ戻ると、ホストが最新の内容で updateContent を呼び直すため、
    /// 抑止した更新は 1 回に畳まれる(ADR 0002 段 5)。
    public var isVisible = true
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

    public init() {}

    /// WKWebView を構成し、viewer.html をロードして返す。
    /// - Parameters:
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    ///   - findOptionsPreference: 検索バー3トグルの永続化ストア。QuickLook 等では nil を渡す。
    ///   - codeFontFamily: ロード前に JS へ注入するソースビュー等幅フォントファミリー名。
    ///     nil はシステム既定(QuickLook 等では nil を渡す)。
    ///   - codeFontSizePoints: ロード前に JS へ注入するソースビューのコードフォントサイズ(pt)。
    ///     nil は未カスタマイズ(CSS 側の calc(本文*0.75) フォールバックへ委ね、
    ///     アクセシビリティ文字サイズに追従する)。
    ///   - headingJumpLevels: 見出しジャンプで目印にするレベルの初期値。保存値を持たない
    ///     呼び出し側(QuickLook 等)は既定の `.default` のままでよい(JS 側の既定と同じ意味)。
    public func makeWebView(
        initialZoom: Double, findOptionsPreference: FindOptionsPreference?,
        codeFontFamily: String? = nil, codeFontSizePoints: Double? = nil,
        headingJumpLevels: HeadingJumpLevels = .default
    ) -> WKWebView {
        self.findOptionsPreference = findOptionsPreference
        initialPageZoom = initialZoom
        let webView = ViewerWebViewFactory.makeWebView(
            options: ViewerWebViewFactory.Options(
                initialZoom: initialZoom, findOptions: findOptionsPreference,
                headingJumpLevels: headingJumpLevels,
                codeFontFamily: codeFontFamily, codeFontSizePoints: codeFontSizePoints,
                features: rendererFeatures
            ),
            messageHandler: messageRouter
        )
        webView.navigationDelegate = navigationCoordinator
        self.webView = webView
        ViewerWebViewFactory.loadViewerHTML(into: webView)
        return webView
    }

    /// makeWebView で登録した postMessage ハンドラを解除する。
    public func dismantle(_ webView: WKWebView) {
        ViewerWebViewFactory.dismantle(webView, features: rendererFeatures)
    }

    /// viewer.html の準備ができていれば即実行し、まだなら準備完了まで保留する。
    func runWhenReady(_ work: @escaping () -> Void) {
        readiness.run(work)
    }
}
