import AppKit
import BefoldKit

/// ViewerWindowController のメニュー/ツールバーから届く文書操作コマンド
/// (ズーム・印刷・検索・スクロール位置保存)の方針を担う。
///
/// ここが持つのは「その操作が許されるか(capabilities)」と「結果をどこへ届けるか」だけで、どう実現するかは `DocumentRendering` の実装(adapter)に委ねる。
/// WKWebView と JS 文字列はこの層に現れない(ADR 0002 段 4)。
@MainActor
final class DocumentCommandController {
    /// この窓の描画面の束。**宛先の決定はこの型が持つ**ので、ここでは種別を見ない
    /// (ADR 0002 段 2 の「条件は 1 箇所」を宛先にも適用する / TASK-564.6)。
    private let surfaces: DocumentSurfaces
    private let perFileState: PerFileStateStore
    /// 提示中の文書 URL への共有参照。rename/switch で書き換わるため値を捕捉せず都度参照する。
    private let currentDocument: CurrentDocumentRef
    /// いま何ができるか。判断は ViewerWindowController.capabilities が唯一の導出元で、
    /// ここでは受け取った値を使うだけ(ADR 0002)。
    private let capabilities: () -> ViewerCapabilities
    /// 倍率が変わったことを窓へ伝える。窓はこれを自分のライブ値へ反映する。
    /// **既定値を与えない**。渡し忘れが静かにライブ値の取り残しになるのを防ぐ
    /// (直接 HTML モードは viewer.js が居らず、JS からの通知が来ないため
    /// ここだけが更新の契機になる = ADR 0002「文書の状態の規則」)。
    private let onZoomChanged: (Double) -> Void
    /// スクロール位置の取得が完了したことを、キーと値ごと窓へ伝える。位置を記憶するのは
    /// 窓側（`ViewerDocumentPresenter`）で、ここは取得と受け渡ししかしない。
    /// 位置の取得は JS のラウンドトリップを挟むため、切替の退場側で発行した保存は
    /// 切替先の提示開始(保存値の同期読み取り)より後に完了しうる。窓はこの通知で
    /// 「いま提示中の文書のものなら」ライブな復元値を追いつかせる(TASK-394)。
    /// **既定値を与えない**。渡し忘れると往復時に古い位置を復元したままになる。
    private let onScrollPositionSaved: (Double, URL, ViewerBridge.ViewMode) -> Void

    init(
        surfaces: DocumentSurfaces,
        perFileState: PerFileStateStore,
        currentDocument: CurrentDocumentRef,
        onZoomChanged: @escaping (Double) -> Void,
        onScrollPositionSaved: @escaping (Double, URL, ViewerBridge.ViewMode) -> Void,
        capabilities: @escaping () -> ViewerCapabilities = { .none }
    ) {
        self.surfaces = surfaces
        self.perFileState = perFileState
        self.currentDocument = currentDocument
        self.onZoomChanged = onZoomChanged
        self.onScrollPositionSaved = onScrollPositionSaved
        self.capabilities = capabilities
    }

    // 設定の反映(applyCodeFont)は能力で止めない。止めると、フォルダーを見ている間の
    // 設定変更が常駐 WebView に入らないまま取り残される。
    // 止めるのはユーザー操作(印刷・検索・ズーム)だけ。

    /// ユーザー操作の宛先。**いま描いている面 1 枚**を、描画が確定した種別から引く。
    /// 提示予定の URL からではないこと(理由は `DocumentSurfaces.operating(on:)` の doc)。
    private var renderer: any DocumentSurfaceOperating {
        surfaces.operating(on: currentDocument.renderedFileType)
    }

    /// find/findNext/findPrevious の有効判定に使う。HTML 直接ロード中は viewer.html の
    /// JS が存在しないため検索系メニューを無効化する。
    var isDirectHTMLMode: Bool {
        renderer.isDirectHTMLMode
    }

    // MARK: - Zoom

    // MARK: - Code font

    /// 設定変更時に等幅フォント設定を注入し直して即時反映する。
    func applyCodeFont(family: String?, points: Double?) {
        for surface in surfaces.syncingAll {
            surface.applyCodeFont(family: family, points: points)
        }
    }

    /// 設定の反映なので applyCodeFont と同じく能力(ViewerCapabilities)では止めない。
    func applyCsvNumberFormat(grouping: Bool, negativeStyle: CsvNegativeStyle) {
        for surface in surfaces.syncingAll {
            surface.applyCsvNumberFormat(grouping: grouping, negativeStyle: negativeStyle)
        }
    }

