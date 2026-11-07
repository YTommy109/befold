import AppKit
import BefoldKit

/// 空タブのサイドバーの受け手。`SidebarNavigator` と `FileListView` は文書タブと同じものを使い、
/// 「ファイルを選ぶ」だけがこのタブを文書へ置き換える動作になる。
extension BlankTabWindowController: SidebarInheritanceSource {
    var inheritableSidebar: SidebarNavigator? {
        sidebarContext?.navigator
    }

    /// サイドバーが見ているフォルダ。⌘O と Quick Open の起点にする。サイドバーが無ければ nil。
    var sidebarDirectory: URL? {
        sidebarContext?.navigator.fileListModel.currentDirectory
    }

    /// Quick Open の候補の起点。文書が無いので、フォルダ直下の存在しないファイルで表す
    /// (起点はファイルの親フォルダとして読まれ、ファイル自体は開かれない)。
    var quickOpenAnchor: URL? {
        sidebarDirectory?.appendingPathComponent(".befold-blank-tab")
    }
}

extension BlankTabWindowController: SidebarNavigatorHost {
    /// 空タブに文書は無い。
    var currentFileURL: URL? {
        nil
    }

    @discardableResult
    func performFileSwitch(to url: URL) -> FileSwitchOutcome {
        guard let sidebarContext, let window else { return .failed }
        return sidebarContext.replaceWithDocument(url, window) ? .switched : .failed
    }

    func historyStateDidChange() {}

    func gitContextDidChange() {}
}

extension BlankTabWindowController: FileListViewDelegate {
    /// 置き換えるとこのタブの一覧ごと閉じるので、選択を届けている一覧の処理が終わってから開く。
    func fileListDidSelectFile(_ url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .failed = performFileSwitch(to: url) else { return }
            sidebarContext?.navigator.fileListModel.selection = nil
        }
    }

    func fileListDidRequestNavigation(to url: URL) {
        sidebarContext?.navigator.navigateToFolder(url)
    }

    func fileListDidRequestOpenElsewhere(_ url: URL, disposition: OpenDisposition) {
        guard let window else { return }
        sidebarContext?.openElsewhere(url, disposition, window)
    }

    func fileListDidRequestExpand(_ entry: FileListEntry) {
        sidebarContext?.navigator.expandFolder(entry.pathKey, at: entry.url)
    }

    func fileListDidRequestCollapse(_ entry: FileListEntry) {
        sidebarContext?.navigator.collapseFolder(entry.pathKey)
    }

    func fileListDidRequestDisplayChange(_ change: SidebarDisplayChange) {
        sidebarContext?.navigator.applyDisplayChange(change)
    }

    func fileListDidRequestComparisonTarget(_ target: GitComparisonTarget) {
        guard comparisonTarget != target else { return }
        comparisonTarget = target
        sidebarContext?.navigator.refreshGitStatuses()
    }
}
