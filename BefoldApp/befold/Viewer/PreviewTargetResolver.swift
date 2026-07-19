import Foundation

/// プレビューエリアが表示すべき対象。ファイルなら既存の ViewerWebView、
/// フォルダーなら FolderListingView(その URL 直下の一覧)を表示する。
enum PreviewTarget: Equatable {
    case file
    case folder(URL)
}

/// サイドバーの選択状態からプレビュー対象を決める純粋ロジック。
/// FileListModel/SidebarNavigator の状態をそのまま参照し、独自の状態を持たない。
enum PreviewTargetResolver {
    static func resolve(
        selection: FileListEntry.ID?,
        entries: [FileListEntry],
        currentDirectory: URL
    ) -> PreviewTarget {
        guard let selection,
              let entry = entries.first(where: { $0.id == selection })
        else {
            return .folder(currentDirectory)
        }
        return entry.kind == .file ? .file : .folder(entry.url)
    }
}
