import Foundation

/// サイドバーのフォルダー移動(navigateToFolder とその補助)。
/// 本体(SidebarNavigator.swift)から分けているのは file_length を超えないため。
@MainActor
extension SidebarNavigator {
    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    /// 列挙はメイン外で行い、完了後にメインアクターへ一括反映する(呼び出し自体は非 async)。
    ///
    /// 移動先の本文には、そのフォルダーの一覧を出す(ADR 0013 決定 5)。かつては記憶した
    /// 選択や先頭行を自動で選び、ファイルを開いたり空タブを置き換えたりしていた(TASK-309 /
    /// TASK-310)。選択は付けない——本文が出しているのはフォルダー自身で、その一覧に行は無い。
    ///
    /// **本文の意図はこの型が書かない**(ADR 0013)。書く口は呼び出し側の窓が持ち、ここは
    /// 移動が決まった時点で `presentingFolder` に渡すだけ。一覧の着地は待たない
    /// (待つと、遅い列挙の間は本文が前のファイルのまま残る)。
    ///
    /// - Parameter presentingFolder: 移動が決まったときに呼ぶ。履歴の記録(着地時)より
    ///   先になる(記録は窓の意図を読む)。
    func navigateToFolder(_ url: URL, presentingFolder: @escaping (URL) -> Void) {
        guard host != nil else { return }
        guard DirectoryLister.isWithinHome(url.standardizedFileURL, home: home) else { return }
        moveCurrentDirectory(to: url)
        fileListModel.selection = nil
        presentingFolder(url)
        performListing(of: url) { _, directory, listing in
            self.applyRows(listing, for: directory)
            self.recordHistory()
        }
    }

    /// **`fileListModel.currentDirectory` を書き換える唯一の経路**(TASK-465)。
    ///
    /// 表示中フォルダーを動かすときに必ず要る後始末——rootDirectory の更新・展開の破棄——を
    /// ここに畳んでいる。ルートが変わると、それまでの展開は別の
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
        fileListModel.currentDirectory = url
        updateRootDirectory(with: url.standardizedFileURL)
        if fileListModel.display.layoutMode == .tree {
            discardExpansion()
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
