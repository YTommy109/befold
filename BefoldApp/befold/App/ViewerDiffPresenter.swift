import BefoldKit
import Foundation

/// ソース表示へ重ねる git 差分の**取得と反映**、およびレイアウト設定を受け持つ。
///
/// 差分を「出すかどうか」は表示モード（`ViewerStore.showsDiff`）の担当、
/// 「切り替えるコマンド」はメニューアクションの担当で、ここに置くのは非同期取得と
/// その世代管理（開始時に捨てる / 着地時に一致確認する）だけ。
@MainActor
final class ViewerDiffPresenter {
    /// 差分の取得元。全ウィンドウで 1 個を共有する（生成元は ViewerWindowManager 一箇所）。
    /// 機能が無効なビルドでは nil で、git diff を一切実行しない。
    private let loader: GitDiffLoader?
    /// git 追跡ファイルの索引。リポジトリルートの解決に使う。
    private let gitFileIndex: any GitFileIndexing
    /// 差分本文の書き戻し先。
    private let store: ViewerStore
    /// 差分のレイアウト設定。全ウィンドウ共有（差分を出すかどうかは store の表示モードが持つ）。
    let displayPreference: DiffDisplayPreference
    /// 差分を取る対象。切替・リネームで変化するため都度参照する
    /// （`WebViewCommandController` と同じく、ウィンドウ側を弱参照で捕捉したクロージャで受ける。
    /// プロトコルにするとウィンドウコントローラの準拠がもう 1 つ増える）。
    private let currentURL: () -> URL?
    /// いま何ができるか。差分の種別ゲート（ADR 0002 段 2）もここから引く。
    private let capabilities: () -> ViewerCapabilities

    /// 直近の `refresh()` が起こした「取得結果を store へ書き戻すタスク」。
    ///
    /// 反映の完了はこれ以外に観測点が無い（`GitDiffLoader` が返す Task は取得までで、
    /// `store.diffContent` への書き戻しはこの後段）。捨てると、テストは結果をポーリングで
    /// 待つしかなくなり、取得が detached の utility タスクを通る都合で全スイート並列実行では
    /// 待機予算に達して落ちる（TASK-437）。
    private(set) var refreshTask: Task<Void, Never>?

    init(
        loader: GitDiffLoader?,
        gitFileIndex: any GitFileIndexing,
        store: ViewerStore,
        displayPreference: DiffDisplayPreference,
        currentURL: @escaping () -> URL?,
        capabilities: @escaping () -> ViewerCapabilities
    ) {
        self.loader = loader
        self.gitFileIndex = gitFileIndex
        self.store = store
        self.displayPreference = displayPreference
        self.currentURL = currentURL
        self.capabilities = capabilities
    }

    /// 差分表示モードかどうか（メニューのチェック表示に使う）。
    var isDiffShown: Bool {
        store.showsDiff
    }

    /// 差分レイアウトが左右分割かどうか（メニューのチェック表示に使う）。
    var isLayoutSideBySide: Bool {
        displayPreference.layout == .sideBySide
    }

    /// レイアウトをインラインと左右分割で往復する。
    /// レイアウトはアプリ全体で共有する好みの設定なので、差分表示中の全ウィンドウへ反映される
    /// （`DiffDisplayPreference` が `@Observable` で 1 個を共有しているため自動）。
    func toggleLayout() {
        displayPreference.layout = displayPreference.layout == .sideBySide ? .inline : .sideBySide
    }

    /// 表示中ファイルの差分を取り直して store へ反映する。
    ///
    /// 取得は非同期のため、戻ってきた時点で表示対象が変わっていないかを URL で確認する
    /// （遅れて着地した結果が現在の表示を壊すのを防ぐ）。切替時に古い差分を捨てる側は
    /// `ViewerStore.openFile` が担う（着地時の確認だけでは切替直後の残留を防げない）。
    ///
    /// リポジトリルートの解決はクロージャで `GitDiffLoader` へ渡し、差分取得と同じ
    /// detached タスクの中で行わせる。キャッシュに無いディレクトリではリポジトリを開いて
    /// 走査するため、メインアクター上で同期に呼ぶとコンテンツ再読込のたびに
    /// UI が止まりうる（遅いボリュームでは特に）。
    /// ここで解決を待ってからローダーを呼ぶ形へ戻すと、登録が契機のターンから外れて
    /// 兄弟要求が合流できなくなる（TASK-346）。
    /// 差分を出せない種別（画像・PDF・文書を出していない状態）では差分取得を起こさない。
    /// 表示側（ViewerContentView）が捨てるだけでは、契機の数だけ取得が走る。
    func refresh() {
        guard let loader, let url = currentURL(), isDiffShown, capabilities().canSelectDiffMode else {
            store.diffContent = .unavailable
            // 取得を起こさなかった契機で直前のタスクを残すと、待つ側が古い取得の完了を
            // 「この契機の完了」と取り違える。
            refreshTask = nil
            return
        }
        let directory = url.deletingLastPathComponent()
        let index = gitFileIndex
        // 取得の登録は契機のここで**同期に**行う。await を挟んだ後に登録すると、同じ
        // ファイル変更イベントから出た他ウィンドウの要求が別のターンへ散り、合流できずに
        // 窓の数だけ git が起動する（TASK-325 / TASK-346）。ルート解決はローダーが
        // 取得タスクの中（メインアクターの外）で行う。
        let fetch = loader.diff(forFileAt: url) { index.repositoryRoot(forDirectoryAt: directory) }
        // 取得を実際に起こした契機で「未確定」を立てる(未確定の間、レンダラは
        // モード切替だけの再描画を見送って前の表示を残す = TASK-407)。ただし確定差分を
        // 表示中の取り直し(保存などによる再取得)では降格しない — 従来どおり古い差分を
        // 出したまま着地を待つ(降格すると差分ハイライトが 1 サイクル消える)。
        if case .diff = store.diffContent {} else { store.diffContent = .pending }
        // 反映タスクは保持する。取得完了はここでしか観測できないため、捨てると呼び出し側
        // （テスト）は `store.diffContent` をポーリングで待つしかなくなる（TASK-437）。
        refreshTask = Task { @MainActor [weak self] in
            let result = await fetch.value
            // 取得中に OFF へ切り替わっていたら書き戻さない。表示は ViewerContentView の
            // ゲートで隠れるが、store.diffContent に古い本文が残ると次に ON にした瞬間だけ
            // 取り直し前の差分が見える。未確定(.pending)の解消は、この 3 つの bail 経路の
            // いずれでも別の書き手(モード離脱の applyDisplayMode / 切替の openFile)が先行する。
            guard let self, currentURL() == url, isDiffShown else { return }
            store.diffContent = Self.displayableDiff(result)
        }
    }

    /// 取得結果のうち、差分として描けるのは本文があるものだけ。
    /// それ以外（未追跡・バイナリ・変更なし・大きすぎる・取得できない）は `.unavailable` にして
    /// 通常のソース表示へ戻す。理由ごとの表示分けは行わない（TASK-315 の次段）。
    static func displayableDiff(_ result: GitFileDiff?) -> ViewerDiffContent {
        guard case let .diff(text) = result else { return .unavailable }
        return .diff(text)
    }
}
