import Foundation

/// サイドバーのフォルダー移動(navigateToFolder とその補助)。
/// 本体(SidebarNavigator.swift)から分けているのは file_length を超えないため。
///
/// 選択記憶(TASK-309)の 2 つのヘルパーは本体側にある。`selectionMemory` を
/// `private` にするには、それを触るコードが stored property と同じファイルに
/// 無ければならない(Swift の `private` はファイルスコープ)ため。
@MainActor
extension SidebarNavigator {
    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    /// 列挙はメイン外で行い、完了後にメインアクターへ一括反映する(呼び出し自体は非 async)。
    ///
    /// 下位・横へ移動したときは一覧の先頭行を選ぶ(TASK-310)。プレビューは選択に追従するので、
    /// 先頭がファイルならその中身、フォルダーならそのフォルダーの一覧が出る。
    /// **選択を書くだけでは追従しない**ことに注意する。previewTarget が `.file` になっても
    /// ViewerWebView が出すのは ViewerStore が保持している「前に開いていたファイル」であり、
    /// ハイライトだけが動いて中身が変わらない。先頭がファイルのときは切替まで行うこと。
    func navigateToFolder(_ url: URL) {
        guard host != nil else { return }
        let target = url.standardizedFileURL
        guard DirectoryLister.isWithinHome(target) else { return }
        let previous = fileListModel.currentDirectory
        moveCurrentDirectory(to: url)
        performListing(of: url) { host, directory, listing in
            self.applyRows(listing, for: directory)
            let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
                .normalizedPathKey
            if let remembered = self.rememberedSelectionURL(in: directory) {
                self.select(remembered, presentingWith: host)
            } else if isGoingUp {
                self.fileListModel.selection = self.fileListModel.folderEntryURL(forKey: previous.normalizedPathKey)
            } else {
                self.select(self.fileListModel.firstSelectableEntryURL, presentingWith: host)
            }
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
    /// 直接 `currentDirectory` へ代入しないこと。かつて `syncAfterSwitch` が代入だけを
    /// 行い、この後始末を素通りしていた。
    func moveCurrentDirectory(to url: URL) {
        rememberSelection(in: fileListModel.currentDirectory)
        fileListModel.currentDirectory = url
        updateRootDirectory(with: url.standardizedFileURL)
        discardExpansion()
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
