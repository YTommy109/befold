import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ツールバー項目の構成・状態・ファイル切替に伴うライブ更新を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替える。
/// switchFile の存在ガードが store.fileReader 経由になった(TASK-116.12)ため、
/// 切替時のツールバー更新も InMemoryFileReader でモック化して unit で検証する。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerToolbarTests {
    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    private func makeController(
        file: URL, contents: String = "graph TD;", extraFiles: [URL] = []
    ) -> ViewerWindowController {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerToolbarTests")
        var files = [file.path: contents]
        for extra in extraFiles {
            files[extra.path] = contents
        }
        return ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: ViewerStore(
                watcherFactory: { _, _, _ in MockFileWatcher() },
                fileReader: InMemoryFileReader(files: files),
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

    // MARK: - ファイル切替に伴うライブ更新

    @Test("ファイル切替でブックマークボタンが新しいファイルの状態に更新される")
    func bookmarkItemUpdatesOnFileSwitch() async throws {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeController(file: fileA, extraFiles: [fileB])
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
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeController(file: fileA, extraFiles: [fileB])
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
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeController(file: fileA, extraFiles: [fileB])
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
