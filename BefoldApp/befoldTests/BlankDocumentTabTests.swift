import AppKit
@testable import befold
import BefoldKit
import Testing

@Suite
@MainActor
struct BlankDocumentTabTests {
    @Test("File メニューの新しいタブは ⌘T を持つ")
    func newTabHasCommandT() throws {
        let file = try #require(MainMenuFixture().submenu(titledKey: "menu.file.title"))
        let item = try #require(file.items.first { $0.keyEquivalent == "t" })
        #expect(item.keyEquivalentModifierMask == .command)
        #expect(item.action == #selector(NSResponder.newWindowForTab(_:)))
    }

    @Test("空タブは選択され、文書や履歴を生成しない")
    func blankTabJoinsWithoutLoadingDocument() throws {
        let file = URL(fileURLWithPath: "/mock/first.md")
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        let first = try #require(fixture.manager.openViewer(for: file)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: first)
        defer { blank.close() }
        let window = try #require(blank.window)

        #expect(window.tabGroup === first.tabGroup)
        #expect(window.tabGroup?.selectedWindow === window)
        #expect(window.representedURL == nil)
        #expect(fixture.manager.allControllers.count == 1)
        #expect(ViewerTabGrouping.viewerPath(of: window) == nil)
    }

    @Test("文書を選ぶと空タブの位置を置き換える")
    func openingDocumentReplacesBlankInPlace() throws {
        let files = ["first", "chosen", "last"].map { URL(fileURLWithPath: "/mock/\($0).md") }
        let fixture = MockedViewerWindowManager(files: files)
        defer { fixture.closeAll() }
        let first = try #require(fixture.manager.openViewer(for: files[0])?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: first)
        defer { blank.close() }
        let blankWindow = try #require(blank.window)
        let last = try #require(fixture.manager.openViewer(
            for: files[2], disposition: .newTab, relativeTo: blankWindow
        )?.window)
        let chosen = try #require(fixture.manager.openViewer(
            for: files[1], disposition: .currentTab, relativeTo: blankWindow
        )?.window)

        #expect(first.tabGroup?.windows == [first, chosen, last])
        #expect(first.tabGroup?.selectedWindow === chosen)
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }

    @Test("単独の空タブは閉じると管理台帳から消える")
    func standaloneBlankIsReleasedOnClose() {
        let fixture = MockedViewerWindowManager(files: [])
        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        #expect(fixture.manager.blankTabs.controllers.count == 1)
        blank.close()
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }
}
