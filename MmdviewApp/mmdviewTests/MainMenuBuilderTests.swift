import AppKit
@testable import mmdview
import Testing

@Suite
@MainActor
struct MainMenuBuilderTests {
    private final class StubMenuDelegate: NSObject, NSMenuDelegate {}

    private func buildMenu() -> NSMenu {
        // swift test のプロセスでは NSApp が未初期化のため、
        // MainMenuBuilder が参照する前に NSApplication.shared で初期化する
        _ = NSApplication.shared
        return MainMenuBuilder.build(
            openAction: #selector(AppDelegate.showOpenPanel),
            helpAction: #selector(AppDelegate.openHelp(_:)),
            recentMenuDelegate: StubMenuDelegate()
        )
    }

    private func submenu(titled title: String, in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.items.first { $0.submenu?.title == title }?.submenu
    }

    @Test("トップレベルは App/File/Edit/View/Window/Help の 6 メニュー")
    func topLevelMenusArePresent() {
        let mainMenu = buildMenu()

        #expect(mainMenu.items.count == 6)
        let titles = mainMenu.items.compactMap(\.submenu?.title)
        #expect(titles.contains("File"))
        #expect(titles.contains("Edit"))
        #expect(titles.contains("View"))
        #expect(titles.contains("Window"))
        #expect(titles.contains("Help"))
    }

    @Test("Edit メニューに Copy(⌘C) と Select All(⌘A) がある")
    func editMenuEnablesCopyAndSelectAll() throws {
        let mainMenu = buildMenu()
        let edit = try #require(submenu(titled: "Edit", in: mainMenu))

        let copy = try #require(edit.items.first { $0.action == #selector(NSText.copy(_:)) })
        #expect(copy.keyEquivalent == "c")
        let selectAll = try #require(edit.items.first { $0.action == #selector(NSText.selectAll(_:)) })
        #expect(selectAll.keyEquivalent == "a")
    }

    @Test("View メニューにズームとフルスクリーンがある")
    func viewMenuHasZoomAndFullScreen() throws {
        let mainMenu = buildMenu()
        let view = try #require(submenu(titled: "View", in: mainMenu))

        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.zoomIn(_:)) })
        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.zoomOut(_:)) })
        #expect(view.items.contains { $0.action == #selector(ViewerWindowController.resetZoom(_:)) })
        let fullScreen = try #require(
            view.items.first { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        )
        #expect(fullScreen.keyEquivalentModifierMask == [.control, .command])
    }

    @Test("File メニューに Print(⌘P) がある")
    func fileMenuHasPrint() throws {
        let mainMenu = buildMenu()
        let file = try #require(submenu(titled: "File", in: mainMenu))

        let print = try #require(
            file.items.first { $0.action == #selector(ViewerWindowController.printDocument(_:)) }
        )
        #expect(print.keyEquivalent == "p")
    }

    @Test("Window メニューにタブ操作項目がある")
    func windowMenuHasTabItems() throws {
        let mainMenu = buildMenu()
        let window = try #require(submenu(titled: "Window", in: mainMenu))

        #expect(window.items.contains { $0.action == #selector(NSWindow.selectNextTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.selectPreviousTab(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.moveTabToNewWindow(_:)) })
        #expect(window.items.contains { $0.action == #selector(NSWindow.mergeAllWindows(_:)) })
    }

    @Test("Help メニューが NSApp.helpMenu に登録される")
    func helpMenuIsRegistered() throws {
        let mainMenu = buildMenu()
        let help = try #require(submenu(titled: "Help", in: mainMenu))

        #expect(NSApp.helpMenu === help)
        #expect(help.items.contains { $0.action == #selector(AppDelegate.openHelp(_:)) })
    }
}
