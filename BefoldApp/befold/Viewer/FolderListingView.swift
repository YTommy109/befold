import BefoldKit
import SwiftUI

/// フォルダー一覧の供給元。表示中ディレクトリを見ているときは、サイドバー
/// (FileListModel)が git 状態と一緒に揃えた一覧をそのまま使う。自前で列挙すると
/// git 状態との完了順が揃わず、絞り込みが効く前の全件が一瞬描画される(TASK-293)。
enum FolderListingSource: Equatable {
    /// サイドバーと同じ一覧。nil は「このディレクトリの一覧がまだ手元に無い」。
    case shared([FileListEntry]?)
    /// このビューが自前で列挙する。選択中のサブフォルダーを見ているときに使う。
    case ownListing
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
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void

    /// このビュー内だけのハイライト選択。サイドバーの選択状態(FileListModel.selection)とは
    /// 同期しない。ダブルクリックで確定した操作(onSelectFile/onNavigateToFolder)だけが
    /// サイドバー側の状態を書き換える。
    @State private var localSelection: FileListEntry.ID?
    /// ディレクトリー一覧をキャッシュ。listingKey(directory・sortOrder・showHiddenFiles)変更時に
    /// .task で非同期に再取得し、毎回の本体レンダリング時の再計算・重複呼び出しを避ける。
    /// 初期値 nil は「未取得」を表し、取得完了後に空一覧と区別する(空状態の一瞬のちらつき防止)。
    @State private var cachedEntries: [FileListEntry]?

    /// .task(id:) のキー。directory だけでなく sortOrder・showHiddenFiles の変更でも
    /// 一覧を再取得させるため、3値をまとめた Hashable な複合キーにする。
    private struct ListingKey: Hashable {
        let directory: URL
        let sortOrder: SortOrder
        let showHiddenFiles: Bool
    }

    private var listingKey: ListingKey {
        ListingKey(directory: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles)
    }

    /// ディスクから引いた一覧に表示設定を適用した結果。サイドバー
    /// (FileListModel.visibleEntries)と同じ FileListFilter を同じ関数で適用するため、
    /// 同じディレクトリを見ているときは両者が必ず一致する(TASK-288)。
    func visibleEntries(from entries: [FileListEntry]) -> [FileListEntry] {
        filter.apply(to: entries, in: directory)
    }

    /// 手元にある一覧。nil は「未取得」で、空一覧(= 絞り込みで全部消えた)と区別する。
    private var loadedEntries: [FileListEntry]? {
        switch source {
        case let .shared(entries): entries
        case .ownListing: cachedEntries
        }
    }

    var body: some View {
        let entries = visibleEntries(from: loadedEntries ?? [])
        List(entries, selection: $localSelection) { entry in
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
            // 「何もない」と伝えないと、無言の空リストになる。
            if loadedEntries != nil, entries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    String(localized: "sidebar.empty", bundle: .l10n),
                    systemImage: "doc.questionmark",
                    description: Text(directory.lastPathComponent)
                )
                .allowsHitTesting(false)
            }
        }
        .task(id: listingKey) {
            guard source == .ownListing else { return }
            cachedEntries = await DirectoryLister.listEntriesAsync(
                in: directory,
                sortOrder: sortOrder,
                showHiddenFiles: showHiddenFiles
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
            case .folder, .parentNavigation:
                onNavigateToFolder(entry.url)
            }
        }
    }
}
