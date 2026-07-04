import AppKit
@testable import mmdview
import Testing

@Suite
@MainActor
struct RecentDocumentsMenuControllerTests {
    private func makeController(
        urls: [URL],
        onOpen: @escaping (URL) -> Void = { _ in },
        onClear: @escaping () -> Void = {}
    ) -> RecentDocumentsMenuController {
        RecentDocumentsMenuController(
            recentURLs: { urls }, openHandler: onOpen, clearHandler: onClear
        )
    }

    @Test
    func populatesMenuItemsFromRecentURLs() {
        let urls = [
            URL(fileURLWithPath: "/tmp/diagram.mmd"),
            URL(fileURLWithPath: "/tmp/note.md"),
        ]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Open Recent")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 4)
        #expect(menu.items[0].title == "diagram.mmd")
        #expect(menu.items[1].title == "note.md")
        #expect(menu.items[0].representedObject as? URL == urls[0])
        #expect(menu.items[0].image != nil)
        #expect(menu.items[2].isSeparatorItem)
        #expect(menu.items[3].title == "Clear Menu")
        #expect(menu.items[3].target === controller)
    }

    @Test("Clear Menu 選択でクリアハンドラが呼ばれる")
    func invokesClearHandlerWhenClearMenuSelected() {
        var cleared = false
        let controller = makeController(urls: [], onClear: { cleared = true })
        let menu = NSMenu(title: "Open Recent")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(cleared)
    }

    @Test
    func showsOnlyClearMenuWhenRecentsIsEmpty() {
        let controller = makeController(urls: [])
        let menu = NSMenu(title: "Open Recent")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 1)
        #expect(menu.items[0].title == "Clear Menu")
    }

    @Test
    func doesNotDuplicateItemsOnRepeatedUpdate() {
        let urls = [URL(fileURLWithPath: "/tmp/diagram.mmd")]
        let controller = makeController(urls: urls)
        let menu = NSMenu(title: "Open Recent")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 3)
        #expect(menu.items[0].title == "diagram.mmd")
    }

    @Test
    func passesURLToOpenHandlerWhenItemSelected() {
        var opened: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        let controller = makeController(urls: [url]) { opened.append($0) }
        let menu = NSMenu(title: "Open Recent")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [url])
    }
}
