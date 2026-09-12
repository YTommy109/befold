import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

@Suite
@MainActor
struct BookmarksMenuControllerTests {
    private func makeController(
        urls: [URL],
        onOpen: @escaping (URL) -> Void = { _ in },
        onRemoveMissing: @escaping () -> Void = {}
    ) -> BookmarksMenuController {
        BookmarksMenuController(
            bookmarkedURLs: { urls }, openHandler: onOpen, removeMissingHandler: onRemoveMissing
        )
    }

    /// 一括除去の項目(末尾)。固定部のトグルは responder chain へ流すため target を持たず、
    /// ブックマークが 0 件のときはそれが末尾に来るので除く。
    private func removeMissingItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.last.flatMap { $0.isSeparatorItem || $0.target == nil ? nil : $0 }
    }

    @Test("ブックマーク済み URL からファイル名アルファベット順でメニュー項目を構築する")
    func populatesMenuItemsSortedByFileName() {
        let urls = [
            URL(fileURLWithPath: "/tmp/zebra.mmd"),
            URL(fileURLWithPath: "/tmp/apple.md"),
        ]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        // 先頭はトグル + セパレータ、末尾はセパレータ + 一括除去。
        #expect(menu.items.count == 6)
        #expect(menu.items[2].title == "apple.md\t/tmp")
        #expect(menu.items[3].title == "zebra.mmd\t/tmp")
        #expect(menu.items[2].attributedTitle?.string == "apple.md\t/tmp")
        #expect(menu.items[2].representedObject as? URL == urls[1])
        #expect(menu.items[2].image != nil)
    }

    @Test("ブックマークが無い場合は固定部のトグルだけが残る")
    func showsOnlyToggleWhenBookmarksIsEmpty() throws {
        let controller = makeController(urls: [])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 1)
        let toggle = try #require(menu.items.first)
        #expect(toggle.action == #selector(ViewerWindowController.toggleBookmark(_:)))
    }

    @Test("繰り返し更新しても項目が重複しない")
    func doesNotDuplicateItemsOnRepeatedUpdate() {
        let urls = [URL(fileURLWithPath: "/tmp/diagram.mmd")]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 5)
        #expect(menu.items[2].title == "diagram.mmd\t/tmp")
    }

    /// 固定部のトグルは `removeAllItems()` で一緒に消えるため、再生成のたびに置き直す。
    /// ここが落ちると Help > キーボードショートカット から ⌘D が消える——一覧の
    /// スナップショットは `NSApp.mainMenu` へ設定する**前の**メニュー木から取るので、
    /// delegate が表示直前に作る項目は最初から載らない。
    @Test("再生成しても先頭にブックマークのトグルが残る")
    func keepsBookmarkToggleAfterRebuild() throws {
        let controller = makeController(urls: [URL(fileURLWithPath: "/tmp/diagram.mmd")])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        let toggle = try #require(menu.items.first)
        #expect(toggle.action == #selector(ViewerWindowController.toggleBookmark(_:)))
        #expect(toggle.keyEquivalent == BookmarkShortcut.keyEquivalent)
    }

    @Test("ブックマークが 1 件でもあれば末尾に一括除去の項目が出る")
    func offersRemoveMissingItemWhenBookmarksExist() throws {
        let controller = makeController(urls: [URL(fileURLWithPath: "/tmp/diagram.mmd")])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[3].isSeparatorItem)
        let item = try #require(removeMissingItem(in: menu))
        #expect(!item.title.isEmpty)
    }

    @Test("ブックマークが無ければ一括除去の項目も出ない")
    func hidesRemoveMissingItemWhenBookmarksIsEmpty() {
        let controller = makeController(urls: [])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(removeMissingItem(in: menu) == nil)
    }

    @Test("一括除去の項目を選ぶと removeMissingHandler が呼ばれる")
    func invokesRemoveMissingHandlerWhenItemSelected() throws {
        var calls = 0
        let controller = makeController(
            urls: [URL(fileURLWithPath: "/tmp/diagram.mmd")], onRemoveMissing: { calls += 1 }
        )
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        let item = try #require(removeMissingItem(in: menu))
        _ = item.target?.perform(item.action, with: item)

        #expect(calls == 1)
    }

    /// 存在確認(stat)はネットワークマウントで待たされうるため、メニュー表示では行わない
    /// (`MissingBookmarksPruner` に閉じている)。ここで永続化が動かないことを固定して、
    /// 「表示のたびに欠落を掃除する」実装へ逆戻りしたら落ちるようにする。
    @Test("メニュー表示はブックマークの永続化を一切書き換えない")
    func menuUpdateDoesNotMutatePersistedBookmarks() {
        let defaults = makeIsolatedDefaults(prefix: "BookmarksMenuControllerTests")
        let store = BookmarkStore(defaults: defaults)
        let missing = URL(fileURLWithPath: "/tmp/deleted-worktree/gone.md")
        store.add(missing)
        let controller = BookmarksMenuController(
            bookmarkedURLs: { store.bookmarkedURLs() }, openHandler: { _ in },
            removeMissingHandler: {}
        )

        controller.menuNeedsUpdate(NSMenu(title: "Bookmarks"))

        #expect(store.bookmarkedURLs() == [missing])
    }

    @Test("メニュー項目を選択すると openHandler に URL が渡される")
    func passesURLToOpenHandlerWhenItemSelected() {
        var opened: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let controller = makeController(urls: [url]) { opened.append($0) }
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[2]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [url])
    }
}
