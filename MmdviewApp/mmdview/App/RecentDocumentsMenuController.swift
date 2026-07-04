import AppKit

/// "Open Recent" サブメニューを NSDocumentController の履歴から自前で構築する。
/// コード構築メニューはシステムの自動管理(nib の NSRecentDocumentsMenu)に
/// 接続できないため、NSMenuDelegate で表示直前に毎回再生成する。
@MainActor
final class RecentDocumentsMenuController: NSObject, NSMenuDelegate {
    private let recentURLs: () -> [URL]
    private let openHandler: (URL) -> Void

    init(
        recentURLs: @escaping () -> [URL] = { NSDocumentController.shared.recentDocumentURLs },
        openHandler: @escaping (URL) -> Void
    ) {
        self.recentURLs = recentURLs
        self.openHandler = openHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = recentURLs()
        for url in urls {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !urls.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = NSMenuItem(
            title: String(localized: "menu.file.clearMenu", bundle: .l10n),
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = NSDocumentController.shared
        menu.addItem(clearItem)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openHandler(url)
    }
}
