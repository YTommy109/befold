import AppKit

/// 倍率の 1 段変更。値の刻みと上下限は呼び出し側(ZoomStore)が持つ。
enum ZoomChange {
    case zoomIn
    case zoomOut
    case reset
}

/// 表示中の文書に対してできること(ADR 0002 段 4 の port)。
///
/// 呼び出し側(WebViewCommandController)は「能力を確認して意図を伝える」だけにし、
/// WKWebView・JS 文字列・ブリッジ契約の詳細は adapter(WebViewDocumentRenderer)に閉じる。
/// これにより、レンダラへ何が命じられたかをテストで検証できる境界ができる。
/// 境界が無かった頃は、ウィンドウ系テストが WebView 不在で回るため
/// `guard let webView else { return }` により JS 契約のズレまで「no-op が正常」として通過していた。
@MainActor
protocol DocumentRendering: AnyObject {
    /// HTML を直接ロードして表示しているか。viewer.html の JS が居ないため検索できない。
    var isDirectHTMLMode: Bool { get }

    /// 指定倍率を適用する(保存値の反映)。
    func applyZoom(_ zoom: Double)

    /// ソースビューの等幅フォント設定を反映する。
    func applyCodeFont(family: String?, points: Double?)

    /// 倍率を 1 段変える。直接 HTML モードでは適用後の倍率を返す(保存は呼び出し側の責務)。
    /// viewer.js が倍率を持つ通常モードでは nil を返す(保存も JS からの通知経由)。
    func changeZoom(_ change: ZoomChange) -> Double?

    /// ページ内検索を開く / 次へ / 前へ。
    func openFind()
    func findNext()
    func findPrevious()

    /// 文書内ジャンプを開く。
    /// kind は目印の種類。生の String ではなく `DocumentJumpKind` で受けるのは、
    /// 種類ごとの可否検査(`ViewerCapabilities.canJump(to:)`)をコマンド経路が
    /// 迂回できないようにするため(TASK-485.7)。文字列へ落とすのは JS 境界の
    /// `WebViewDocumentRenderer` 1 箇所だけ。
    ///
    /// 閉じる / 次へ / 前へ は Swift 側の入口を持たない。Esc・Enter・Shift+Enter は
    /// viewer の keydown ハンドラが処理しており、Swift から呼ぶ経路が無いため
    /// 配管だけが残っていた(TASK-485.15 で撤去)。メニューやキーバインドから
    /// 呼ぶ必要が出たら、そのときに再導入する。
    func openJump(kind: DocumentJumpKind)

    /// いま使える目印の種類を viewer へ知らせる。開いているジャンプバーの種類が
    /// この集合から外れていれば、viewer 側がバーを閉じる(TASK-485.18)。
    ///
    /// 「閉じろ」ではなく「使える集合」を送るのは、判定を Swift 側の
    /// `ViewerCapabilities.canJump(to:)` 1 箇所に保つため。閉じる条件を JS 側で
    /// 組み直すと、開くときの guard と同じ規則が 2 つの言語で別々に育つ。
    func applyJumpAvailability(_ kinds: Set<DocumentJumpKind>)

    /// 表示内容を指定ウィンドウ上のシートとして印刷する。
    func printDocument(over window: NSWindow?)

    /// 現在のスクロール位置を問い合わせる。取得できなければ呼ばれない。
    func currentScrollPosition(_ completion: @escaping (Double) -> Void)

    /// ファイルの rename / move を描画状態(描画済みミラーと JS 側の文書パス)へ追随させる。
    /// `perFileState.migrate` と同じ同期区間で呼ぶこと。呼ばないと、リネーム再描画が
    /// ファイル切替として扱われてスクロール位置が保存値へ巻き戻り(TASK-401)、
    /// 再描画確定までのスクロール通知が旧パスのキーへ保存される(TASK-393)。
    func noteRename(from oldURL: URL, to newURL: URL)
}
