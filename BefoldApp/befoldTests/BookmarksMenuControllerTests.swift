import AppKit
@testable import befold
import BefoldKit
import Testing

@Suite
@MainActor
struct BookmarksMenuControllerTests {
    private func makeController(
        urls: [URL],
        onOpen: @escaping (URL) -> Void = { _ in }
    ) -> BookmarksMenuController {
        BookmarksMenuController(bookmarkedURLs: { urls }, openHandler: onOpen)
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

        #expect(menu.items.count == 2)
        #expect(menu.items[0].title == "apple.md")
        #expect(menu.items[1].title == "zebra.mmd")
        #expect(menu.items[0].representedObject as? URL == urls[1])
        #expect(menu.items[0].image != nil)
    }

    @Test("ブックマークが無い場合はメニュー項目が空")
    func showsNoItemsWhenBookmarksIsEmpty() {
        let controller = makeController(urls: [])
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.isEmpty)
    }

    @Test("繰り返し更新しても項目が重複しない")
    func doesNotDuplicateItemsOnRepeatedUpdate() {
        let urls = [URL(fileURLWithPath: "/tmp/diagram.mmd")]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 1)
        #expect(menu.items[0].title == "diagram.mmd")
    }

    @Test("メニュー項目を選択すると openHandler に URL が渡される")
    func passesURLToOpenHandlerWhenItemSelected() {
        var opened: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let controller = makeController(urls: [url]) { opened.append($0) }
        let menu = NSMenu(title: "Bookmarks")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [url])
    }
}
