import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ツールバー項目のうち、実ファイルシステムに依存しない構成・状態
/// (既定アイテム順・ブックマークトグル・行番号有効判定・ナビ項目属性)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替える。
/// ファイル切替でツールバーがライブ更新される挙動は Integration へ移した。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerToolbarTests {
    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    private func makeController(file: URL, contents: String = "graph TD;") -> ViewerWindowController {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerToolbarTests")
        return ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: ViewerStore(
                watcherFactory: { _, _, _ in MockFileWatcher() },
                fileReader: InMemoryFileReader(files: [file.path: contents]),
                defaults: defaults
            ),
            directoryLister: noEntries
        )
    }

    @Test("既定アイテムは サイドバー開閉/仕切り/戻る/進む/可変スペース/行番号/モード切替/ブックマーク の順")
    func defaultItemsPlaceHistoryButtonsAfterTrackingSeparator() throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/a.mmd"))
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let identifiers = controller.toolbarController.toolbarDefaultItemIdentifiers(toolbar)

        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("lineNumbers"), .init("modeToggle"), .init("bookmark"),
        ])
    }

    @Test("ブックマークボタンをクリックすると状態がトグルされアイコン・色に反映される")
    func bookmarkItemTogglesOnClick() throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/a.mmd"))
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let item = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let button = try #require(item.view as? NSButton)
        #expect(button.contentTintColor == nil)

        controller.toggleBookmark(nil)

        #expect(button.contentTintColor == .controlAccentColor)

        controller.toggleBookmark(nil)

        #expect(button.contentTintColor == nil)
    }

    @Test("行番号アイテムはコード表示中のみ有効")
    func lineNumbersItemEnabledOnlyForCodeContent() async throws {
        let codeController = makeController(file: URL(fileURLWithPath: "/mock/a.swift"), contents: "let x = 1")
        defer { codeController.close() }
        let codeToolbar = try #require(codeController.window?.toolbar)
        // toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:) は呼び出しごとに
        // 現在の store 状態から新しいアイテムを生成するため、都度呼び直してポーリングする。
        // fileType は非同期読み込みの完了(apply())と同時にのみ確定するため、
        // 読み込み完了(onContentReloaded による toolbar 更新)を待ってから検証する。
        // ポーリングで true を確認した後に取得し直すと、await の再開点を挟んだ別呼び出しに
        // なり、その間の状態変化と競合しうる。ポーリング中に取得したボタンをそのまま使う。
        func makeCodeButton() -> NSButton? {
            (codeController.toolbarController.toolbar(
                codeToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
            )?.view as? NSButton)
        }
        var codeButtonBox: NSButton?
        await waitUntilOnMainActor {
            let button = makeCodeButton()
            codeButtonBox = button
            return button?.isEnabled == true
        }
        let codeButton = try #require(codeButtonBox)
        #expect(codeButton.isEnabled == true)

        let previewController = makeController(file: URL(fileURLWithPath: "/mock/b.mmd"))
        defer { previewController.close() }
        let previewToolbar = try #require(previewController.window?.toolbar)
        let previewItem = try #require(previewController.toolbarController.toolbar(
            previewToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        ))
        let previewButton = try #require(previewItem.view as? NSButton)
        #expect(previewButton.isEnabled == false)
    }

    @Test("戻る・進むアイテムはナビゲーション項目としてタイトルより先頭側に配置される")
    func historyItemsAreNavigational() throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/a.mmd"))
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbarController.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            #expect(item.isNavigational, "\(identifier) は isNavigational であるべき")
        }
    }

    @Test("履歴が無い間、戻る・進むアイテムは無効")
    func historyItemsDisabledWithoutHistory() throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/a.mmd"))
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbarController.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            let button = try #require(item.view as? HistoryButtonView)
            #expect(button.isEnabled == false, "\(identifier) は初期状態で無効のはず")
        }
    }
}
