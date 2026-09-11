import BefoldKit
import Foundation

// MARK: - FileListViewDelegate

/// サイドバー一覧(`FileListView`)の行操作と表示切り替えの受け先。
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
        openFileElsewhere(url, disposition, .end, window) // 一覧からの独立したオープンは末尾へ(TASK-611)
    }

    func fileListDidRequestExpand(_ entry: FileListEntry) {
        sidebar.expandFolder(entry.pathKey, at: entry.url)
    }

    func fileListDidRequestCollapse(_ entry: FileListEntry) {
        sidebar.collapseFolder(entry.pathKey)
    }

    /// サイドバーヘッダーのトグル。表示 4 値は窓ごとのライブ値なので(ADR 0002)、
    /// **この窓のサイドバーへ直接届ける。** メニュー(⌃⌘T ほか)と同じ経路を通り、
    /// ボタン専用の経路は持たせない。
    func fileListDidRequestDisplayChange(_ change: SidebarDisplayChange) {
        sidebar.applyDisplayChange(change)
    }
}
