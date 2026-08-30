import AppKit
import BefoldKit

/// 倍率の 1 段変更。値の刻みと上下限は呼び出し側(ZoomStore)が持つ。
enum ZoomChange {
    case zoomIn
    case zoomOut
    case reset
}

/// **いま見えている面 1 枚に向ける**操作(ADR 0002 段 4 の port の前半)。
///
/// ユーザーが「この文書に対して」行う操作がここに入る。描画面が複数あるとき、
/// これらは**いま描いている面 1 枚**へ振り分ける。見えていない面へ送っても
/// 意味が無い(あるいは間違った面が反応する)ものだけを置くこと。
///
/// 追随(`DocumentSurfaceSyncing`)との線引きは「宛先が 1 枚か全部か」であって、
/// 「ユーザー操作か否か」ではない。`noteRename` はユーザー操作だが全部へ配る。
@MainActor
protocol DocumentSurfaceOperating: AnyObject {
    /// HTML を直接ロードして表示しているか。viewer.html の JS が居ないため検索できない。
    var isDirectHTMLMode: Bool { get }

    /// 指定倍率を適用する(保存値の反映)。
    func applyZoom(_ zoom: Double)

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

    /// 表示内容を指定ウィンドウ上のシートとして印刷する。
    func printDocument(over window: NSWindow?)

    /// 現在のスクロール位置を問い合わせる。取得できなければ呼ばれない。
    func currentScrollPosition(_ completion: @escaping (Double) -> Void)

    /// 表示を 90 度単位で回す(度数は 90 の倍数)。
    /// 回せるのは PDF の面だけで、可否は `ViewerCapabilities.canRotate` が持つ。
    func rotate(byDegrees degrees: Int)

    /// いまの回転角(0 / 90 / 180 / 270)。回転を持たない面は常に 0。
    /// 窓はこれを**切替の退場側で**読み、その文書の記憶へ入れる
    /// (`ViewerDocumentPresenter.saveScrollPositionBeforeTransition` と同じ契機)。
    var currentRotation: Int { get }
}

/// **すべての描画面へ配る**追随(ADR 0002 段 4 の port の後半)。
///
/// 「いま見えているか」に関係なく、どの面も最新の状態にしておかなければならない
/// ものがここに入る。描画面が複数あるとき、これらは**全部へブロードキャストする**。
/// 種別で振り分けてはならない。
///
/// 振り分けると 2 つの事故が戻る。どちらも既存コードのコメントが名指ししている。
///
/// - 設定の反映(`applyCodeFont` / `applyCsvNumberFormat` / `applyJumpAvailability`):
///   `DocumentCommandController` はこれらを能力(`ViewerCapabilities`)でも止めていない。
///   止めると「フォルダーを見ている間の設定変更が常駐 WebView に入らないまま
///   取り残される」ため。種別で振り分けると、同じ取り残しが**種別の形で**戻る
///   (PDF を見ている間に変えたフォントが WebView へ入らない)。
/// - `noteRename`: `ViewerWindowController+FileNavigation.handleRename` は
///   `applyURLToWindow(newURL)` を `noteRename` より**先**に呼ぶ。振り分けると
///   常に新しい URL 側の面へ届き、対応形式が変わるリネーム(`.pdf` → `.md` など)で
///   旧側の面が追随しない。下の `noteRename` の doc が警告する TASK-401 / TASK-393 が
///   そのまま再発する。
@MainActor
protocol DocumentSurfaceSyncing: AnyObject {
    /// ソースビューの等幅フォント設定を反映する。
    func applyCodeFont(family: String?, points: Double?)
    /// CSV/TSV の数値表示設定を注入し直して即時反映する。コードフォントと違い、
    /// viewer 側は現在の文書を描き直す(セルの HTML 文字列そのものが変わるため)。
    func applyCsvNumberFormat(grouping: Bool, negativeStyle: CsvNegativeStyle)

    /// いま使える目印の種類を viewer へ知らせる。開いているジャンプバーの種類が
    /// この集合から外れていれば、viewer 側がバーを閉じる(TASK-485.18)。
    ///
    /// 「閉じろ」ではなく「使える集合」を送るのは、判定を Swift 側の
    /// `ViewerCapabilities.canJump(to:)` 1 箇所に保つため。閉じる条件を JS 側で
    /// 組み直すと、開くときの guard と同じ規則が 2 つの言語で別々に育つ。
    func applyJumpAvailability(_ kinds: Set<DocumentJumpKind>)

    /// ファイルの rename / move を描画状態(描画済みミラーと JS 側の文書パス)へ追随させる。
    /// `perFileState.migrate` と同じ同期区間で呼ぶこと。呼ばないと、リネーム再描画が
    /// ファイル切替として扱われてスクロール位置が保存値へ巻き戻り(TASK-401)、
    /// 再描画確定までのスクロール通知が旧パスのキーへ保存される(TASK-393)。
    func noteRename(from oldURL: URL, to newURL: URL)
}

/// 表示中の文書に対してできること(ADR 0002 段 4 の port)。
///
/// 呼び出し側(DocumentCommandController)は「能力を確認して意図を伝える」だけにし、
/// WKWebView・JS 文字列・ブリッジ契約の詳細は adapter(WebViewDocumentRenderer)に閉じる。
/// これにより、レンダラへ何が命じられたかをテストで検証できる境界ができる。
/// 境界が無かった頃は、ウィンドウ系テストが WebView 不在で回るため
/// `guard let webView else { return }` により JS 契約のズレまで「no-op が正常」として通過していた。
///
/// **1 枚の面はこの両方を満たす。** 2 群に分けてあるのは宛先の違い(1 枚 / 全部)を
/// 型で表すためで、実装側を分ける意図ではない(TASK-564.6)。
typealias DocumentRendering = DocumentSurfaceOperating & DocumentSurfaceSyncing
