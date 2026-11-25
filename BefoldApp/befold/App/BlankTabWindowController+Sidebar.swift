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

    /// 空タブの本文は空タブの画面で、文書もフォルダー一覧も出していない。
    var presentedTarget: PreviewTarget? {
        nil
    }

    /// サイドバーから開いた文書タブも、文書タブのサイドバーと同じくフォーカスを表に残す
    /// (TASK-581)。閉じる空タブの表に当てても、置き換えた窓の表には誰もフォーカスしない。
    /// 再利用した既存のタブのサイドバーが閉じていれば、`focusSidebar` が何もしない。
    @discardableResult
    func performFileSwitch(to url: URL) -> FileSwitchOutcome {
        guard let sidebarContext, let window else { return .failed }
        guard let replaced = sidebarContext.replaceWithDocument(url, window) else { return .failed }
        replaced.focusSidebar(nil)
        return .switched
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

    /// 空タブは本文にフォルダー一覧を出さない(本文は空タブの画面のまま)。
    func fileListDidSelectFolder(_: URL) {}

    func fileListDidRequestNavigation(to url: URL) {
        sidebarContext?.navigator.navigateToFolder(url, presentingFolder: { _ in })
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
