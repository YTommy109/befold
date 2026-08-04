import AppKit
import BefoldKit

/// ViewerWindowController のメニュー/ツールバーから届く文書操作コマンド
/// (ズーム・印刷・検索・スクロール位置保存)の方針を担う。
///
/// ここが持つのは「その操作が許されるか(capabilities)」と「結果をどこへ保存するか
/// (perFileState)」だけで、どう実現するかは `DocumentRendering` の実装(adapter)に委ねる。
/// WKWebView と JS 文字列はこの層に現れない(ADR 0002 段 4)。
@MainActor
final class WebViewCommandController {
    private let renderer: any DocumentRendering
    private let perFileState: PerFileStateStore
    /// 現在表示中ファイルの URL。rename/switch で書き換わるため値を捕捉せず都度取得する。
    private let currentURL: () -> URL
    /// いま何ができるか。判断は ViewerWindowController.capabilities が唯一の導出元で、
    /// ここでは受け取った値を使うだけ(ADR 0002)。
    private let capabilities: () -> ViewerCapabilities

    init(
        renderer: any DocumentRendering,
        perFileState: PerFileStateStore,
        currentURL: @escaping () -> URL,
        capabilities: @escaping () -> ViewerCapabilities = { .none }
    ) {
        self.renderer = renderer
        self.perFileState = perFileState
        self.currentURL = currentURL
        self.capabilities = capabilities
    }

    // 設定の反映(applyStoredZoom/applyCodeFont)は能力で止めない。止めると、
    // フォルダーを見ている間の設定変更が常駐 WebView に入らないまま取り残される。
    // 止めるのはユーザー操作(印刷・検索・ズーム)だけ。

    /// find/findNext/findPrevious の有効判定に使う。HTML 直接ロード中は viewer.html の
    /// JS が存在しないため検索系メニューを無効化する。
    var isDirectHTMLMode: Bool {
        renderer.isDirectHTMLMode
    }

    // MARK: - Zoom

    /// 現在のファイルの保存倍率を適用する。
    func applyStoredZoom() {
        renderer.applyZoom(perFileState.zoom.zoom(for: currentURL()))
    }

    // MARK: - Code font

    /// 設定変更時に等幅フォント設定を注入し直して即時反映する。
    func applyCodeFont(family: String?, points: Double?) {
        renderer.applyCodeFont(family: family, points: points)
    }

    /// 倍率を 1 段変える。直接 HTML モードは viewer.js を経由しないため、
    /// 適用後の倍率が返り、その保存だけをここで行う(通常モードは JS からの通知で保存される)。
    private func changeZoom(_ change: ZoomChange) {
        guard capabilities().canZoom else { return }
        guard let newZoom = renderer.changeZoom(change) else { return }
        perFileState.zoom.setZoom(newZoom, for: currentURL())
    }

    func zoomIn() {
        changeZoom(.zoomIn)
    }

    func zoomOut() {
        changeZoom(.zoomOut)
    }

    func resetZoom() {
        changeZoom(.reset)
    }

    // MARK: - Print

    func printDocument(over window: NSWindow?) {
        guard capabilities().canPrint else { return }
        renderer.printDocument(over: window)
    }

    // MARK: - Find

    func openFind() {
        guard capabilities().canFind else { return }
        renderer.openFind()
    }

    func findNext() {
        guard capabilities().canFind else { return }
        renderer.findNext()
    }

    func findPrevious() {
        guard capabilities().canFind else { return }
        renderer.findPrevious()
    }

    // MARK: - Scroll position

    /// 現在のスクロール位置を問い合わせ、指定した URL・モードのキーへ保存する。
    /// 現在の表示状態に依存せず呼び出し側が指定したキーへ書くだけで、いつ呼ぶべきか
    /// (切替前でなければならない)の判断は呼び出し側が負う
    /// (ViewerWindowController.saveScrollPositionBeforeTransition 参照)。
    func saveCurrentScrollPosition(for url: URL, mode: ViewerBridge.ViewMode) {
        renderer.currentScrollPosition { [perFileState] position in
            perFileState.scrollPosition.setScrollPosition(position, for: url, mode: mode)
        }
    }
}
