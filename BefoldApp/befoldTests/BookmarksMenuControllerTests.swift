import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

@Suite
@MainActor
struct BookmarksMenuControllerTests {
    /// 固定部は「トグル」「ブックマークを編集…」の 2 項目。一覧はその後ろのセパレータから始まる。
    private static let fixedItemCount = 2
    private static let firstListIndex = fixedItemCount + 1

    private func makeController(
        urls: [URL],
        onOpen: @escaping (URL) -> Void = { _ in },
        onRemoveMissing: @escaping () -> Void = {}
    ) -> BookmarksMenuController {
        makeController(
            library: BookmarkLibrary(entries: urls.map { BookmarkEntry(path: $0.path) }),
            onOpen: onOpen, onRemoveMissing: onRemoveMissing
        )
    }

    private func makeController(
        library: BookmarkLibrary,
        onOpen: @escaping (URL) -> Void = { _ in },
        onRemoveMissing: @escaping () -> Void = {}
    ) -> BookmarksMenuController {
        BookmarksMenuController(
            library: { library }, openHandler: onOpen, removeMissingHandler: onRemoveMissing
        )
    }

    /// 一括除去の項目(末尾)。固定部は responder chain へ流すため target を持たず、
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

        // 先頭は固定部 2 項目 + セパレータ、末尾はセパレータ + 一括除去。
        let first = Self.firstListIndex
        #expect(menu.items.count == Self.fixedItemCount + 5)
        #expect(menu.items[first].title == "apple.md\t/tmp")
        #expect(menu.items[first + 1].title == "zebra.mmd\t/tmp")
        #expect(menu.items[first].attributedTitle?.string == "apple.md\t/tmp")
        #expect(menu.items[first].representedObject as? URL == urls[1])
        #expect(menu.items[first].image != nil)
    }

    /// 別名は左列にだけ効き、右列のパスと representedObject(開く先)はファイルのまま。
    /// 並びも別名で決まる(別名 "Alpha" が付いた zebra.mmd が apple.md より前に来る)。
    @Test("別名を付けたブックマークは別名で表示され、別名の順に並ぶ")
    func showsAliasInsteadOfFileName() {
        let zebra = URL(fileURLWithPath: "/tmp/zebra.mmd")
        let apple = URL(fileURLWithPath: "/tmp/apple.md")
        let library = BookmarkLibrary(entries: [
            BookmarkEntry(path: zebra.path, alias: "Alpha"),
            BookmarkEntry(path: apple.path),
        ])
        let controller = makeController(library: library)
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        let first = Self.firstListIndex
        #expect(menu.items[first].title == "Alpha\t/tmp")
        #expect(menu.items[first].representedObject as? URL == zebra)
        #expect(menu.items[first + 1].title == "apple.md\t/tmp")
    }

    @Test("ブックマークが無い場合は固定部だけが残る")
    func showsOnlyFixedItemsWhenBookmarksIsEmpty() throws {
        let controller = makeController(urls: [])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == Self.fixedItemCount)
        let toggle = try #require(menu.items.first)
        #expect(toggle.action == #selector(ViewerWindowController.toggleBookmark(_:)))
        #expect(menu.items[1].action == #selector(AppDelegate.showBookmarkManager(_:)))
    }

    @Test("繰り返し更新しても項目が重複しない")
    func doesNotDuplicateItemsOnRepeatedUpdate() {
        let urls = [URL(fileURLWithPath: "/tmp/diagram.mmd")]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == Self.fixedItemCount + 4)
        #expect(menu.items[Self.firstListIndex].title == "diagram.mmd\t/tmp")
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

    /// 「ブックマークを編集…」も固定部なので、再生成のたびに置き直される。
    @Test("再生成しても固定部の「ブックマークを編集…」が残る")
    func keepsEditItemAfterRebuild() {
        let controller = makeController(urls: [URL(fileURLWithPath: "/tmp/diagram.mmd")])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        let editItems = menu.items.filter { $0.action == #selector(AppDelegate.showBookmarkManager(_:)) }
        #expect(editItems.count == 1)
        #expect(menu.items.firstIndex { $0 === editItems.first } == 1)
    }

    @Test("ブックマークが 1 件でもあれば末尾に一括除去の項目が出る")
    func offersRemoveMissingItemWhenBookmarksExist() throws {
        let controller = makeController(urls: [URL(fileURLWithPath: "/tmp/diagram.mmd")])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items[Self.fixedItemCount].isSeparatorItem)
        #expect(menu.items[Self.firstListIndex + 1].isSeparatorItem)
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
            library: { store.library() }, openHandler: { _ in },
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
        let item = menu.items[Self.firstListIndex]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [url])
    }
}
