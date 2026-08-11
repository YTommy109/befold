import Foundation

/// サイドバーのツリー展開まわり(TASK-361.3)。SidebarNavigator 本体から分けているのは、
/// swiftlint の file_length / type_body_length を超えないようにするため
/// (SidebarNavigator+History / +SelectionMemory と同じ理由)。
///
/// ここのメソッドが `private` ではなく internal なのは、Swift の `private` が
/// ファイルスコープで、別ファイルの extension から参照できないため。
/// SidebarNavigator の外から呼んでよいのは `expandFolder` / `collapseFolder` だけ。
@MainActor
extension SidebarNavigator {
    // MARK: - Tree Expansion

    /// ルートの一覧(親移動行を含む畳んだ形)と展開の材料から行配列を組み立て、
    /// `fileListModel` へ反映して**反映した行**を返す。
    ///
    /// `SidebarRowBuilder.rows` を呼ぶのはサイドバーではここ 1 箇所だけ。呼び出し元が
    /// それぞれ畳むと、展開の材料を渡し忘れた経路がドリルダウンのまま残る。
    /// 呼び出し元は戻り値を使って選択維持を判定すること(ルート直下だけを見ると、
    /// 展開したサブフォルダ内のファイルを選んでいる間ずっと選択が飛ぶ)。
    @discardableResult
    func applyRows(_ rootListing: DirectoryListing, for directory: URL) -> [FileListEntry] {
        let material = expansion.material
        // ルートの一覧は畳んだ形で届く。親移動行は種別で確実に分けられる
        // (ホームの外では出ないため「先頭が必ず `..`」とは限らない)。
        let parentEntry = rootListing.entries.first { $0.kind == .parentNavigation }
        let rootChildren = rootListing.entries.filter { $0.kind != .parentNavigation }
        let isTree = fileListModel.layoutMode == .tree
        let rows = SidebarRowBuilder.rows(
            parentEntry: parentEntry,
            rootChildren: rootChildren,
            // ドリルダウン表示では展開の材料を渡さない。展開状態が残っていても
            // 行は 1 階層ぶんに戻る(モードを戻したのにツリーのままになるのを防ぐ)。
            expanded: isTree ? material.expanded : [],
            childrenByPathKey: isTree ? material.childrenByPathKey : [:],
            loading: isTree ? material.loading : [],
            failed: isTree ? material.failed : [],
            showsDisclosure: isTree
        )
        fileListModel.setEntries(rootListing.replacingEntries(rows), for: directory)
        return rows
    }

    /// 手元の展開の材料だけで行を組み直す。子リストが届いたときに呼ぶ。
    /// ルートを列挙し直さないので、展開のたびにルートの再列挙は起きない。
    func rebuildRows() {
        applyRows(fileListModel.listing.filteringEntries { $0.depth == 0 }, for: fileListModel.entriesDirectory)
    }

    /// フォルダを展開する。既に展開済みなら何もしない(再列挙しない)。
    /// 列挙は `childrenLister`(nonisolated async)が行うため、MainActor 上では列挙しない。
    func expandFolder(_ key: String, at url: URL) {
        guard let token = expansion.beginExpanding(key) else { return }
        loadChildren(for: token, at: url)
    }

    /// フォルダを畳む。配下の展開も一緒に捨てる(SidebarExpansion.collapse を参照)。
    func collapseFolder(_ key: String) {
        expansion.collapse(key)
        rebuildRows()
    }

    /// 展開中フォルダの子リストを、現在の並び順・隠しファイル設定で取り直す。
    /// 取り直さないと、展開中のサブツリーだけが古い規則で並び続ける。
    ///
    /// ここで行を組み直してはならない。この関数はルートの列挙を**発行する前**に呼ばれ、
    /// そのルートの一覧はまだ届いていない。組み直すと手元の古い行で `setEntries` が走り、
    /// 一覧の到着前に `hasLoadedEntries` が立って「対象が確定していない」状態が失われる
    /// (previewTarget が .undetermined を返せなくなる)。行はルートの一覧が届いた時点と、
    /// 子リストが届いた時点(loadChildren)で組み直す。
    func reloadExpandedChildren() {
        for token in expansion.invalidateChildren() {
            guard let url = folderEntryURL(forKey: token.key) else { continue }
            loadChildren(for: token, at: url)
        }
    }

    func loadChildren(for token: SidebarExpansion.ExpansionToken, at url: URL) {
        let sortOrder = fileListModel.sortOrder
        let showHiddenFiles = fileListModel.showHiddenFiles
        Task {
            let children = await self.childrenLister(url, sortOrder, showHiddenFiles)
            self.expansion.apply(children, for: token)
            self.rebuildRows()
        }
    }
}
