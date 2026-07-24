import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ファイル切替に伴うツールバーのライブ更新(ブックマーク・履歴ボタンの状態反映)を検証する。
/// 実 switchFile(実 store の読み込み完了)を踏むため製品変更なしにはモック化できず Integration。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerToolbarIntegrationTests {
    private func makeController(file: URL) -> ViewerWindowController {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerToolbarTests")
        return ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults)
        )
    }

    @Test("ファイル切替でブックマークボタンが新しいファイルの状態に更新される")
    func bookmarkItemUpdatesOnFileSwitch() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.mmd", contents: "graph TD;")
        let fileB = try tmp.file(named: "b.mmd", contents: "graph TD;")
        let controller = makeController(file: fileA)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let button = try #require(liveItem.view as? NSButton)

        controller.toggleBookmark(nil)
        #expect(button.contentTintColor == .controlAccentColor)

        controller.switchFile(to: fileB)

        // onContentReloaded はファイル読み込み完了後に非同期で発火するため、反映をポーリングで待つ。
        await waitUntilOnMainActor { button.contentTintColor == nil }
        #expect(button.contentTintColor == nil)
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

        let item = try #require(controller.toolbarController.toolbar(
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
