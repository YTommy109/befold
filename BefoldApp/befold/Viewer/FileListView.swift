import AppKit
import BefoldKit
import SwiftUI

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void
    let onOpenInNewWindow: (URL) -> Void
    var onToggleHiddenFiles: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            entryList
        }
    }

    private var header: some View {
        HStack {
            Text(model.currentDirectory.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                let next: SortOrder = model.sortOrder == .foldersFirst ? .alphabetical : .foldersFirst
                onSortOrderChanged(next)
            } label: {
                Image(systemName: model.sortOrder == .foldersFirst
                    ? "folder.fill" : "textformat.abc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(model.sortOrder == .foldersFirst
                ? String(localized: "sidebar.sort.alphabetical", bundle: .l10n)
                : String(localized: "sidebar.sort.foldersFirst", bundle: .l10n))

            Button {
                onToggleHiddenFiles?()
            } label: {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                    .foregroundStyle(model.showHiddenFiles ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(model.showHiddenFiles
                ? String(localized: "sidebar.hiddenFiles.hide", bundle: .l10n)
                : String(localized: "sidebar.hiddenFiles.show", bundle: .l10n))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var entryList: some View {
        List(model.entries, selection: $model.selection) { entry in
            // 行インセットをゼロにして同等のパディングを行コンテンツ側へ移し、
            // contentShape が行の全幅を覆うようにする。インセット部分をダブル
            // クリックしたとき選択だけされて移動しない取りこぼしを防ぐ。
            FileListEntryRow(entry: entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
                .background(SidebarTableViewLocator { tableView in
                    model.sidebarTableView = tableView
                })
                .contextMenu { contextMenuItems(for: entry) }
                .simultaneousGesture(singleTapGesture(for: entry))
                .simultaneousGesture(doubleTapGesture(for: entry))
        }
        .overlay {
            if model.entries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    String(localized: "sidebar.empty", bundle: .l10n),
                    systemImage: "doc.questionmark",
                    description: Text(model.currentDirectory.lastPathComponent)
                )
                .allowsHitTesting(false)
            }
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for entry: FileListEntry) -> some View {
        if entry.kind != .parentNavigation {
            Button(String(localized: "sidebar.context.copy", bundle: .l10n)) {
                copyFileReference(entry.url)
            }
            openInNewWindowButton(for: entry)
            Button(String(localized: "sidebar.context.copyPath", bundle: .l10n)) {
                copyPath(entry.url)
            }
            Button(String(localized: "sidebar.context.revealInFinder", bundle: .l10n)) {
                revealInFinder(entry.url)
            }
        }
    }

    @ViewBuilder
    private func openInNewWindowButton(for entry: FileListEntry) -> some View {
        let label = String(
            localized: "sidebar.context.openInNewWindow",
            bundle: .l10n
        )
        if entry.kind == .folder {
            let hasFile = DirectoryLister.containsSupportedFile(in: entry.url)
            Button(label) {
                if let first = DirectoryLister.firstSupportedFile(in: entry.url) {
                    onOpenInNewWindow(first)
                }
            }
            .disabled(!hasFile)
        } else {
            Button(label) {
                onOpenInNewWindow(entry.url)
            }
        }
    }

    private func copyFileReference(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            PathRelativizer.relativePath(of: url, relativeTo: model.rootDirectory),
            forType: .string
        )
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Click

    /// シングルクリックで行を選択し、ファイルなら開く。
    /// List の選択バインディング任せにせず自前で選択を書くことで、
    /// プログラム的な選択更新とクリックが競合しても確実に反応させる。
    private func singleTapGesture(
        for entry: FileListEntry
    ) -> some Gesture {
        TapGesture().onEnded {
            model.selection = entry.id
            openIfFile(entry)
            // List が選択を NSTableView へ反映し終える前に first responder を
            // 奪うと選択行とハイライトがズレるため、次のランループへ遅延する
            // (固定待ちは不要)。
            DispatchQueue.main.async {
                model.focusSidebarTable()
            }
        }
    }

    /// 選択が確定したエントリがファイルなら表示を更新する。
    /// クリック・矢印キー・j/k など、選択を変えるすべての経路から呼ぶことで
    /// 「選択は動くが表示が追従しない」状態を防ぐ。
    func openIfFile(_ entry: FileListEntry) {
        if entry.kind == .file {
            onSelect(entry.url)
        }
    }

    private func doubleTapGesture(
        for entry: FileListEntry
    ) -> some Gesture {
        TapGesture(count: 2).onEnded {
            if entry.kind == .parentNavigation || entry.kind == .folder {
                // List が 2 クリック目のイベント処理を終える前に entries を
                // 差し替えないよう、次のランループまで遅延する(固定待ちは不要)。
                DispatchQueue.main.async {
                    onNavigate(entry.url)
                }
            }
        }
    }

    // MARK: - Keyboard Navigation

    /// サイドバーがアクティブなときのキー操作を処理する。
    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        handleKey(keyPress.key)
    }

    /// キーとアクションの対応付け。`KeyPress` は公開イニシャライザがなくテストで
    /// 直接構築できないため、`KeyEquivalent` だけを受け取るこの関数を internal にして
    /// テストから直接呼べるようにしている。
    func handleKey(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case "j", .downArrow:
            selectNext()
        case "k", .upArrow:
            selectPrevious()
        case .return, .rightArrow, "l":
            enterSelected()
        case .leftArrow, "h", .delete:
            navigateToParent()
        default:
            .ignored
        }
    }

    /// 選択を次のエントリへ進める。テストから直接呼べるよう internal。
    func selectNext() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index + 1 < model.entries.count
        else {
            if model.selection == nil, let first = model.entries.first {
                model.selection = first.id
                openIfFile(first)
                return .handled
            }
            return .ignored
        }
        let next = model.entries[index + 1]
        model.selection = next.id
        openIfFile(next)
        return .handled
    }

    /// 選択を前のエントリへ戻す。テストから直接呼べるよう internal。
    func selectPrevious() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index > 0
        else {
            return .ignored
        }
        let previous = model.entries[index - 1]
        model.selection = previous.id
        openIfFile(previous)
        return .handled
    }

    private func enterSelected() -> KeyPress.Result {
        guard let current = model.selection,
              let entry = model.entries.first(where: { $0.id == current })
        else {
            return .ignored
        }
        switch entry.kind {
        case .parentNavigation, .folder:
            onNavigate(entry.url)
            return .handled
        case .file:
            openIfFile(entry)
            return .handled
        }
    }

    private func navigateToParent() -> KeyPress.Result {
        if let parent = model.entries.first(where: { $0.kind == .parentNavigation }) {
            onNavigate(parent.url)
            return .handled
        }
        return .ignored
    }
}
