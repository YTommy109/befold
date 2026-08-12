import AppKit
import BefoldKit

/// メインメニューの組み立てと、動的に中身が変わるメニュー(Recent / Bookmarks /
/// 最近使ったリポジトリ)へのデータ供給。
///
/// `MainMenuBuilder` はメニューの形だけを知る純粋な組み立て役で、中身を供給する
/// `NSMenuDelegate` の生存は誰かが持つ必要がある。その保持と、供給元(各ストア)への
/// 接続をここへ集約する。
@MainActor
final class MainMenuCoordinator {
    private let stores: AppStores
    private let sessionRestorer: SessionRestorer
    private let openHandler: @MainActor (URL) -> Void
    private lazy var recentDocumentsMenuController = RecentDocumentsMenuController(
        recentURLs: { [store = stores.recentDocumentsStore] in store.recentURLs() },
        openHandler: { [openHandler] url in openHandler(url) },
        clearHandler: { [store = stores.recentDocumentsStore] in
            store.clear()
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    )
    /// 開けなくなったブックマークの一括除去。存在確認をここ(ユーザーが項目を選んだとき)へ
    /// 閉じ込めるため、BookmarksMenuController には結果のハンドラだけを渡す。
    private lazy var missingBookmarksPruner = MissingBookmarksPruner(
        bookmarkStore: stores.bookmarkStore
    )
    private lazy var bookmarksMenuController = BookmarksMenuController(
        bookmarkedURLs: { [store = stores.bookmarkStore] in store.bookmarkedURLs() },
        openHandler: { [openHandler] url in openHandler(url) },
        removeMissingHandler: { [missingBookmarksPruner] in
            Task { await missingBookmarksPruner.pruneMissingBookmarks() }
        }
    )
    private lazy var recentRepositoriesMenuController = RecentRepositoriesMenuController(
        entries: { [store = stores.recentRepositoriesStore] in store.entries() },
        worktrees: { [catalog = stores.worktreeCatalog] root in catalog.worktrees(forMainRoot: root) },
        openHandler: { [sessionRestorer] entry in
            sessionRestorer.openRepository(root: entry.root, savedTabGroup: entry.lastTabGroup)
        },
        clearHandler: { [store = stores.recentRepositoriesStore] in store.clear() }
    )

    init(
        stores: AppStores,
        sessionRestorer: SessionRestorer,
        openHandler: @escaping @MainActor (URL) -> Void
    ) {
        self.stores = stores
        self.sessionRestorer = sessionRestorer
        self.openHandler = openHandler
    }

    /// メインメニューを組み立てて `NSApp` へ設定する。起動時に 1 回だけ呼ぶ。
    func installMainMenu() {
        let mainMenu = MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpActions: MainMenuHelpActions(
                visitWebsite: #selector(AppDelegate.openHelp(_:)),
                featureOverview: #selector(AppDelegate.showFeatureOverview(_:)),
                keyboardShortcuts: #selector(AppDelegate.showKeyboardShortcuts(_:)),
                aiIntegration: #selector(AppDelegate.showAIIntegration(_:)),
                ossAcknowledgements: #selector(AppDelegate.showOSSLicenses(_:))
            ),
            recentMenuDelegate: recentDocumentsMenuController,
            bookmarksMenuDelegate: bookmarksMenuController,
            recentRepositoriesMenuDelegate: recentRepositoriesMenuController
        )
        // AppKit は mainMenu に設定した後、Close All や Start Dictation などの項目を
        // 勝手に差し込む。Help のショートカット一覧には自前で定義したものだけを載せたいので、
        // 設定する前のメニューから抽出しておく。
        MenuShortcutCatalog.snapshot = MenuShortcutCatalog.groups(from: mainMenu, appMenuTitle: "befold")
        NSApp.mainMenu = mainMenu
    }
}
