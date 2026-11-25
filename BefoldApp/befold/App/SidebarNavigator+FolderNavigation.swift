import Foundation

/// サイドバーのフォルダー移動(navigateToFolder とその補助)。
/// 本体(SidebarNavigator.swift)から分けているのは file_length を超えないため。
@MainActor
extension SidebarNavigator {
    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    /// 列挙はメイン外で行い、完了後にメインアクターへ一括反映する(呼び出し自体は非 async)。
    ///
    /// 下位・横へ移動したときは一覧の先頭行を選ぶ(TASK-310)。先頭がファイルなら切り替えて
    /// その中身を、フォルダー(または選べる行が無い)なら `presentingFolder` でフォルダー一覧を
    /// 本文に出す。**本文の意図はこの型が書かない**(ADR 0013)。書く口は呼び出し側の窓が持ち、
    /// ここは着地で決まった結果を渡すだけ。選択の書き込みは本文を動かさない。
    ///
    /// - Parameter presentingFolder: 本文にフォルダー一覧を出すと決まったときに呼ぶ。
    ///   履歴の記録より先に呼ぶ(記録は窓の意図を読む)。
    func navigateToFolder(_ url: URL, presentingFolder: @escaping (URL) -> Void) {
        guard host != nil else { return }
        let target = url.standardizedFileURL
        guard DirectoryLister.isWithinHome(target, home: home) else { return }
        let previous = fileListModel.currentDirectory
        moveCurrentDirectory(to: url)
        performListing(of: url) { host, directory, listing in
            self.applyRows(listing, for: directory)
            let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
                .normalizedPathKey
            if let remembered = self.selectionMemory.rememberedURL(in: directory) {
                self.select(remembered, presentingWith: host)
            } else if isGoingUp {
                self.fileListModel.selection = self.fileListModel.folderEntryURL(forKey: previous.normalizedPathKey)
            } else {
                self.select(self.fileListModel.firstSelectableEntryURL, presentingWith: host)
            }
            let selected = self.fileListModel.selection
                .flatMap { self.fileListModel.entry(forPathKey: $0.normalizedPathKey) }
            if selected?.kind != .file { presentingFolder(selected?.url ?? directory) }
            self.recordHistory()
        }
    }

    /// **`fileListModel.currentDirectory` を書き換える唯一の経路**(TASK-465)。
    ///
    /// 表示中フォルダーを動かすときに必ず要る後始末——移動前の選択の記憶・rootDirectory の
    /// 更新・展開の破棄——をここに畳んでいる。ルートが変わると、それまでの展開は別の
    /// ツリーのものになる。走行中の子リスト取得もここで無効化する(着地させると、新しい
    /// ルートの行配列へ前のツリーの子が混ざる)。
    ///
    /// **破棄はツリー表示中だけ。** リスト表示中の移動は展開を温存する——リスト表示は
    /// 展開を行へ出さないので別ツリーの行が混ざる形は起きず、温存した集合と
    /// snapshotRoot がツリーへ戻るときの復元材料になる(TASK-481)。
    ///
    /// 直接 `currentDirectory` へ代入しないこと。かつて `syncAfterSwitch` が代入だけを
    /// 行い、この後始末を素通りしていた。
    func moveCurrentDirectory(to url: URL) {
        selectionMemory.remember(in: fileListModel.currentDirectory)
        fileListModel.currentDirectory = url
        updateRootDirectory(with: url.standardizedFileURL)
        if fileListModel.display.layoutMode == .tree {
            discardExpansion()
        }
    }

    /// 移動先で選ぶ行を反映し、それがファイルならプレビューの中身も揃える。
    /// 切替に失敗した(ファイルが消えている)ときは選択を戻さず外し、移動先ディレクトリの
    /// 一覧を出す。存在しない行をハイライトしたまま残すより、一覧へ落ちるほうが実態に近い。
    func select(_ url: URL?, presentingWith host: SidebarNavigatorHost) {
        fileListModel.selection = url
        guard let url, fileListModel.entries.first(where: { $0.url == url })?.kind == .file
        else { return }
        if case .failed = host.performFileSwitch(to: url) {
            fileListModel.selection = nil
        }
    }

    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ(rootDirectory)を更新する。
    /// target が rootDirectory の祖先(より上位)なら、そこを新たな最上位として記録する。
    /// 既に到達した最上位より下位・並列のディレクトリへ移動しても rootDirectory は変えない。
    func updateRootDirectory(with target: URL) {
        let rootKey = fileListModel.rootDirectory.normalizedPathKey
        let targetKey = target.normalizedPathKey
        let rootComponents = rootKey.split(separator: "/")
        let targetComponents = targetKey.split(separator: "/")
        guard targetComponents.count < rootComponents.count,
              rootComponents.starts(with: targetComponents)
        else { return }
        fileListModel.rootDirectory = target
    }
}
