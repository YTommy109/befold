import Foundation

/// サイドバーのフォルダー移動(navigateToFolder とその補助)。
/// SidebarNavigator 本体から分けているのは、swiftlint の file_length を超えないようにするため
/// (SidebarNavigator+History / +SelectionMemory / +Expansion と同じ理由)。
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
        rememberSelection(in: previous)
        fileListModel.currentDirectory = url
        updateRootDirectory(with: target)
        // ルートが変わると、それまでの展開は別のツリーのものになる。走行中の子リスト取得も
        // ここで無効化する(着地させると、新しいルートの行配列へ前のツリーの子が混ざる)。
        expansion.invalidateAll()
        performListing(of: url) { host, directory, rootRows in
            self.applyRows(rootRows, for: directory)
            let isGoingUp = target.normalizedPathKey == previous.deletingLastPathComponent()
                .normalizedPathKey
            if let remembered = self.rememberedSelectionURL(in: directory) {
                self.select(remembered, presentingWith: host)
            } else if isGoingUp {
                self.fileListModel.selection = self.folderEntryURL(forKey: previous.normalizedPathKey)
            } else {
                self.select(self.fileListModel.firstSelectableEntryURL, presentingWith: host)
            }
            self.recordHistory()
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
