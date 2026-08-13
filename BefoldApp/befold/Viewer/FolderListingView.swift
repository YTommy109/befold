import BefoldKit
import SwiftUI

/// フォルダー一覧の供給元。表示中ディレクトリを見ているときは、サイドバー
/// (FileListModel)が git 状態と一緒に揃えた一覧をそのまま使う。自前で列挙すると
/// git 状態との完了順が揃わず、絞り込みが効く前の全件が一瞬描画される(TASK-293)。
/// プレビューへ渡す「フォルダーの中身」。**畳んだ行**と、列挙に失敗したかの組。
///
/// `DirectoryListing`(行に畳む前の材料 / TASK-442.1)とは別の型にしてある。ここへ来るのは
/// サイドバーが絞り込んで depth 0 だけにした**結果の行**であって材料ではなく、材料を
/// 渡すとプレビュー側が畳み直す第 2 の組み立て点ができる。
struct SharedFolderListing: Equatable {
    let entries: [FileListEntry]
    /// 列挙に失敗したか。空の一覧が「空だった」のか「読めなかった」のかを分ける(TASK-410)。
    let didFailEnumeration: Bool
}

enum FolderListingSource: Equatable {
    /// サイドバーと同じ一覧。nil は「このディレクトリの一覧がまだ手元に無い」。
    case shared(SharedFolderListing?)
    /// このビューが自前で列挙する。選択中のサブフォルダーを見ているときに使う。
    case ownListing

    /// `.shared` の比較は **行の同一性(id = url)だけ**で行う。プレビューが見せるのは
    /// 「このフォルダーに何が並ぶか」であって、サイドバー側のインデントや開閉三角
    /// (`FileListEntry.depth` / `.disclosure`)ではない。これらは `FileListEntry` の
    /// 等値に含まれる(サイドバーの行を描き直させるために必要)ので、ここで合成の
    /// Equatable に任せると、サイドバーの表示モードを切り替えただけでプレビューが
    /// 別の一覧に変わったと判定される。**逆向きに `FileListEntry` の等値を弱めない**
    /// (TASK-361.1 の回帰。FileListEntry の `==` の doc を参照)。
    ///
    /// **列挙の成否は比較に含める。** 行の同一性だけで比べると、読めなかった一覧と
    /// 空だった一覧はどちらも 0 行で等しくなり、「読めるようになった / 読めなくなった」の
    /// 遷移でプレビューが描き直されない(TASK-410)。
    static func == (lhs: FolderListingSource, rhs: FolderListingSource) -> Bool {
        switch (lhs, rhs) {
        case (.ownListing, .ownListing): true
        case let (.shared(lhsListing), .shared(rhsListing)):
            lhsListing?.entries.map(\.id) == rhsListing?.entries.map(\.id)
                && lhsListing?.didFailEnumeration == rhsListing?.didFailEnumeration
        default: false
        }
    }
}

/// サイドバーでフォルダーが選択された際にプレビューエリアへ表示する、
/// そのフォルダー直下の一覧。WKWebView を使わず SwiftUI の List で完結させる。
/// 隠しファイル表示・並び順・絞り込みはサイドバー(FileListModel)の現在値をそのまま渡してもらい、
/// このビュー自身は独自の設定を持たない。
struct FolderListingView: View {
    let directory: URL
    let sortOrder: SortOrder
    let showHiddenFiles: Bool
    /// サイドバーと共通の絞り込み(FileListModel.listFilter)。ディスク列挙のあとに
    /// 適用するため、`sortOrder`/`showHiddenFiles` と違い再取得のキーには含めない。
    let filter: FileListFilter
    /// 一覧の供給元。既定は自前列挙(サブフォルダーのプレビューと単体テスト)。
    var source: FolderListingSource = .ownListing
    /// いま開いているファイル。このフォルダー直下にあれば、列挙に載らない拡張子でも
    /// 一覧へ足す(DirectoryLister.appendingOpenFile)。サイドバーと同じ規則を通すため、
    /// 供給元が .shared でも .ownListing でも同じ結果になる(TASK-295)。
    var openFile: URL?
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void

    /// このビュー内だけのハイライト選択。サイドバーの選択状態(FileListModel.selection)とは
    /// 同期しない。ダブルクリックで確定した操作(onSelectFile/onNavigateToFolder)だけが
    /// サイドバー側の状態を書き換える。
    @State private var localSelection: FileListEntry.ID?
    /// ディレクトリー一覧をキャッシュ。listingKey(directory・sortOrder・showHiddenFiles)変更時に
    /// .task で非同期に再取得し、毎回の本体レンダリング時の再計算・重複呼び出しを避ける。
    /// 初期値 nil は「未取得」を表し、取得完了後に空一覧と区別する(空状態の一瞬のちらつき防止)。
    /// 「読めなかった」は空一覧ではなく `DirectoryListing.didFailEnumeration` が持つ。
    @State private var cachedListing: SharedFolderListing?

    /// .task(id:) のキー。directory だけでなく sortOrder・showHiddenFiles の変更でも
    /// 一覧を再取得させるため、3値をまとめた Hashable な複合キーにする。
    ///
    /// 供給元が自前列挙かどうかも含める。ディレクトリが据え置きのまま
    /// .shared → .ownListing へ切り替わることがあり(サイドバーが別のディレクトリへ移り、
    /// このフォルダーが「選択中のサブフォルダー」側になったとき)、キーに入れていないと
    /// 列挙が一度も走らずプレビューが空のままになる(TASK-295)。
    struct ListingKey: Hashable {
        let directory: URL
        let sortOrder: SortOrder
        let showHiddenFiles: Bool
        let usesOwnListing: Bool
    }

