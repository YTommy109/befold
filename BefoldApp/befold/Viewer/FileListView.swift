import AppKit
import BefoldKit
import SwiftUI

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void
    /// 選択行を別のタブ/ウィンドウで開く。disposition ごとにクロージャを分けず
    /// 1 本にまとめることで、開き先を増やしても配線が増えない
    /// (受け側の ViewerWindowController.openFileElsewhere も disposition を取る)。
    let onOpenElsewhere: (URL, OpenDisposition) -> Void
    var onToggleHiddenFiles: (() -> Void)?

    @FocusState private var isFilterFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            entryList
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            baseDirectoryIndicator
            navigationHeader
            if model.isFilterActive {
                filterField
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var filterField: some View {
        TextField(
            String(localized: "sidebar.filter.placeholder", bundle: .l10n),
            text: $model.filterText
        )
        .textFieldStyle(.plain)
        .focused($isFilterFieldFocused)
        .onAppear { isFilterFieldFocused = true }
        .onKeyPress(.escape) {
            closeFilter()
            return .handled
        }
    }

    /// フィルターフィールドを閉じ、フィルター文字列を解除する。
    /// アイコン再押下・esc のどちらからも同じ挙動にするための共通口。
    private func closeFilter() {
        model.isFilterActive = false
        model.filterText = ""
    }

    /// 基準ディレクトリの解決前(初回表示直後の一瞬)は行を出さない。
    @ViewBuilder
    private var baseDirectoryIndicator: some View {
        if let base = model.baseDirectory {
            BaseDirectoryIndicator(base: base)
        }
    }

    private var navigationHeader: some View {
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

            Button {
                if model.isFilterActive {
                    closeFilter()
                } else {
                    model.isFilterActive = true
                }
            } label: {
                Image(systemName: model.filterText.isEmpty
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(model.filterText.isEmpty ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .help(model.isFilterActive
                ? String(localized: "sidebar.filter.hide", bundle: .l10n)
                : String(localized: "sidebar.filter.show", bundle: .l10n))
        }
    }

    private var entryList: some View {
        List(model.visibleEntries, selection: $model.selection) { entry in
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
            if model.visibleEntries.allSatisfy({ $0.kind == .parentNavigation }) {
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
            openElsewhereButtons(for: entry)
            Button(String(localized: "sidebar.context.copyPath", bundle: .l10n)) {
                copyPath(entry.url)
            }
            Button(String(localized: "sidebar.context.revealInFinder", bundle: .l10n)) {
                revealInFinder(entry.url)
            }
        }
    }

    /// 「別の場所で開く」系の項目定義(並び・文言キー・開き先)。項目を数える単一情報源を
    /// ここに置き、片方の開き先だけメニューから抜け落ちるのを防ぐ。
    static let openElsewhereEntries: [(titleKey: String, disposition: OpenDisposition)] = [
        ("sidebar.context.openInNewTab", .newTab),
        ("sidebar.context.openInNewWindow", .newWindow),
    ]

    private func openElsewhereButtons(for entry: FileListEntry) -> some View {
        ForEach(Self.openElsewhereEntries, id: \.titleKey) { item in
            openElsewhereButton(for: entry, titleKey: item.titleKey, disposition: item.disposition)
        }
    }

    /// フォルダー行では「そのフォルダーで最初に開けるファイル」を開き先にする。
    /// 走査はメインを止めないよう detached で行い、開けるファイルが無い行は無効化する。
    @ViewBuilder
    private func openElsewhereButton(
        for entry: FileListEntry, titleKey: String, disposition: OpenDisposition
    ) -> some View {
        let label = String(localized: String.LocalizationValue(titleKey), bundle: .l10n)
        if entry.kind == .folder {
            let folder = entry.url
            Button(label) {
                Task {
                    let detached = Task.detached { DirectoryLister.firstSupportedFile(in: folder) }
                    if let first = await detached.value {
                        onOpenElsewhere(first, disposition)
                    }
                }
            }
            .disabled(!entry.containsSupportedFile)
        } else {
            Button(label) {
                onOpenElsewhere(entry.url, disposition)
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
        pasteboard.setString(relativePathForCopy(url), forType: .string)
    }

    /// コピー対象の相対パス。基準は model.baseDirectory(SidebarNavigator がメイン外で
    /// 解決済みの `gitRoot ?? workspaceRoot`)、未解決なら rootDirectory にフォールバックする。
    /// PathRelativizer.relativePath(workspaceRoot:gitRoot:) と同じ規則(BaseDirectoryDescriptor
    /// のドキュメント参照)なので、git subprocess をここで新たに走らせる必要がない。
    /// テストから直接呼べるよう internal にする。
    func relativePathForCopy(_ url: URL) -> String {
        PathRelativizer.relativePath(of: url, relativeTo: model.baseDirectory?.url ?? model.rootDirectory)
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
              let index = model.visibleEntries.firstIndex(where: { $0.id == current }),
              index + 1 < model.visibleEntries.count
        else {
            if model.selection == nil, let first = model.visibleEntries.first {
                model.selection = first.id
                openIfFile(first)
                return .handled
            }
            return .ignored
        }
        let next = model.visibleEntries[index + 1]
        model.selection = next.id
        openIfFile(next)
        return .handled
    }

    /// 選択を前のエントリへ戻す。テストから直接呼べるよう internal。
    func selectPrevious() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.visibleEntries.firstIndex(where: { $0.id == current }),
              index > 0
        else {
            return .ignored
        }
        let previous = model.visibleEntries[index - 1]
        model.selection = previous.id
        openIfFile(previous)
        return .handled
    }

    private func enterSelected() -> KeyPress.Result {
        guard let current = model.selection,
              let entry = model.visibleEntries.first(where: { $0.id == current })
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
        if let parent = model.visibleEntries.first(where: { $0.kind == .parentNavigation }) {
            onNavigate(parent.url)
            return .handled
        }
        return .ignored
    }
}
