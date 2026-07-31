import AppKit
import UniformTypeIdentifiers

/// "Recent Repositories" サブメニューを RecentRepositoriesStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
/// 一覧のメンテナンス(存在しなくなった worktree 等の除去)はここでは行わない
/// (RecentRepositoriesStore.pruneMissingAsync が起動時に非同期で行う)。
/// アンマウント済み/応答しないネットワークマウント上のパスが履歴に残っていても、
/// メニュー表示自体は保存済みリストをそのまま出すだけで FS I/O を伴わない。
@MainActor
final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate {
    private let entries: () -> [RecentRepositoryEntry]
    private let openHandler: (RecentRepositoryEntry) -> Void
    private let clearHandler: () -> Void

    init(
        entries: @escaping () -> [RecentRepositoryEntry],
        openHandler: @escaping (RecentRepositoryEntry) -> Void,
        clearHandler: @escaping () -> Void
    ) {
        self.entries = entries
        self.openHandler = openHandler
        self.clearHandler = clearHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let currentEntries = entries()
        // パス毎の NSWorkspace.icon(forFile:) はディスク I/O を伴い、応答しないネットワーク
        // マウント上の worktree で固まりうるため使わない。リポジトリのルートは常にフォルダーなので、
        // パスに依存しない汎用フォルダーアイコンで足りる。
        let folderIcon = NSWorkspace.shared.icon(for: .folder)
        folderIcon.size = NSSize(width: 16, height: 16)
        for entry in currentEntries {
            let item = NSMenuItem(
                title: entry.label,
                action: #selector(openRecentRepository(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry
            item.image = folderIcon
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
