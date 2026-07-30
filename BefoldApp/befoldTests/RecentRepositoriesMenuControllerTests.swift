import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct RecentRepositoriesMenuControllerTests {
    private func makeController(
        entries: [RecentRepositoryEntry],
        onPrune: @escaping () -> Void = {},
        onOpen: @escaping (RecentRepositoryEntry) -> Void = { _ in },
        onClear: @escaping () -> Void = {}
    ) -> RecentRepositoriesMenuController {
        RecentRepositoriesMenuController(
            pruneMissing: onPrune, entries: { entries }, openHandler: onOpen, clearHandler: onClear
        )
    }

    private func entry(_ name: String) -> RecentRepositoryEntry {
        RecentRepositoryEntry(rootPath: "/tmp/\(name)", label: name, lastTabGroup: nil)
    }

    @Test("ラベルでメニュー項目が構築される")
    func populatesMenuItemsFromEntries() {
        let entries = [entry("befold"), entry("befold (worktree-a)")]
        let controller = makeController(entries: entries)
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 4)
        #expect(menu.items[0].title == "befold")
        #expect(menu.items[1].title == "befold (worktree-a)")
        #expect(menu.items[0].representedObject as? RecentRepositoryEntry == entries[0])
        #expect(menu.items[2].isSeparatorItem)
        #expect(menu.items[3].title == String(localized: "menu.file.clearMenu", bundle: .l10n))
    }

    @Test("表示直前に毎回 pruneMissing が呼ばれる")
    func callsPruneMissingOnEveryUpdate() {
        var pruneCount = 0
        let controller = makeController(entries: [], onPrune: { pruneCount += 1 })
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        controller.menuNeedsUpdate(menu)

        #expect(pruneCount == 2)
    }

    @Test("一覧が空でも Clear Menu だけは表示される")
    func showsOnlyClearMenuWhenEntriesIsEmpty() {
        let controller = makeController(entries: [])
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items.count == 1)
        #expect(menu.items[0].title == String(localized: "menu.file.clearMenu", bundle: .l10n))
    }

    @Test("項目選択で openHandler に該当エントリが渡る")
    func passesEntryToOpenHandlerWhenItemSelected() {
        var opened: [RecentRepositoryEntry] = []
        let target = entry("befold")
        let controller = makeController(entries: [target], onOpen: { opened.append($0) })
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [target])
    }

    @Test("Clear Menu 選択でクリアハンドラが呼ばれる")
    func invokesClearHandlerWhenClearMenuSelected() {
        var cleared = false
        let controller = makeController(entries: [], onClear: { cleared = true })
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = menu.items[0]
        _ = item.target?.perform(item.action, with: item)

        #expect(cleared)
    }
}
