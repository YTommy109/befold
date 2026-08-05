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
        menu.addFileItems(urls: urls, action: #selector(openBookmark(_:)), target: self)
    }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openHandler(url)
    }
}