    /// 倍率を 1 段変える。直接 HTML モードは viewer.js を経由しないため、適用後の倍率が返り、
    /// 窓のライブ値の更新と保存をここで行う(通常モードは JS からの通知が同じ 2 つを行う)。
    private func changeZoom(_ change: ZoomChange) {
        guard capabilities().canZoom else { return }
        guard let newZoom = renderer.changeZoom(change) else { return }
        onZoomChanged(newZoom)
        perFileState.zoom.setZoom(newZoom, for: currentDocument.url)
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

    /// 統合バー(TASK-485.19)の単一入口。Edit > 検索…(⌘F、kind なし)と
    /// Edit > 見出しへジャンプ / 変更箇所へジャンプ(kind あり)がここへ収斂する。
    ///
    /// kind を明示したときは常にそのモードを強制する(検索とジャンプは同じ理由で
    /// 使い分けるものではなく、ユーザーが選んだ種類をそのまま尊重する)。
    /// kind が nil のとき(⌘F 相当の非明示オープン)だけ、
    /// `ViewerCapabilities.defaultBarKind` に既定モードの選択を委ねる。
    /// ここで `showsDiff` 等の個別フラグを直接見ないのは、「変更ブロックへ
    /// ジャンプできるか」の条件(ジャンプの能力・フィーチャーゲート込み)を
    /// `ViewerCapabilities` の外で再実装すると、条件の一部だけを見落として
    /// (例: フィーチャーゲートが閉じているのに差分表示中というだけで
    /// 変更箇所ジャンプへ倒し、ジャンプ側の guard で無言の no-op になり
    /// ⌘F が何も開かなくなる)取りこぼす経路ができるため(ADR 0002 段 2
    /// 「条件は 1 箇所」)。
    func openBar(kind: DocumentJumpKind?) {
        guard let resolvedKind = kind ?? capabilities().defaultBarKind else {
            openFind()
            return
        }
        openJump(kind: resolvedKind)
    }

    /// 本番コードからは `openBar(kind:)` を経由すること。ここへの直接呼び出しは
    /// テスト専用(`openBar` の既定モード選択を迂回してしまうため)。
    /// キーボードのフォーカスを**いま描いている面**へ移す（⌘→ / TASK-584）。
    ///
    /// 能力では絞らない。どの種別でも「本文を読む」ことはできるので、フォーカスを
    /// 渡せない面は無い。面がまだ組み上がっていなければ proxy 側が黙って何もしない。
    func focusSurface() {
        renderer.focusSurface()
    }

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

    // MARK: - Document jump

    /// 種類ごとの可否で閉じる。粗い `canJump` だけで通すと、メニュー検証だけが
    /// 種類別の規則(変更ブロックは差分表示が必要)を守る形になり、メニュー以外の
    /// 入口(キーバインド・ツールバー)が同じ穴を継承する(TASK-485.7)。
    ///
    /// 本番コードからは `openBar(kind:)` を経由すること(理由は `openFind()` と同じ)。
    func openJump(kind: DocumentJumpKind) {
        guard capabilities().canJump(to: kind) else { return }
        renderer.openJump(kind: kind)
    }

    /// いま使える種類を viewer へ送り直す。開いているバーの種類が使えなくなって
    /// いれば viewer 側が閉じる(TASK-485.18)。
    ///
    /// 集合は `allCases` を `canJump(to:)` で絞って作る。openJump の guard と
    /// **同じ述語**を通すので、開く条件と開き続けられる条件が食い違わない。
    /// 種類を足したときも列挙を書き足す必要が無い(書き足し漏れは
    /// 「新しい種類だけ失効しない」という形で表に出るため、構造で塞ぐ)。
    func syncJumpAvailability() {
        let capabilities = capabilities()
        let kinds = Set(DocumentJumpKind.allCases.filter { capabilities.canJump(to: $0) })
        for surface in surfaces.syncingAll {
            surface.applyJumpAvailability(kinds)
        }
    }

    // MARK: - Rotation

    /// 表示を 90 度単位で回す。回せる面かどうかは能力が決める(種別を見ない)。
    /// 度数の符号は時計回りが正。
    func rotate(byDegrees degrees: Int) {
        guard capabilities().canRotate else { return }
        renderer.rotate(byDegrees: degrees)
    }

    /// いま描いている面の回転角。窓が切替の退場側で読み、その文書の記憶へ入れる。
    var currentRotation: Int {
        renderer.currentRotation
    }

    // MARK: - Scroll position

    /// 現在のスクロール位置を問い合わせ、指定した URL・モードのキーごと窓へ通知する。
    /// 現在の表示状態に依存せず呼び出し側が指定したキーを載せるだけで、いつ呼ぶべきか
    /// (切替前でなければならない)の判断は呼び出し側が負う
    /// (ViewerWindowController.saveScrollPositionBeforeTransition 参照)。
    ///
    /// 保存キーは「その位置が属する文書」を呼び出し側が指定する。現在表示中の fileURL は
    /// 参照しない(現在値を参照すると切替直後に別文書のキーへ書く = TASK-400)。
    /// **記憶へ位置が届く経路はこれ 1 本**(TASK-574.3)。かつては web 面だけが、
    /// スクロールのたびに JS から送る継続通知も併せ持っていた。
    func saveCurrentScrollPosition(for url: URL, mode: ViewerBridge.ViewMode) {
        renderer.currentScrollPosition { [onScrollPositionSaved] position in
            onScrollPositionSaved(position, url, mode)
        }
    }

    // MARK: - Rename

    /// ファイルの rename / move を描画状態へ追随させる(詳細は DocumentRendering.noteRename)。
    /// ユーザー操作ではなく状態の追随なので、applyCodeFont と同じく能力では止めない。
    func noteRename(from oldURL: URL, to newURL: URL) {
        for surface in surfaces.syncingAll {
            surface.noteRename(from: oldURL, to: newURL)
        }
    }
}
