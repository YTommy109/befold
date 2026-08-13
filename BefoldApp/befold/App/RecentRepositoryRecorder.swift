import AppKit
import BefoldKit

/// 「最近使ったリポジトリ」の記録役。ウィンドウを開いた時点でのルート解決と、
/// アクティブ化・クローズ・アプリ終了に伴うタブ構成の更新をまとめる。
///
/// 知っているのは `RecentRepositoryEntry` の規約(本体リポジトリなら mainRoot は nil)と、
/// タブ構成を観測できるのはウィンドウが生きている間だけという AppKit の癖。
/// 開いているウィンドウの管理台帳は知らず、記録対象は必ず引数で受け取る。
///
/// この型は `ViewerWindowManager` の init が自身の stored property から組み立てる。
/// 外から組み立てて渡す形にしないのは、`gitFileIndex` が「アプリ全体で 1 つ」の共有索引で、
/// 別インスタンスを渡せる余地を残すと `git ls-files` と照合索引が二重化するため
/// (デフォルト引数による静かな別インスタンス化: TASK-319)。
@MainActor
final class RecentRepositoryRecorder {
    private let store: RecentRepositoriesStore
    private let gitFileIndex: any GitFileIndexing
    /// root からメニュー表示用ラベルと本体リポジトリのルートを解決する。
    /// 解決は MainActor の外(detached タスク)で走るため @Sendable が要る。
    private let resolveIdentity: @Sendable (URL) -> RepositoryIdentity
    /// 新しい本体ルートを記録した直後に呼ばれる。AppDelegate が WorktreeCatalog を
    /// 追随させるために使う。
    private let onRepositoryRecorded: (URL) -> Void

    init(
        store: RecentRepositoriesStore,
        gitFileIndex: any GitFileIndexing,
        resolveIdentity: @escaping @Sendable (URL) -> RepositoryIdentity,
        onRepositoryRecorded: @escaping (URL) -> Void
    ) {
        self.store = store
        self.gitFileIndex = gitFileIndex
        self.resolveIdentity = resolveIdentity
        self.onRepositoryRecorded = onRepositoryRecorded
    }

    /// url が git リポジトリ内なら「最近使ったリポジトリ」に記録し、ウィンドウへ
    /// ルートをキャッシュする(ウィンドウを閉じる際に再度 git を呼ばずに済ませるため)。
    ///
    /// ルート解決とラベル解決はどちらも git の subprocess を待ち、しかも
    /// GitCommandFileIndex の共有ロックの内側で直列化される。MainActor で同期実行すると
    /// ウィンドウを開くたびに UI が止まるため、解決は detached タスクで行い、結果の反映だけ
    /// MainActor へ戻す(SidebarNavigator の resolveGitRoot と同じ方針)。
    /// 解決が終わる前にウィンドウが閉じられた場合、そのウィンドウ分の記録は行われない
    /// (履歴が1件増えないだけで、次に開いたときに記録されるため許容する)。
    /// 解決の着地前にウィンドウが別ファイルへ切り替わった場合も同様に何もしない
    /// (切替前のリポジトリを現在のリポジトリとして書き込まないため。TASK-461)。
    func recordIfNeeded(for url: URL, controller: ViewerWindowController) {
        let gitFileIndex = gitFileIndex
        let resolveIdentity = resolveIdentity
        Task.detached { [weak self, weak controller] in
            guard let root = gitFileIndex.repositoryRoot(forFileAt: url) else { return }
            let identity = resolveIdentity(root)
            await self?.apply(root: root, identity: identity, to: controller, resolvedFor: url)
        }
    }

    /// detached タスクで解決した git ルート/identity を MainActor 上で反映する。
    /// ウィンドウが既に閉じられていれば(controller == nil)何もしない。
    /// 解決を開始した対象(resolvedFor)とウィンドウの現在の表示対象が一致しない場合も
    /// 何もしない(解決中に別リポジトリのファイルへ切り替わった結果を、切替前の
    /// リポジトリとして書き込まないため)。
    /// mainRoot は worktree のときだけ渡す(本体そのものなら nil。RecentRepositoryEntry の規約)。
    private func apply(
        root: URL, identity: RepositoryIdentity, to controller: ViewerWindowController?,
        resolvedFor url: URL
    ) {
        guard let controller else { return }
        guard controller.fileURL.normalizedPathKey == url.normalizedPathKey else { return }
        controller.repositoryRoot = root
        let isMainRepository = identity.mainRoot.normalizedPathKey == root.normalizedPathKey
        store.record(
            root: root, label: identity.label, mainRoot: isMainRepository ? nil : identity.mainRoot
        )
        onRepositoryRecorded(identity.mainRoot)
    }

    /// controller のウィンドウ(自身のタブグループ)の構成を「最近使ったリポジトリ」へ記録する。
    ///
    /// タブ構成を正しく観測できるのはウィンドウが生きている間だけである。
    /// windowWillClose の時点では AppKit が既にそのウィンドウをタブグループから外していて
    /// (`window.tabGroup == nil`)、閉じる1枚分しか組み立てられない。そのため
    /// アクティブ化のたびに現在の構成を記録し、close 時に届く縮小した構成は
    /// updateLastTabGroup の部分集合拒否で捨てる。
    func recordTabGroup(of controller: ViewerWindowController, force: Bool = false) {
        guard let root = controller.repositoryRoot, let window = controller.window,
              let group = ViewerTabGrouping.tabGroup(of: window)
        else { return }
        store.updateLastTabGroup(root: root, group, force: force)
    }

    /// 渡された全ウィンドウの現在のタブ構成を「最近使ったリポジトリ」へ記録する。
    /// アプリ終了時に呼ぶ。終了では windowWillClose が発火しないことがあり、
    /// close 経路だけではタブ構成を取りこぼす。終了時点の構成を正として force 付きで
    /// 上書きする(ユーザーが意図的にタブを減らした結果は、セッション中の
    /// 縮小拒否を通り抜けられるこの経路でしか反映できない)。
    func recordAllTabGroups(of controllers: [ViewerWindowController]) {
        for controller in controllers {
            recordTabGroup(of: controller, force: true)
        }
    }
}