    var listingKey: ListingKey {
        ListingKey(
            directory: directory,
            sortOrder: sortOrder,
            showHiddenFiles: showHiddenFiles,
            usesOwnListing: source == .ownListing
        )
    }

    /// ディスクから引いた一覧に表示設定を適用した結果。サイドバー
    /// (FileListModel.visibleEntries)と同じ FileListFilter を同じ関数で適用するため、
    /// 同じディレクトリを見ているときは両者が必ず一致する(TASK-288)。
    ///
    /// `.shared` の場合、`entries` はサイドバー(FileListModel.visibleEntries)が同じ
    /// filter・directory で既に絞り込んだ一覧である。開いているファイルの追記
    /// (appendingOpenFile)で件数が増えなければ、その一覧がそのまま最終結果であり、
    /// 同じ filter.apply を body 評価のたびに再実行する必要がない(TASK-298)。追記が
    /// 起きた場合(フォルダー移動直後など、手元の一覧が openFile の変化にまだ追従して
    /// いない)だけ apply を通す。filter.apply は同じ入力に対して冪等なので、既に
    /// 絞り込み済みの分がもう一度通っても結果は変わらない。
    func visibleEntries(from entries: [FileListEntry]) -> [FileListEntry] {
        let appended = DirectoryLister.appendingOpenFile(openFile, to: entries, in: directory)
        guard case .shared = source, appended.count == entries.count else {
            return filter.apply(to: appended, in: directory)
        }
        return appended
    }

    /// 手元にある一覧。nil は「未取得」で、空一覧(= 絞り込みで全部消えた)と区別する。
    ///
    /// 供給元が指した一覧をそのまま使い、退避先は持たない。`.shared(nil)`(= 一覧がまだ
    /// 届いていない)は「git 状態と対になった一覧を待て」の意味であり、ここで自前列挙の
    /// キャッシュへ退避すると、絞り込み前の全件が一瞬描画され(TASK-293 の回帰)、
    /// 列挙し直さないため削除済みのファイルも残る(TASK-301)。待たなくてよい場面では
    /// 供給元自体が `.ownListing` になる(FileListModel.listingSource)。
    static func resolveListing(
        source: FolderListingSource, cached: SharedFolderListing?
    ) -> SharedFolderListing? {
        switch source {
        case let .shared(listing): listing
        case .ownListing: cached
        }
    }

    private var loadedListing: SharedFolderListing? {
        Self.resolveListing(source: source, cached: cachedListing)
    }

    /// List へ渡す一覧。nil は「未取得」で、この間は 1 行も描かない。
    ///
    /// 未取得を空配列へ潰して `visibleEntries(from:)` に通してはならない。
    /// `appendingOpenFile` が開いているファイルを足すため、一覧の到着待ちに
    /// 「開いているファイル 1 行だけの幻リスト」が出る(TASK-301)。
    var displayedEntries: [FileListEntry]? {
        loadedListing.map { visibleEntries(from: $0.entries) }
    }

    var body: some View {
        let entries = displayedEntries
        List(entries ?? [], selection: $localSelection) { entry in
            FileListEntryRow(entry: entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
                .simultaneousGesture(singleTapGesture(for: entry))
                .simultaneousGesture(doubleTapGesture(for: entry))
        }
        .overlay {
            // 空状態は絞り込み後の一覧で判定する。絞り込みで全部消えたときも
            // 「何もない」と伝えないと、無言の空リストになる。到着待ち(nil)の間は
            // まだ答えが出ていないので何も言わない。
            if let entries, entries.isEmpty {
                // 絞り込みで空になったのかを、サイドバーと同じ実装で出し分ける。
                // git 絞り込みはリポジトリ配下のどの階層にも効くため、この一覧が
                // サブフォルダーのものでも絞り込みによる空が起こりうる(TASK-361.2)。
                SidebarEmptyState(context: SidebarEmptyContext(
                    activeGitChangeFilter: filter.gitChangeFilter(for: directory),
                    filterText: filter.filterText,
                    directoryName: directory.lastPathComponent,
                    // 読めなかったフォルダーを「空のフォルダー」と言い切らない(TASK-410)。
                    didFailEnumeration: loadedListing?.didFailEnumeration ?? false
                ))
                .allowsHitTesting(false)
            }
        }
        .task(id: listingKey) {
            guard source == .ownListing else { return }
            let listing = await DirectoryLister.listingAsync(
                in: directory,
                sortOrder: sortOrder,
                showHiddenFiles: showHiddenFiles
            )
            // 自前列挙の経路でも畳むのは DirectoryListing.rows の 1 箇所を通る。
            cachedListing = SharedFolderListing(
                entries: listing.rows(), didFailEnumeration: listing.didFailEnumeration
            )
        }
        .id(directory)
    }

    /// シングルクリックはハイライトのみ(サイドバーと同じ操作感)。
    private func singleTapGesture(for entry: FileListEntry) -> some Gesture {
        TapGesture().onEnded {
            localSelection = entry.id
        }
    }

    /// ダブルクリックでファイルを開く/サブフォルダーへ移動する。
    private func doubleTapGesture(for entry: FileListEntry) -> some Gesture {
        TapGesture(count: 2).onEnded {
            switch entry.kind {
            case .file:
                onSelectFile(entry.url)
            case .folder:
                onNavigateToFolder(entry.url)
            }
        }
    }
}
