import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ツールバー項目の構成・状態・ファイル切替に伴うライブ更新を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入する。
/// switchFile の存在ガードが store.fileReader 経由になった(TASK-116.12)ため、
/// 切替時のツールバー更新も InMemoryFileReader でモック化して unit で検証する。
/// コンテンツペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証はこのスイートに置かない。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowControllerToolbarTests {
    private func makeController(
        file: URL, contents: String = "graph TD;", extraFiles: [URL] = [],
        bookmarkStore: BookmarkStore? = nil
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, extraFiles: extraFiles, contents: contents,
            prefix: "ViewerWindowControllerToolbarTests", bookmarkStore: bookmarkStore
        ).controller
    }

    @Test(
        "既定アイテム順・戻る/進むアイテムの isNavigational・初期無効状態を1つのウィンドウで検証する"
    )
    func defaultItemsAreOrderedNavigationalAndInitiallyDisabled() throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/a.mmd"))
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        // 既定アイテムは サイドバー開閉/仕切り/戻る/進む/可変スペース/行番号/モード切替/
        // (差分レイアウト)/ブックマーク の順。差分レイアウトはフィーチャーゲートの内側にあり、
        // stable ビルドでは構成に載らない(無効化ではなく不在)。
        let identifiers = controller.toolbarController.toolbarDefaultItemIdentifiers(toolbar)
        let diffLayout: [NSToolbarItem.Identifier] = FeatureGate.isSourceDiffEnabled ? [.init("diffLayout")] : []
        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("lineNumbers"), .init("modeToggle"),
        ] + diffLayout + [.init("bookmark")])

        for identifier in ["historyBack", "historyForward"] {
            let item = try #require(controller.toolbarController.toolbar(
                toolbar, itemForItemIdentifier: .init(identifier), willBeInsertedIntoToolbar: false
            ))
            // 戻る・進むアイテムはナビゲーション項目としてタイトルより先頭側に配置される
            #expect(item.isNavigational, "\(identifier) は isNavigational であるべき")

            // 履歴が無い間、戻る・進むアイテムは無効
            let button = try #require(item.view as? HistoryButtonView)
            #expect(button.isEnabled == false, "\(identifier) は初期状態で無効のはず")
        }
    }

    /// ゲート OFF 相当(stable)のツールバー構成をライブなゲート値に依らず検証する。
    /// ゲート越しの検証は動いているビルドの側しか通らないため、構成の両分岐はここで押さえる。
    @Test(
        "ツールバー構成は差分ゲートに応じて差分レイアウト項目とセグメント数を切り替える",
        arguments: [true, false]
    )
    func toolbarCompositionFollowsSourceDiffGate(isSourceDiffEnabled: Bool) {
        let identifiers = ViewerToolbarController.defaultItemIdentifiers(
            isSourceDiffEnabled: isSourceDiffEnabled
        )
        let diffLayout: [NSToolbarItem.Identifier] = isSourceDiffEnabled ? [.init("diffLayout")] : []
        #expect(identifiers == [
            .toggleSidebar, .sidebarTrackingSeparator,
            .init("historyBack"), .init("historyForward"),
            .flexibleSpace, .init("lineNumbers"), .init("modeToggle"),
        ] + diffLayout + [.init("bookmark")])

        let modes = ModeSegments.modes(isSourceDiffEnabled: isSourceDiffEnabled)
        #expect(modes.count == (isSourceDiffEnabled ? 3 : 2))
        #expect(modes.contains(.diff) == isSourceDiffEnabled)
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
        // fileType は非同期読み込みの完了(apply())と同時にのみ確定するため、完了を待つ。
        // 壁時計予算のポーリング(waitUntilOnMainActor)ではなく loadTask を await する。
        // full suite では多数の `@MainActor` スイートがメインアクターを占有するため、
        // メインアクターの一巡に 5〜8 秒かかることがあり(TASK-327 の実測)、10 秒予算の
        // ポーリングは負荷次第で読み込み完了前に尽きて失敗していた。await なら混雑は
        // 遅延になるだけで失敗にはならない(上限はスイートの .timeLimit が担保する)。
        await codeController.store.loadTask?.value

        codeController.toolbarController.refreshToolbarState()

        let codeButton = try #require(codeController.toolbarController.toolbar(
            codeToolbar, itemForItemIdentifier: .init("lineNumbers"), willBeInsertedIntoToolbar: false
        )?.view as? NSButton)
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

    /// コード種別は保存モードが .rendered でも実際にはソースを出しているため、
    /// 選べないプレビュー側が選択済みに見えないこと(effectiveDisplayMode)まで測る。
    @Test("モード切替セグメントの有効状態と選択はファイル種別で決まる", arguments: [
        // (ファイル名, 内容, プレビュー有効, ソース有効, ソース側が選択済み)
        ("a.mmd", "graph TD;", true, true, false), // レンダリング可能なテキスト: 両方有効・プレビュー選択
        ("a.swift", "let x = 1", false, true, true), // コード: プレビュー不可・ソース固定
    ])
    func modeToggleReflectsFileType(
        name: String, contents: String, previewEnabled: Bool, sourceEnabled: Bool, sourceSelected: Bool
    ) async throws {
        let controller = makeController(file: URL(fileURLWithPath: "/mock/\(name)"), contents: contents)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)
        // fileType は非同期読み込みの完了(apply())と同時に確定するため、完了を待つ。
        await controller.store.loadTask?.value

        controller.toolbarController.refreshToolbarState()

        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("modeToggle") })
        let segmented = try #require(liveItem.view as? NSSegmentedControl)
        #expect(segmented.isEnabled(forSegment: 0) == previewEnabled)
        #expect(segmented.isEnabled(forSegment: 1) == sourceEnabled)
        #expect(segmented.selectedSegment == (sourceSelected ? 1 : 0))
        // 差分セグメントの有無はフィーチャーゲートと一致する(AC#1 / AC#2)。
        #expect(segmented.segmentCount == (FeatureGate.isSourceDiffEnabled ? 3 : 2))
    }

    /// AC#3: レイアウトトグルは差分表示を選んでいない間は無効。出したまま無効にするのは、
    /// 出現・消滅させるとツールバーの幅が動くため。
    @Test("差分レイアウトトグルは差分表示中だけ有効になる")
    func diffLayoutToggleEnabledOnlyInDiffMode() async throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let file = URL(fileURLWithPath: "/mock/a.swift")
        let controller = makeController(file: file, contents: "let x = 1")
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)
        await controller.store.loadTask?.value
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file

        controller.setDisplayMode(.source)
        controller.toolbarController.refreshToolbarState()
        let item = try #require(toolbar.items.first { $0.itemIdentifier == .init("diffLayout") })
        #expect((item.view as? NSButton)?.isEnabled == false)

        controller.setDisplayMode(.diff)
        controller.toolbarController.refreshToolbarState()
        #expect((item.view as? NSButton)?.isEnabled == true)
    }

    // MARK: - 外部からの状態変更に伴う再同期

    @Test("GUI のトグルを経ないブックマーク変更も refreshToolbarState() で実アイテムへ反映される")
    func refreshToolbarStateAppliesExternalBookmarkChange() throws {
        let file = URL(fileURLWithPath: "/mock/a.mmd")
        let bookmarkStore = BookmarkStore(
            defaults: makeIsolatedDefaults(prefix: "ToolbarRefreshExternalBookmark")
        )
        let controller = makeController(file: file, bookmarkStore: bookmarkStore)
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let button = try #require(liveItem.view as? NSButton)
        #expect(button.contentTintColor == nil)

        // CLI 転送など、ウィンドウのトグル操作を経ずストアだけが変わる経路を模す。
        bookmarkStore.toggle(file)
        controller.toolbarController.refreshToolbarState()

        #expect(button.contentTintColor == .controlAccentColor)
    }

    // MARK: - ファイル切替に伴うライブ更新

    @Test("ファイル切替でブックマークボタンが新ファイルの状態に、戻るアイテムが履歴の有無に更新される")
    func fileSwitchUpdatesBookmarkAndHistoryToolbarItemsLive() async throws {
        let fileA = URL(fileURLWithPath: "/mock/a.mmd")
        let fileB = URL(fileURLWithPath: "/mock/b.mmd")
        let controller = makeController(file: fileA, extraFiles: [fileB])
        defer { controller.close() }
        let toolbar = try #require(controller.window?.toolbar)

        let bookmarkItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("bookmark") })
        let bookmarkButton = try #require(bookmarkItem.view as? NSButton)
        let historyItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("historyBack") })
        let historyButton = try #require(historyItem.view as? HistoryButtonView)
        #expect(historyButton.isEnabled == false)

        controller.toggleBookmark(nil)
        #expect(bookmarkButton.contentTintColor == .controlAccentColor)

        controller.switchFile(to: fileB)

        // ファイル切替で履歴ができると戻るアイテムが有効になる(即時反映)
        #expect(historyButton.isEnabled == true)
        // toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:) は呼び出しごとに
        // 現在の store 状態から新規にアイテムを生成する。ツールバーのカスタマイズ等で
        // アイテムが再生成される経路でも、履歴あり状態が反映されることを確認する。
        let recreatedHistoryItem = try #require(controller.toolbarController.toolbar(
            toolbar, itemForItemIdentifier: .init("historyBack"), willBeInsertedIntoToolbar: false
        ))
        #expect((recreatedHistoryItem.view as? HistoryButtonView)?.isEnabled == true)
        // onContentReloaded はファイル読み込み完了後に非同期で発火するため、ブックマークの
        // 反映のみポーリングで待つ。
        await waitUntilOnMainActor { bookmarkButton.contentTintColor == nil }
        #expect(bookmarkButton.contentTintColor == nil)

        controller.navigateHistory(by: -1)
        #expect(historyButton.isEnabled == false)
    }
}
