import BefoldKit
import Foundation

// MARK: - FileListViewDelegate

/// サイドバー一覧(`FileListView`)の行操作の受け先。
///
/// `SidebarNavigatorHost` と同じく「外から来た契機を、このウィンドウの担当者へ配る」
/// だけの薄い層に保つ。判断や状態はここに置かない。
@MainActor
extension ViewerWindowController: FileListViewDelegate {
    func fileListDidSelectFile(_ url: URL) {
        switchFile(to: url)
    }

    func fileListDidRequestNavigation(to url: URL) {
        navigateToFolder(url)
    }

    func fileListDidRequestOpenElsewhere(_ url: URL, disposition: OpenDisposition) {
        openFileElsewhere(url, disposition, window)
    }

    func fileListDidRequestExpand(_ entry: FileListEntry) {
        sidebar.expandFolder(entry.pathKey, at: entry.url)
    }

    func fileListDidRequestCollapse(_ entry: FileListEntry) {
        sidebar.collapseFolder(entry.pathKey)
    }
}
