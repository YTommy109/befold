import AppKit

/// "Open Recent" サブメニューを NSDocumentController の履歴から自前で構築する。
/// コード構築メニューはシステムの自動管理(nib の NSRecentDocumentsMenu)に
/// 接続できないため、NSMenuDelegate で表示直前に毎回再生成する。
@MainActor
final class RecentDocumentsMenuController: NSObject, NSMenuDelegate {
    private let recentURLs: () -> [URL]
    private let openHandler: (URL) -> Void
    private let clearHandler: () -> Void

    init(
        recentURLs: @escaping () -> [URL],
        openHandler: @escaping (URL) -> Void,
        clearHandler: @escaping () -> Void
    ) {
        self.recentURLs = recentURLs
        self.openHandler = openHandler
        self.clearHandler = clearHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = recentURLs()
        for url in urls {
            menu.addFileItem(
                title: url.lastPathComponent, filePath: url.path,
                action: #selector(openRecentDocument(_:)), target: self, representedObject: url
            )
        }
        if !urls.isEmpty {
            menu.addItem(.separator())
        }
        menu.addActionItem(
            title: String(localized: "menu.file.clearMenu", bundle: .l10n),
            action: #selector(clearRecentDocuments(_:)), target: self
        )
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openHandler(url)
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        clearHandler()
    }
}
