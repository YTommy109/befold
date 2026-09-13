import AppKit
import BefoldKit

/// トップレベルの "Bookmarks" メニューの中身を BookmarkStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
///
/// 固定部(追加/削除のトグル・「ブックマークを編集…」)も毎回置き直す。`removeAllItems()` で
/// 一緒に消えるためで、定義そのものは `MainMenuBuilder.addBookmarksFixedItems(to:)` 側にある
/// (理由はそちらの doc)。
///
/// 個別の解除は管理パネル(Bookmarks > ブックマークを編集…)か、該当ファイルを開いて
/// トグルオフする。開けなくなったファイル(削除・worktree ごと消滅)を一括で外す項目を末尾に置く。
/// **この型は `FileReading` を持たない。** 存在確認(stat)はアンマウント済み/応答しない
/// ネットワークマウントで待たされるため、メニュー表示のたびに走らせてはならず、
/// 判定は `MissingBookmarksPruner`(ユーザーが項目を選んだときだけ走る)に閉じている。
@MainActor
final class BookmarksMenuController: NSObject, NSMenuDelegate {
    private let library: () -> BookmarkLibrary
    private let openHandler: (URL) -> Void
    private let removeMissingHandler: () -> Void

    init(
        library: @escaping () -> BookmarkLibrary,
        openHandler: @escaping (URL) -> Void,
        removeMissingHandler: @escaping () -> Void
    ) {
        self.library = library
        self.openHandler = openHandler
        self.removeMissingHandler = removeMissingHandler
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        MainMenuBuilder.addBookmarksFixedItems(to: menu)
        // 表示名(別名 ?? ファイル名)の順。パス列は別名を付けても親ディレクトリのまま。
        let entries = library().entriesSortedByDisplayName
        guard !entries.isEmpty else { return }
        menu.addItem(.separator())
        menu.addFileItems(
            urls: entries.map(\.url), titles: entries.map(\.displayName),
            action: #selector(openBookmark(_:)), target: self
        )
        menu.addItem(.separator())
        menu.addActionItem(
            title: String(localized: "menu.bookmarks.removeMissing", bundle: .l10n),
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
