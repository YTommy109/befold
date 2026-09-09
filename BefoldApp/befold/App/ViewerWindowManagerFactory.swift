import BefoldKit
import Foundation

/// `ViewerWindowManager` の合成点。共有ストアの配線と `GitStatusStore` の後差しを
/// ここ 1 箇所に閉じる(TASK-604.3 で `AppDelegate` から切り出した)。
///
/// `AppStores` は「ストアの束」であって組み立て役ではないため、そちらへは置かない。
@MainActor
enum ViewerWindowManagerFactory {
    static func make(stores: AppStores) -> ViewerWindowManager {
        let windowManager = ViewerWindowManager(
            sessionStore: stores.sessionStore,
            recentDocumentsStore: stores.recentDocumentsStore,
            displayDefaults: stores.displayDefaults,
            diffDisplayPreference: stores.diffDisplayPreference,
            findOptionsPreference: stores.findOptionsPreference,
            headingJumpLevelDefaults: stores.headingJumpLevelDefaults,
            codeFontPreference: stores.codeFontPreference,
            csvNumberFormatPreference: stores.csvNumberFormatPreference,
            perFileState: stores.perFileState,
            windowFrame: stores.windowFrame,
            bookmarkStore: stores.bookmarkStore,
            recentRepositoriesStore: stores.recentRepositoriesStore,
            // リポジトリを記録したら、その本体ルートの worktree 一覧も裏で解決し直しておく。
            // 次にメニューを開いた時点でキャッシュに載っていれば階層表示になる。
            onRepositoryRecorded: { [worktreeCatalog = stores.worktreeCatalog] mainRoot in
                Task { await worktreeCatalog.refresh(mainRoots: [mainRoot]) }
            }
        )
        // git 状態の取得は、ルート解決を全ウィンドウ共有の索引へ一本化する
        // (Store が独自に GitRepository を生成して rev-parse を重ねない)。
        // 索引の実体は windowManager が握っているため、生成後にここで差し込む。
        windowManager.gitStatusStore = GitStatusStore(
            resolveRepositoryRoot: { [gitFileIndex = windowManager.gitFileIndex] directory in
                gitFileIndex.repositoryRoot(forDirectoryAt: directory)
            }
        )
        return windowManager
    }
}
