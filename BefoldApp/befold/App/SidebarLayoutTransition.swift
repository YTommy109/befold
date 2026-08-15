import Foundation

/// サイドバーのツリー⇄リスト切り替えに伴う遷移方針(TASK-481)。
///
/// - ツリー→リスト: 展開集合は捨てずに root を `SidebarExpansion.snapshotRoot` へ記録し、
///   選択の親フォルダーへカレントを移す(未選択なら動かさない)。
/// - リスト→ツリー: カレントが記録 root の配下なら root へ戻して展開を復元し、
///   現在の選択までの経路を追加展開する。配下でなければ展開ごと捨てて、
///   いまのカレントを新しいルートにする(元の場所へ引き戻さない)。
///
/// ライブ値の更新・既定値の書き戻し・行の組み直しは従来どおり
/// `SidebarListingCoordinator.applyDisplayChange(_:)` に任せ、この型はその前後に置く
/// 「カレントの移動・スナップショットの記録と復元・経路の展開」だけを持つ。
/// `SidebarNavigator` から分けているのは責務(切り替えの遷移方針)による。
///
/// 生成は `SidebarNavigator.init` の内側だけ(注入引数にすると、渡し忘れが
/// コンパイルエラーにならず静かに別インスタンスになる / TASK-319 と同型)。
/// カレントの移動は `SidebarNavigator.moveCurrentDirectory` が唯一の経路(TASK-465)
/// なので、weak な navigator を経由して呼ぶ。
@MainActor
final class SidebarLayoutTransition {
    private let fileListModel: FileListModel
    private let tree: SidebarTreePresenter
    private let listing: SidebarListingCoordinator
    /// `moveCurrentDirectory` / `refreshFileList` / `expandFolder` の呼び出し先。
    /// navigator 自身が init でこの型を生成するため、循環を避けて weak で持つ。
    private weak var navigator: SidebarNavigator?

    init(
        fileListModel: FileListModel, tree: SidebarTreePresenter,
        listing: SidebarListingCoordinator
    ) {
        self.fileListModel = fileListModel
        self.tree = tree
        self.listing = listing
    }

    /// navigator を接続する。SidebarNavigator.attach(to:) が中継する。
    func attach(to navigator: SidebarNavigator) {
        self.navigator = navigator
    }

    /// ツリー⇄リストのトグル。`SidebarNavigator.applyDisplayChange` から
    /// `.toggleLayoutMode` のときだけ呼ばれる。
    func toggleLayoutMode() {
        if fileListModel.layoutMode == .tree {
            switchToDrillDown()
        } else {
            switchToTree()
        }
    }

    private func switchToDrillDown() {
        tree.recordSnapshotRoot(fileListModel.currentDirectory)
        // ライブ値の更新・既定値の書き戻し・行の組み直し。展開集合はここでは捨てない——
        // リスト表示は展開の材料を行へ渡さない(SidebarTreePresenter.applyRows)ので
        // 表示には出ず、ツリーへ戻るときの復元材料として温存する。
        listing.applyDisplayChange(.toggleLayoutMode)
        guard let navigator, let selection = fileListModel.selection else { return }
        let parent = selection.deletingLastPathComponent()
        guard parent.normalizedPathKey != fileListModel.currentDirectory.normalizedPathKey
        else { return }
        // 既にリスト表示なので moveCurrentDirectory は展開を捨てない。
        navigator.moveCurrentDirectory(to: parent)
        // 直前の applyDisplayChange が発行した旧カレントの列挙は世代ガードが捨てる。
        navigator.refreshFileList()
    }

    /// ライブ値の更新(`listing.applyDisplayChange`)は navigator の接続に依存させない。
    /// 依存させると、host を持たない窓(テスト・組み立て途中)でトグルがモードごと
    /// 素通りする。navigator が要るのはカレントの移動と経路の展開だけで、
    /// 未接続ならその 2 つだけを諦める。
    private func switchToTree() {
        guard let root = tree.snapshotRoot,
              tree.snapshotRootCovers(fileListModel.currentDirectory)
        else {
            // root の外へ出ていた。いまの場所を新しいルートにする(元へ引き戻さない)。
            // 温存していた展開は別ツリーのものなので snapshot ごと捨てる(invalidateAll)。
            tree.invalidateExpansion()
            listing.applyDisplayChange(.toggleLayoutMode)
            return
        }
        let currentKey = fileListModel.currentDirectory.normalizedPathKey
        if let navigator, root.normalizedPathKey != currentKey {
            // まだリスト表示のうちに移す(ツリーへ切り替えた後だと展開が捨てられる)。
            navigator.moveCurrentDirectory(to: root)
        }
        tree.clearSnapshotRoot()
        listing.applyDisplayChange(.toggleLayoutMode)
        revealSelection(under: root)
    }

    /// 現在の選択までの祖先フォルダーを展開し、選択行が現れたら可視になるよう
    /// スクロールを要求する。展開はルートの一覧が着地してから始める
    /// (先に始めると、着地した子リストが古い一覧材料で行を組み直す窓がある)。
    private func revealSelection(under root: URL) {
        guard let navigator, let selection = fileListModel.selection else { return }
        var ancestors: [URL] = []
        var directory = selection.deletingLastPathComponent()
        let rootKey = root.normalizedPathKey
        while directory.normalizedPathKey != rootKey {
            // root の配下に無い選択(別ツリーの残骸)は開かない。
            guard directory.path != "/" else { return }
            ancestors.append(directory)
            directory = directory.deletingLastPathComponent()
        }
        guard !ancestors.isEmpty else { return }
        navigator.refreshFileList(applyCustomSelection: { [weak self] in
            guard let self, let navigator = self.navigator else { return false }
            for ancestor in ancestors.reversed() {
                navigator.expandFolder(ancestor.normalizedPathKey, at: ancestor)
            }
            // 選択は変えず、書き込み点を通し直してスクロール要求だけを積む。行が
            // まだ無ければ子リストの着地時に再試行される(SidebarTableFocuser)。
            fileListModel.selection = fileListModel.selection
            // 復元中の選択(root 一覧にはまだ無い深い行)を既定の選択維持へ通すと
            // currentFileURL へ引き戻されるため、ここで確定させる。
            return true
        })
    }
}
