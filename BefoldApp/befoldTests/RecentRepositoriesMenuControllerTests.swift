import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct RecentRepositoriesMenuControllerTests {
    private func makeController(
        entries: [RecentRepositoryEntry],
        worktrees: [String: [GitWorktree]] = [:],
        onOpen: @escaping (RecentRepositoryEntry) -> Void = { _ in },
        onClear: @escaping () -> Void = {}
    ) -> RecentRepositoriesMenuController {
        RecentRepositoriesMenuController(
            entries: { entries },
            worktrees: { worktrees[$0.path] ?? [] },
            openHandler: onOpen,
            clearHandler: onClear
        )
    }

    private func entry(_ name: String) -> RecentRepositoryEntry {
        RecentRepositoryEntry(rootPath: "/tmp/\(name)", label: name, lastTabGroup: nil)
    }

    /// worktree エントリ。ラベルは本体の記録時規約("本体 (worktree名)")に合わせる。
    private func worktreeEntry(
        _ name: String, mainRoot: String, tabGroup: SessionLayout.TabGroup? = nil
    ) -> RecentRepositoryEntry {
        RecentRepositoryEntry(
            rootPath: "/tmp/\(name)",
            label: "\(URL(fileURLWithPath: mainRoot).lastPathComponent) (\(name))",
            lastTabGroup: tabGroup,
            mainRootPath: mainRoot
        )
    }

    private func worktree(_ path: String, isMain: Bool = false) -> GitWorktree {
        GitWorktree(root: URL(fileURLWithPath: path), isMain: isMain)
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

    @Test("worktree を持たないリポジトリはフラットな1項目になる")
    func keepsRepositoryWithoutWorktreesFlat() {
        let controller = makeController(
            entries: [entry("befold")],
            worktrees: ["/tmp/befold": [worktree("/tmp/befold", isMain: true)]]
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items[0].title == "befold")
        #expect(menu.items[0].submenu == nil)
        #expect(menu.items[0].action != nil)
    }

    @Test("worktree を持つリポジトリは親項目とサブメニューに畳まれる")
    func groupsWorktreesUnderParentItem() {
        let controller = makeController(
            entries: [worktreeEntry("wt-a", mainRoot: "/tmp/befold"), entry("befold")],
            worktrees: [
                "/tmp/befold": [
                    worktree("/tmp/befold", isMain: true), worktree("/tmp/wt-a"), worktree("/tmp/wt-b"),
                ],
            ]
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        // 親1件 + セパレータ + Clear Menu。
        #expect(menu.items.count == 3)
        #expect(menu.items[0].title == "befold")
        let submenu = menu.items[0].submenu
        #expect(submenu?.items.map(\.title) == ["befold", "wt-a", "wt-b"])
    }

    @Test("親項目は見出しのみで選択しても何も開かない")
    func parentItemHasNoAction() {
        var opened: [RecentRepositoryEntry] = []
        let controller = makeController(
            entries: [entry("befold")],
            worktrees: ["/tmp/befold": [worktree("/tmp/befold", isMain: true), worktree("/tmp/wt-a")]],
            onOpen: { opened.append($0) }
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        // 親項目は見出し。submenu を付けた時点で AppKit が target/action(submenuAction:)を
        // 自前で差し込むため、そこは検証せず「コントローラへ届かない」ことを確かめる。
        let parent = menu.items[0]
        #expect(parent.submenu != nil)
        #expect(parent.representedObject == nil)
        // 「開く」動作はサブメニュー項目側の action。それを親項目に対して直接叩いても何も起きない。
        if let openAction = parent.submenu?.items[0].action {
            controller.perform(openAction, with: parent)
        }

        #expect(opened.isEmpty)
    }

    @Test("サブメニューの記憶済み worktree は保存済みエントリで開かれる")
    func opensRememberedEntryFromSubmenu() throws {
        var opened: [RecentRepositoryEntry] = []
        let remembered = worktreeEntry(
            "wt-a", mainRoot: "/tmp/befold",
            tabGroup: SessionLayout.TabGroup(paths: ["/tmp/wt-a/a.md"], selectedPath: "/tmp/wt-a/a.md")
        )
        let controller = makeController(
            entries: [remembered, entry("befold")],
            worktrees: ["/tmp/befold": [worktree("/tmp/befold", isMain: true), worktree("/tmp/wt-a")]],
            onOpen: { opened.append($0) }
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = try #require(menu.items[0].submenu?.items[1])
        _ = item.target?.perform(item.action, with: item)

        #expect(opened == [remembered])
    }

    @Test("記憶の無い worktree は tabGroup なしの合成エントリで開かれる")
    func opensSynthesizedEntryForUnrecordedWorktree() throws {
        var opened: [RecentRepositoryEntry] = []
        let controller = makeController(
            entries: [entry("befold")],
            worktrees: ["/tmp/befold": [worktree("/tmp/befold", isMain: true), worktree("/tmp/wt-new")]],
            onOpen: { opened.append($0) }
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)
        let item = try #require(menu.items[0].submenu?.items[1])
        _ = item.target?.perform(item.action, with: item)

        #expect(opened.count == 1)
        #expect(opened.first?.label == "wt-new")
        #expect(opened.first?.lastTabGroup == nil)
        #expect(opened.first?.mainRootPath == URL(fileURLWithPath: "/tmp/befold").normalizedPathKey)
    }

    @Test("カタログに無い記憶済みエントリもサブメニュー末尾に残る")
    func keepsRememberedEntryMissingFromCatalog() {
        let removed = worktreeEntry("wt-gone", mainRoot: "/tmp/befold")
        let controller = makeController(
            entries: [removed, entry("befold")],
            worktrees: ["/tmp/befold": [worktree("/tmp/befold", isMain: true), worktree("/tmp/wt-a")]]
        )
        let menu = NSMenu(title: "Recent Repositories")

        controller.menuNeedsUpdate(menu)

        #expect(menu.items[0].submenu?.items.map(\.title) == ["befold", "wt-a", "befold (wt-gone)"])
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
