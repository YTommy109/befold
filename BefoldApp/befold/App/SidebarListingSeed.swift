import Foundation

/// 別の窓が列挙済みのサイドバー一覧を、新しい窓の出発点として引き継ぐための束(TASK-532)。
///
/// 新しい窓のサイドバーは空の一覧で作られ、取り付け直後の非同期列挙で埋まる
/// (`ViewerWindowAssembler.makeSidebarNavigator` の doc)。同じフォルダのファイルを
/// Cmd+クリックで新規タブに開くと、元タブが同じ一覧を出しているのに新しいタブは必ず
/// 「空 → 列挙 → 描画」の 2 段階を通り、サイドバーが一瞬空になる。
///
/// **運ぶのは行ではなく材料**(`DirectoryListing`)。行は窓ごとの展開状態を当てて作る
/// もので、元タブの展開を写すと新しい窓の展開状態と食い違う(`SidebarTreePresenter`)。
/// 材料を渡して新しい窓自身に畳ませれば、その窓が自分で列挙したときと同じ行になる——
/// だからこの引き継ぎの直後に走る取り直しは同じ結果を返し、
/// `SidebarTreePresenter.applyRows` のガードが反映ごと畳む。
///
/// **列挙の入力が一致する窓の間でだけ引き継ぐ。** 並び順・不可視ファイルの表示は窓ごとの
/// ライブ値(ADR 0002)なので、元タブが不可視ファイルを出していて新しい窓が出さない場合に
/// 素通しすると、取り直しが着地するまでの間だけ嘘の一覧が出る。判定は `canApply(to:)`。
struct SidebarListingSeed {
    /// `listing` を列挙したディレクトリ。
    let directory: URL
    /// 行に畳む前の列挙結果。
    let listing: DirectoryListing
    /// 元の窓の並び順(列挙の入力)。
    let sortOrder: SortOrder
    /// 元の窓が不可視ファイルを出していたか(列挙の入力)。
    let showHiddenFiles: Bool

    /// `model` を持つ窓へ引き継いでよいか。
    ///
    /// - 同じディレクトリを列挙した結果であること(違えば単に別の一覧)
    /// - 列挙の入力(並び順・不可視ファイル)が一致すること
    /// - 列挙に失敗した結果でないこと。失敗は「読めなかった」という事実で、これを
    ///   引き継ぐと新しい窓が自分では試していないのに失敗表示から始まる(TASK-410)
    /// - 引き継ぎ先がまだ一覧を持っていないこと(出発点の差し替えなので、既に自分で
    ///   列挙し終えた窓へ後から当ててはならない)
    @MainActor
    func canApply(to model: FileListModel) -> Bool {
        !listing.didFailEnumeration
            && !model.hasLoadedEntries
            && directory.normalizedPathKey == model.currentDirectory.normalizedPathKey
            && sortOrder == model.sortOrder
            && showHiddenFiles == model.showHiddenFiles
    }
}
