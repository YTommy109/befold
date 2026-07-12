import AppKit
@testable import befold
import Foundation
import Testing

@Suite
@MainActor
struct ViewerWindowControllerToolbarTests {
    private func makeController(file: URL) -> ViewerWindowController {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerToolbarTests")
        return ViewerWindowController(
            fileURL: file,
            zoomStore: ZoomStore(defaults: defaults),
            defaults: defaults
        )
    }

    @Test("既定アイテムは サイドバー開閉/仕切り/戻る/進む/可変スペース/モード切替 の順")
    func defaultItemsPlaceHistoryButtonsAfterTrackingSeparator() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let identifiers = controller.toolbarDefaultItemIdentifiers(toolbar)

        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("lineNumbers"), .init("modeToggle"),
        ])
    }

    @Test("行番号アイテムはコード表示中のみ有効")
    func lineNumbersItemEnabledOnlyForCodeContent() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let codeFile = try tmp.file(named: "a.swift", contents: "let x = 1")
        let previewFile = try tmp.file(named: "b.mmd", contents: "graph TD;")

        let codeController = makeController(file: codeFile)
        defer { codeController.close() }
        let codeToolbar = try #require(codeController.window?.toolbar)
        let codeItem = try #require(codeController.toolbar(
            codeToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        ))
        let codeButton = try #require(codeItem.view as? NSButton)
        #expect(codeButton.isEnabled == true)

        let previewController = makeController(file: previewFile)
        defer { previewController.close() }
        let previewToolbar = try #require(previewController.window?.toolbar)
        let previewItem = try #require(previewController.toolbar(
            previewToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        ))
        let previewButton = try #require(previewItem.view as? NSButton)
        #expect(previewButton.isEnabled == false)
    }

    @Test("戻る・進むアイテムはナビゲーション項目としてタイトルより先頭側に配置される")
    func historyItemsAreNavigational() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            #expect(item.isNavigational, "\(identifier) は isNavigational であるべき")
        }
    }

    @Test("履歴が無い間、戻る・進むアイテムは無効")
    func historyItemsDisabledWithoutHistory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            let button = try #require(item.view as? HistoryButtonView)
            #expect(button.isEnabled == false, "\(identifier) は初期状態で無効のはず")
        }
    }

    @Test("ファイル切替で履歴ができると戻るアイテムが有効になる")
    func backItemEnabledAfterFileSwitch() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        controller.switchFile(to: fileB)

        let item = try #require(controller.toolbar(
            toolbar, itemForItemIdentifier: .init("historyBack"), willBeInsertedIntoToolbar: false
        ))
        let button = try #require(item.view as? HistoryButtonView)
        #expect(button.isEnabled == true)
    }

    @Test("履歴状態の変化がツールバー上の実アイテムにライブ反映される")
    func historyBackButtonUpdatesLiveToolbarItemOnFileSwitch() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let liveItem = try #require(toolbar.items.first {
            $0.itemIdentifier == .init("historyBack")
        })
        let button = try #require(liveItem.view as? HistoryButtonView)
        #expect(button.isEnabled == false)

        controller.switchFile(to: fileB)
        #expect(button.isEnabled == true)

        controller.navigateHistory(by: -1)
        #expect(button.isEnabled == false)
    }
}
