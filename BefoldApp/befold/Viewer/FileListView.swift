import AppKit
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

struct FileListView: View {
    @Bindable var model: FileListModel
    let onSelect: (URL) -> Void
    let onNavigate: (URL) -> Void
    let onSortOrderChanged: (SortOrder) -> Void
    let onOpenInNewWindow: (URL) -> Void
    var onNavigateHistory: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            entryList
        }
    }

    private var header: some View {
        HStack {
            HistoryNavigationButton(
                systemImage: "chevron.left",
                accessibilityLabel: String(localized: "sidebar.back", bundle: .l10n),
                isEnabled: model.canGoBack,
                entries: model.backHistory,
                primaryOffset: -1,
                onNavigate: { onNavigateHistory?($0) }
            )
            .frame(width: 20, height: 20)

            HistoryNavigationButton(
                systemImage: "chevron.right",
                accessibilityLabel: String(localized: "sidebar.forward", bundle: .l10n),
                isEnabled: model.canGoForward,
                entries: model.forwardHistory,
                primaryOffset: 1,
                onNavigate: { onNavigateHistory?($0) }
            )
            .frame(width: 20, height: 20)

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var entryList: some View {
        List(model.entries, selection: $model.selection) { entry in
            // 行インセットをゼロにして同等のパディングを行コンテンツ側へ移し、
            // contentShape が行の全幅を覆うようにする。インセット部分をダブル
            // クリックしたとき選択だけされて移動しない取りこぼしを防ぐ。
            entryRow(entry)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets())
                .contentShape(.rect)
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

    @ViewBuilder
    private func entryRow(_ entry: FileListEntry) -> some View {
        switch entry.kind {
        case .parentNavigation:
            HStack {
                Label {
                    Text("..")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.up.doc")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .folder:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        case .file:
            HStack {
                Label {
                    Text(entry.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Spacer()
            }
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
        pasteboard.setString(url.path, forType: .string)
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
            if entry.kind == .file {
                onSelect(entry.url)
            }
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
            onSelect(entry.url)
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

// MARK: - HistoryNavigationButton

private final class HistoryButtonView: NSButton {
    weak var coordinator: HistoryNavigationButton.Coordinator?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            coordinator?.showMenu(from: self)
            return
        }

        highlight(true)
        let deadline = Date(timeIntervalSinceNow: 0.3)
        var clickedInside = false
        var mouseUp = false
        while let next = window?.nextEvent(
            matching: [.leftMouseUp, .leftMouseDragged],
            until: deadline,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if next.type == .leftMouseUp {
                mouseUp = true
                let location = convert(next.locationInWindow, from: nil)
                clickedInside = bounds.contains(location)
                break
            }
        }
        highlight(false)

        if clickedInside {
            coordinator?.primaryAction()
        } else if !mouseUp {
            coordinator?.showMenu(from: self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        coordinator?.showMenu(from: self)
    }
}

private struct HistoryNavigationButton: NSViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let entries: [HistoryEntry]
    let primaryOffset: Int
    let onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HistoryButtonView {
        let button = HistoryButtonView(frame: .zero)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryPushIn)
        button.coordinator = context.coordinator
        configure(button)
        return button
    }

    func updateNSView(_ button: HistoryButtonView, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    private func configure(_ button: HistoryButtonView) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        button.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(config)
        button.isEnabled = isEnabled
        button.contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HistoryNavigationButton

        init(parent: HistoryNavigationButton) {
            self.parent = parent
        }

        func primaryAction() {
            parent.onNavigate(parent.primaryOffset)
        }

        func showMenu(from view: NSView) {
            guard !parent.entries.isEmpty else { return }
            let menu = NSMenu()
            let direction = parent.primaryOffset < 0 ? -1 : 1
            for (index, entry) in parent.entries.enumerated() {
                let (title, icon) = Self.menuLabel(for: entry)
                let item = NSMenuItem(
                    title: title,
                    action: #selector(menuItemClicked(_:)),
                    keyEquivalent: ""
                )
                item.image = icon
                item.target = self
                item.tag = direction * (index + 1)
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
        }

        private static func menuLabel(for entry: HistoryEntry) -> (String, NSImage) {
            if let file = entry.file {
                let dirName = entry.directory.lastPathComponent
                let title = "\(file.lastPathComponent) — \(dirName)"
                let icon = NSWorkspace.shared.icon(forFile: file.path)
                icon.size = NSSize(width: 16, height: 16)
                return (title, icon)
            } else {
                let title = entry.directory.lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: entry.directory.path)
                icon.size = NSSize(width: 16, height: 16)
                return (title, icon)
            }
        }

        @objc private func menuItemClicked(_ sender: NSMenuItem) {
            parent.onNavigate(sender.tag)
        }
    }
}
