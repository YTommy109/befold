import AppKit

/// "Bookmarks" サブメニューを BookmarkStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
/// Recent と異なりクリア・個別削除は設けない(該当ファイルを開いてトグルオフする運用)。
@MainActor
final class BookmarksMenuController: NSObject, NSMenuDelegate {
    private let bookmarkedURLs: () -> [URL]
    private let openHandler: (URL) -> Void

    init(bookmarkedURLs: @escaping () -> [URL], openHandler: @escaping (URL) -> Void) {
        self.bookmarkedURLs = bookmarkedURLs
        self.openHandler = openHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = bookmarkedURLs().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(openBookmark(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
    }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openHandler(url)
    }
}
