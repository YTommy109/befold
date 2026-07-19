import BefoldKit
import SwiftUI

/// サイドバーでフォルダーが選択された際にプレビューエリアへ表示する、
/// そのフォルダー直下の一覧。WKWebView を使わず SwiftUI の List で完結させる。
/// 隠しファイル表示・並び順はサイドバー(FileListModel)の現在値をそのまま渡してもらい、
/// このビュー自身は独自の設定を持たない。
struct FolderListingView: View {
    let directory: URL
    let sortOrder: SortOrder
    let showHiddenFiles: Bool
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void

    /// このビュー内だけのハイライト選択。サイドバーの選択状態(FileListModel.selection)とは
    /// 同期しない。ダブルクリックで確定した操作(onSelectFile/onNavigateToFolder)だけが
    /// サイドバー側の状態を書き換える。
    @State private var localSelection: FileListEntry.ID?
    /// ディレクトリー一覧をキャッシュ。directory 変更時に .task で非同期に再取得し、
    /// 毎回の本体レンダリング時の再計算・重複呼び出しを避ける。
    @State private var cachedEntries: [FileListEntry] = []

    var body: some View {
        List(cachedEntries, selection: $localSelection) { entry in
            FileListEntryRow(entry: entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
                .simultaneousGesture(singleTapGesture(for: entry))
                .simultaneousGesture(doubleTapGesture(for: entry))
        }
        .overlay {
            if cachedEntries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    String(localized: "sidebar.empty", bundle: .l10n),
                    systemImage: "doc.questionmark",
                    description: Text(directory.lastPathComponent)
                )
                .allowsHitTesting(false)
            }
        }
        .task(id: directory) {
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
