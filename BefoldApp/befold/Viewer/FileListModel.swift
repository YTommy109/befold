import Foundation

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL
    var entries: [FileListEntry]
    var selection: FileListEntry.ID?
    var sortOrder: SortOrder

    var canGoBack: Bool {
        !backHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    var backHistory: [HistoryEntry] = []
    var forwardHistory: [HistoryEntry] = []

    init(currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?) {
        self.currentDirectory = currentDirectory
        self.entries = entries
        self.selection = selection
        sortOrder = .foldersFirst
    }
}
