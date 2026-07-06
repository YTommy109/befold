import SwiftUI

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

    init(currentDirectory: URL, entries: [FileListEntry], selection: FileListEntry.ID?) {
        self.currentDirectory = currentDirectory
        self.entries = entries
        self.selection = selection
        sortOrder = .foldersFirst
    }
}

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void

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
            .help(model.sortOrder == .foldersFirst ? "アルファベット順" : "フォルダー優先")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var entryList: some View {
        Group {
            if model.entries.allSatisfy({ $0.kind == .parentNavigation }) {
                ContentUnavailableView(
                    "対応ファイルがありません",
                    systemImage: "doc.questionmark",
                    description: Text(model.currentDirectory.lastPathComponent)
                )
            } else {
                List(model.entries, selection: $model.selection) { entry in
                    entryRow(entry)
                        .contextMenu { contextMenuItems(for: entry) }
                }
                .onChange(of: model.selection) { _, newValue in
                    if let url = newValue,
                       model.entries.first(where: { $0.id == url })?.kind == .file
                    {
                        onSelect(url)
                    }
                }
                .onKeyPress { keyPress in
                    handleKeyPress(keyPress)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: FileListEntry) -> some View {
        switch entry.kind {
        case .parentNavigation:
            Label {
                Text("..")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "arrow.up.doc")
                    .foregroundStyle(.secondary)
            }
        case .folder:
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        case .file:
            Label {
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for entry: FileListEntry) -> some View {
        if entry.kind != .parentNavigation {
            Button("コピー") { copyFileReference(entry.url) }
            openInNewWindowButton(for: entry)
            Button("パスをコピーする") { copyPath(entry.url) }
            Button("Finder で開く") { revealInFinder(entry.url) }
        }
    }

    @ViewBuilder
    private func openInNewWindowButton(for entry: FileListEntry) -> some View {
        if entry.kind == .folder {
            let firstFile = DirectoryLister.listEntries(in: entry.url, sortOrder: .foldersFirst)
                .first { $0.kind == .file }
            Button("新しいウィンドウで開く") {
                if let file = firstFile {
                    AppDelegate.shared?.openViewer(for: file.url)
                }
            }
            .disabled(firstFile == nil)
        } else {
            Button("新しいウィンドウで開く") {
                AppDelegate.shared?.openViewer(for: entry.url)
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
        pasteboard.setString(url.path, forType: .string)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Keyboard Navigation

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case "j":
            selectNext()
        case "k":
            selectPrevious()
        case .return, .rightArrow, "l":
            enterSelected()
        case .leftArrow, "h", .delete:
            navigateToParent()
        default:
            .ignored
        }
    }

    private func selectNext() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index + 1 < model.entries.count
        else {
            if model.selection == nil, let first = model.entries.first {
                model.selection = first.id
                return .handled
            }
            return .ignored
        }
        model.selection = model.entries[index + 1].id
        return .handled
    }

    private func selectPrevious() -> KeyPress.Result {
        guard let current = model.selection,
              let index = model.entries.firstIndex(where: { $0.id == current }),
              index > 0
        else {
            return .ignored
        }
        model.selection = model.entries[index - 1].id
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
            return .ignored
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
