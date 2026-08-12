import Foundation

/// プレビュー内のフォルダー一覧(`FolderListingView`)が、サイドバーの揃えた一覧を使うのか
/// 自前で列挙するのかを決める解決器(TASK-443)。
///
/// 判断材料を stored 値として引数で受け、状態を持たない。`PreviewTargetResolver` と同じ形で、
/// サイドバーの分岐(TASK-293 / 295 / 298 / 301)を `FileListModel` 抜きで測れるようにする。
enum FolderListingSourceResolver {
    /// 判断材料。`FileListModel` の stored 値をそのまま写した入れ物で、判断そのものは持たない。
    struct Listing {
        /// サイドバーがいま見ているディレクトリ(移動要求で先に進む側)。
        let currentDirectory: URL
        /// 手元の一覧を列挙したディレクトリ。突き合わせはこちらで行う(TASK-293)。
        let entriesDirectory: URL
        /// 一覧が一度でも反映されたか。
        let hasLoadedEntries: Bool
        /// git 変更のみ表示が有効か。一覧が届くまでの待ち方がこれで分かれる。
        let showChangedFilesOnly: Bool
        /// 手元の一覧の列挙に失敗したか(TASK-410)。
        let didFailListing: Bool
    }

    /// 表示中ディレクトリを見ているときは、サイドバーが git 状態と一緒に揃えた一覧を
    /// そのまま使わせる。プレビューが自前で列挙すると完了順が揃わず、絞り込みが効く前の
    /// 全件が一瞬描画される(TASK-293)。選択中のサブフォルダーを見ているときは手元に
    /// その一覧が無いので自前で列挙させる(そちらは git 状態の対象外で絞り込み自体が働かない)。
    ///
    /// 表示中ディレクトリの一覧がまだ届いていない間(移動要求で currentDirectory だけが
    /// 先に進んでいる間)の扱いは、**git 絞り込みが ON かどうか**で分かれる。
    ///
    /// - ON: `.shared(nil)` を返して待たせる。自前で列挙させると git 状態と対になっていない
    ///   全件が一瞬描画される(TASK-293 の回帰)。
    /// - OFF: `.ownListing` を返してその場で列挙させる。対にすべき git 状態が無いので待つ
    ///   理由がなく、待たせると移動直後にプレビューが空へ落ちる(TASK-295)。
    ///
    /// ビュー側で「古い自前列挙を出し続ける」形にすると、待つべき場面でも全件が出てしまい、
    /// 列挙し直さないため削除済みのファイルも残る(TASK-301)。判断材料をここに置く。
    ///
    /// - Parameter filteredRows: 絞り込みだけを適用した一覧(`FileListSnapshot.filtered`)。
    ///   祖先を足し戻す**前**の配列を渡すこと。足し戻した配列だと、条件に一致しないフォルダが
    ///   プレビューにも現れる一方、同じフォルダを自前列挙する経路では消えるため、
    ///   1 ウィンドウ内に絞り込みの答えが 2 つ並ぶ(TASK-288 の巻き戻し)。
    ///   評価は共有一覧を返すと決まったあとで済むよう、遅延で受け取る。
    static func resolve(
        for directory: URL,
        in listing: Listing,
        filteredRows: () -> [FileListEntry]
    ) -> FolderListingSource {
        let key = directory.normalizedPathKey
        guard key == listing.currentDirectory.normalizedPathKey else { return .ownListing }
        guard listing.hasLoadedEntries, key == listing.entriesDirectory.normalizedPathKey else {
            return listing.showChangedFilesOnly ? .shared(nil) : .ownListing
        }
        // **depth 0 の行だけを渡す**。プレビューが見せるのは `directory` 直下であって、
        // サイドバーで展開したその配下ではない。ツリー展開が入ると visible には孫以降の行が
        // 混ざるため(TASK-361.1)、そのまま渡すと「このフォルダーの中身」として別階層の
        // ファイルが並ぶ。ドリルダウンでは全行 depth 0 なので素通し。
        //
        // 絞り込み済みの一覧を渡すので、FolderListingView 側はこれを再度 filter.apply に
        // 通さない(FolderListingView.visibleEntries を参照。TASK-298)。
        return .shared(SharedFolderListing(
            entries: filteredRows().filter { $0.depth == 0 },
            didFailEnumeration: listing.didFailListing
        ))
    }
}
