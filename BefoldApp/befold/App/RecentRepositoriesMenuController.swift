import AppKit

/// "Recent Repositories" サブメニューを RecentRepositoriesStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成し、
/// 併せて存在しなくなった worktree 等の一覧メンテナンス(pruneMissing)もここで行う。
@MainActor
final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate {
    private let pruneMissing: () -> Void
    private let entries: () -> [RecentRepositoryEntry]
    private let openHandler: (RecentRepositoryEntry) -> Void
    private let clearHandler: () -> Void

    init(
        pruneMissing: @escaping () -> Void,
        entries: @escaping () -> [RecentRepositoryEntry],
        openHandler: @escaping (RecentRepositoryEntry) -> Void,
        clearHandler: @escaping () -> Void
    ) {
        self.pruneMissing = pruneMissing
        self.entries = entries
        self.openHandler = openHandler
        self.clearHandler = clearHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pruneMissing()
        menu.removeAllItems()
        let currentEntries = entries()
        for entry in currentEntries {
            let item = NSMenuItem(
                title: entry.label,
                action: #selector(openRecentRepository(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry
            let icon = NSWorkspace.shared.icon(forFile: entry.rootPath)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !currentEntries.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = NSMenuItem(
            title: String(localized: "menu.file.clearMenu", bundle: .l10n),
            action: #selector(clearRecentRepositories(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
    }

    @objc private func openRecentRepository(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? RecentRepositoryEntry else { return }
        openHandler(entry)
    }

    @objc private func clearRecentRepositories(_ sender: Any?) {
        clearHandler()
    }
}
