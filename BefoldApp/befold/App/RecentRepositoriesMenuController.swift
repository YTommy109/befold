import AppKit
import BefoldKit
import UniformTypeIdentifiers

/// "Recent Repositories" サブメニューを RecentRepositoriesStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
/// 一覧のメンテナンス(存在しなくなった worktree 等の除去)はここでは行わない
/// (RecentRepositoriesStore.pruneMissingAsync が起動時に非同期で行う)。
/// アンマウント済み/応答しないネットワークマウント上のパスが履歴に残っていても、
/// メニュー表示自体は保存済みリストをそのまま出すだけで FS I/O を伴わない。
///
/// worktree を持つリポジトリは「本体1項目 + 全 worktree のサブメニュー」に畳む。
/// worktree 一覧は WorktreeCatalog のキャッシュを同期で読むだけで、git は呼ばない
/// (呼ぶとメニューを開くたびに subprocess を待つことになる)。
@MainActor
final class RecentRepositoriesMenuController: NSObject, NSMenuDelegate {
    private let entries: () -> [RecentRepositoryEntry]
    /// 本体ルートに属する worktree 一覧(先頭が本体)。キャッシュ未解決なら空配列。
    private let worktrees: (URL) -> [GitWorktree]
    private let openHandler: (RecentRepositoryEntry) -> Void
    private let clearHandler: () -> Void

    init(
        entries: @escaping () -> [RecentRepositoryEntry],
        worktrees: @escaping (URL) -> [GitWorktree] = { _ in [] },
        openHandler: @escaping (RecentRepositoryEntry) -> Void,
        clearHandler: @escaping () -> Void
    ) {
        self.entries = entries
        self.worktrees = worktrees
        self.openHandler = openHandler
        self.clearHandler = clearHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let currentEntries = entries()
        // パス毎の NSWorkspace.icon(forFile:) はディスク I/O を伴い、応答しないネットワーク
        // マウント上の worktree で固まりうるため使わない。リポジトリのルートは常にフォルダーなので、
        // パスに依存しない汎用フォルダーアイコンで足りる。
        let folderIcon = NSWorkspace.shared.icon(for: .folder).sizedForMenuItem()
        for group in groups(of: currentEntries) {
            addItems(for: group, to: menu, icon: folderIcon)
        }
        if !currentEntries.isEmpty {
            menu.addItem(.separator())
        }
        menu.addActionItem(
            title: String(localized: "menu.file.clearMenu", bundle: .l10n),
            action: #selector(clearRecentRepositories(_:)), target: self
        )
    }

    // MARK: - 構築

    /// 同じ本体リポジトリに属するエントリの束。並びは「そのグループの最も新しいエントリの位置」。
    private struct RepositoryGroup {
        var mainRoot: URL
        var entries: [RecentRepositoryEntry]
    }

    /// entries(新しい順)を groupKey で束ね、最も新しいエントリの登場順を保った配列にする。
    private func groups(of entries: [RecentRepositoryEntry]) -> [RepositoryGroup] {
        var order: [String] = []
        var buckets: [String: RepositoryGroup] = [:]
        for entry in entries {
            let key = entry.groupKey
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = RepositoryGroup(
                    mainRoot: URL(fileURLWithPath: entry.mainRootPath ?? entry.rootPath), entries: []
                )
            }
            buckets[key]?.entries.append(entry)
        }
        return order.compactMap { buckets[$0] }
    }

    private func addItems(for group: RepositoryGroup, to menu: NSMenu, icon: NSImage) {
        let worktrees = worktrees(group.mainRoot)
        // worktree が1件以下(未解決・単一作業ツリー)なら、従来どおりのフラット表示に縮退する。
        guard worktrees.count > 1 else {
            for entry in group.entries {
                menu.addItem(openItem(title: entry.label, entry: entry, icon: icon))
            }
            return
        }
        let parent = NSMenuItem(title: group.mainRoot.lastPathComponent, action: nil, keyEquivalent: "")
        parent.image = icon
        let submenu = NSMenu(title: parent.title)
        var remaining = group.entries
        for worktree in worktrees {
            let key = worktree.root.normalizedPathKey
            let index = remaining.firstIndex { URL(fileURLWithPath: $0.rootPath).normalizedPathKey == key }
            // 記憶があればそれ(lastTabGroup ごと復元される)、無ければ合成して
            // ルートフォルダーを開くフォールバックにする。
            let entry = index.map { remaining.remove(at: $0) } ?? RecentRepositoryEntry(
                rootPath: key,
                label: worktree.displayName,
                lastTabGroup: nil,
                mainRootPath: worktree.isMain ? nil : group.mainRoot.normalizedPathKey
            )
            // 記憶済みエントリの label は本体基準の表記(`befold (etc)`)なので、
            // サブメニュー内では常に worktree 側の表記(`feat/repository (etc)`)を使う。
            submenu.addItem(openItem(title: worktree.displayName, entry: entry, icon: icon))
        }
        // カタログに載っていない記憶済みエントリ(削除された worktree 等)も取りこぼさない。
        for entry in remaining {
            submenu.addItem(openItem(title: entry.label, entry: entry, icon: icon))
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func openItem(title: String, entry: RecentRepositoryEntry, icon: NSImage) -> NSMenuItem {
        .action(
            title: title, action: #selector(openRecentRepository(_:)), target: self,
            representedObject: entry, image: icon
        )
    }

    @objc private func openRecentRepository(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? RecentRepositoryEntry else { return }
        openHandler(entry)
    }

    @objc private func clearRecentRepositories(_ sender: Any?) {
        clearHandler()
    }
}
