import AppKit
import BefoldKit

/// 「最近使ったリポジトリ」の記録。ウィンドウを開いた時点でのルート解決と、
/// アクティブ化・クローズ・アプリ終了に伴うタブ構成の更新をまとめる。
extension ViewerWindowManager {
    /// url が git リポジトリ内なら「最近使ったリポジトリ」に記録し、ウィンドウへ
    /// ルートをキャッシュする(ウィンドウを閉じる際に再度 git を呼ばずに済ませるため)。
    ///
    /// ルート解決とラベル解決はどちらも git の subprocess を待ち、しかも
    /// GitCommandFileIndex の共有ロックの内側で直列化される。MainActor で同期実行すると
    /// ウィンドウを開くたびに UI が止まるため、解決は detached タスクで行い、結果の反映だけ
    /// MainActor へ戻す(SidebarNavigator の resolveGitRoot と同じ方針)。
    /// 解決が終わる前にウィンドウが閉じられた場合、そのウィンドウ分の記録は行われない
    /// (履歴が1件増えないだけで、次に開いたときに記録されるため許容する)。
    func recordRecentRepositoryIfNeeded(for url: URL, controller: ViewerWindowController) {
        let gitFileIndex = gitFileIndex
        let resolveIdentity = repositoryIdentityResolver
        Task.detached { [weak self, weak controller] in
            guard let root = gitFileIndex.repositoryRoot(forFileAt: url) else { return }
            let identity = resolveIdentity(root)
            await self?.applyRecentRepository(root: root, identity: identity, to: controller)
        }
    }

    /// detached タスクで解決した git ルート/identity を MainActor 上で反映する。
    /// ウィンドウが既に閉じられていれば(controller == nil)何もしない。
    /// mainRoot は worktree のときだけ渡す(本体そのものなら nil。RecentRepositoryEntry の規約)。
    private func applyRecentRepository(
        root: URL, identity: RepositoryIdentity, to controller: ViewerWindowController?
    ) {
        guard let controller else { return }
        controller.repositoryRoot = root
        let isMainRepository = identity.mainRoot.normalizedPathKey == root.normalizedPathKey
        recentRepositoriesStore.record(
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
    func recordRecentRepositoryTabGroup(
        of controller: ViewerWindowController, force: Bool = false
    ) {
        guard let root = controller.repositoryRoot, let window = controller.window,
              let group = tabGroup(of: window)
        else { return }
        recentRepositoriesStore.updateLastTabGroup(root: root, group, force: force)
    }

    /// 開いている全ウィンドウの現在のタブ構成を「最近使ったリポジトリ」へ記録する。
    /// アプリ終了時に呼ぶ。終了では windowWillClose が発火しないことがあり、
    /// close 経路だけではタブ構成を取りこぼす。終了時点の構成を正として force 付きで
    /// 上書きする(ユーザーが意図的にタブを減らした結果は、セッション中の
    /// 縮小拒否を通り抜けられるこの経路でしか反映できない)。
    func recordAllRecentRepositoryTabGroups() {
        for controller in allControllers {
            recordRecentRepositoryTabGroup(of: controller, force: true)
        }
    }
}
