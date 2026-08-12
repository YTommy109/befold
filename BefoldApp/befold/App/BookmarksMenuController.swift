import AppKit

/// "Bookmarks" サブメニューを BookmarkStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
///
/// 個別のブックマーク解除は該当ファイルを開いてトグルオフする運用だが、開けなくなった
/// ファイル(削除・worktree ごと消滅)はその経路を取れないため、末尾に一括除去の項目を置く。
/// **この型は `FileReading` を持たない。** 存在確認(stat)はアンマウント済み/応答しない
/// ネットワークマウントで待たされるため、メニュー表示のたびに走らせてはならず、
/// 判定は `MissingBookmarksPruner`(ユーザーが項目を選んだときだけ走る)に閉じている。
@MainActor
final class BookmarksMenuController: NSObject, NSMenuDelegate {
    private let bookmarkedURLs: () -> [URL]
    private let openHandler: (URL) -> Void
    private let removeMissingHandler: () -> Void

    init(
        bookmarkedURLs: @escaping () -> [URL],
        openHandler: @escaping (URL) -> Void,
        removeMissingHandler: @escaping () -> Void
    ) {
        self.bookmarkedURLs = bookmarkedURLs
        self.openHandler = openHandler
        self.removeMissingHandler = removeMissingHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = bookmarkedURLs().sorted { $0.lastPathComponent < $1.lastPathComponent }
        menu.addFileItems(urls: urls, action: #selector(openBookmark(_:)), target: self)
        guard !urls.isEmpty else { return }
        menu.addItem(.separator())
        menu.addActionItem(
            title: String(localized: "menu.file.removeMissingBookmarks", bundle: .l10n),
            action: #selector(removeMissingBookmarks(_:)), target: self
        )
    }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openHandler(url)
    }

    @objc private func removeMissingBookmarks(_ sender: Any?) {
        removeMissingHandler()
    }
}
