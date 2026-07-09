import AppKit
import Foundation

/// サイドバーのファイル一覧と選択状態を保持する監視可能モデル。
/// リネームやディレクトリの変化に追従して一覧・選択を更新できるよう、
/// ウィンドウ側(ViewerWindowController)が参照型で保持して書き換える。
@MainActor
@Observable
final class FileListModel {
    var currentDirectory: URL
    /// このウィンドウでこれまでにアクティブになった最上位のディレクトリ。
    /// パスコピー機能の相対パス基準として使う(SidebarNavigator.navigateToFolder が更新)。
    var rootDirectory: URL
    var entries: [FileListEntry]
    var selection: FileListEntry.ID?
    var sortOrder: SortOrder

    /// サイドバー行から見つかった NSTableView への弱参照。SidebarTableViewLocator が
    /// 行描画時に設定する。クリック時に first responder へ昇格させるためだけの
    /// UI 専用値であり、監視対象にする必要はない(#144)。
    @ObservationIgnored
    weak var sidebarTableView: NSTableView?

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
        rootDirectory = currentDirectory
        self.entries = entries
        self.selection = selection
        sortOrder = .foldersFirst
    }
}
