import AppKit
import BefoldKit

/// アプリ全体で 1 つの表示設定を、開いている全ウィンドウへ配る一括反映。
///
/// ここが扱ってよいのは ADR 0002 の 3 分類のうち**「アプリの好み」だけ**——
/// 設定の実体はアプリに 1 つで、窓は表示を追随させるだけ、というものに限る。
/// 「文書の状態」(表示モード・拡大率)も「窓の状態」(サイドバー表示 4 値)も窓側の責務であり、
/// ここから配ってはならない。この禁止は型の依存で担保している——
/// `ViewerDisplayMode` / `ZoomStore` / `SidebarDisplayDefaults` をこの型が持たないため、
/// 違反するには「新しい依存を足す」形でしか書けない。
///
/// 同じ理由で `GitStatusStore` も持たない。実体は `ViewerWindowManager` の `var` で、
/// `AppDelegate` が init 後に差し替える(生成順の都合)。ここで値として捕まえると
/// 差し替え前の既定インスタンスを掴んだままになる。
///
/// 開いているウィンドウの管理台帳(`ViewerWindowManager.controllers`)は知らない。
/// 受け取るのは読み取り専用のスナップショット供給クロージャだけで、辞書の書き換えには
/// 到達できない。
@MainActor
final class GlobalDisplayBroadcaster {
    private let bookmarkStore: BookmarkStore
    /// 反映対象のスナップショット。呼ばれた時点で開いている全ウィンドウを返す。
    private let controllers: () -> [ViewerWindowController]

    /// - Parameters は既定値を持たせない。共有インスタンスの渡し忘れがコンパイルエラーに
    ///   ならないと、静かに別インスタンスになって「アプリ全体で 1 つ」が破れる(TASK-319)。
    init(
        bookmarkStore: BookmarkStore,
        controllers: @escaping () -> [ViewerWindowController]
    ) {
        self.bookmarkStore = bookmarkStore
        self.controllers = controllers
    }

    /// CLI の `--bookmark <path>` から転送された追加を適用し、開いている全ウィンドウの
    /// ツールバーへ即座に反映する。書き込みを GUI プロセスへ一本化する意図で
    /// AppDelegate から呼ばれる(CLIRequestForwarder 参照)。
    /// ブックマーク状態はツールバーが表示のたびに store から読み直すため、
    /// 反映は全ウィンドウの再同期で足り、変更通知の購読機構は要らない。
    func addBookmarks(for urls: [URL]) {
        for url in urls {
            bookmarkStore.add(url)
        }
        refreshAllToolbars()
    }

    /// codeFontPreference の現在値を、開いている全ウィンドウの WebView へ即座に反映する。
    /// フォント設定変更(環境設定 UI 等)から呼ばれる。
    func applyCodeFontToAllWindows() {
        for controller in controllers() {
            controller.applyCodeFontFromPreference()
        }
    }

    /// 開いている全ウィンドウのサイドバー(ファイル一覧)を再読み込みする。
    /// 全ウィンドウへ配るのはこの型を通す。窓 1 つだけの再同期が要る場合は、
    /// その窓のコントローラの API を直接呼ぶこと(ここを使うと無関係な窓まで走る)。
    func refreshAllSidebars() {
        for controller in controllers() {
            controller.sidebar.refreshFileList()
        }
    }

    /// 開いている全ウィンドウのツールバーを現在状態へ再同期する。
    /// 呼び分けの基準は refreshAllSidebars と同じ。
    func refreshAllToolbars() {
        for controller in controllers() {
            controller.refreshUIState()
        }
    }
}
