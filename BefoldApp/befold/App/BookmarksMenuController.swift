import AppKit
import BefoldKit

/// トップレベルの "Bookmarks" メニューの中身を BookmarkStore の一覧から自前で構築する。
/// RecentDocumentsMenuController と同じく NSMenuDelegate で表示直前に毎回再生成する。
///
/// 固定部(追加/削除のトグル・「ブックマークを編集…」)も毎回置き直す。`removeAllItems()` で
/// 一緒に消えるためで、定義そのものは `MainMenuBuilder.addBookmarksFixedItems(to:)` 側にある
/// (理由はそちらの doc)。
///
/// フォルダーはサブメニューとして再帰的に組む(各階層でフォルダーが先、エントリが後。順序は
/// `BookmarkLibrary.children(of:)` が決める)。
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
        let library = library()
        guard !library.entries.isEmpty || !library.folders.isEmpty else { return }
        menu.addItem(.separator())
        addChildren(of: [], in: library, to: menu)
        menu.addItem(.separator())
        menu.addActionItem(
            title: String(localized: "menu.bookmarks.removeMissing", bundle: .l10n),
            action: #selector(removeMissingBookmarks(_:)), target: self
        )
    }

    /// `parent` 直下をメニューへ足す。フォルダーはサブメニューにして中身を再帰で組む。
    /// 表示名(別名 ?? ファイル名)が左列、パス列は別名を付けても親ディレクトリのまま。
    private func addChildren(of parent: [String], in library: BookmarkLibrary, to menu: NSMenu) {
        let children = library.children(of: parent)
        for folder in children.folders {
            addChildren(of: folder.path, in: library, to: menu.addSubmenu(title: folder.name))
        }
        guard !children.entries.isEmpty else { return }
        menu.addFileItems(
            urls: children.entries.map(\.url), titles: children.entries.map(\.displayName),
            action: #selector(openBookmark(_:)), target: self
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
