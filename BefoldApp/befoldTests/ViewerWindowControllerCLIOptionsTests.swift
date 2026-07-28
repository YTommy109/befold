import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// CLI から渡される表示オプション(隠しファイル・並び順・行番号・ソース/プレビューモード)が
/// ウィンドウオープン時に適用されることを検証する。
///
/// これらは init 時のオプション適用のみが検証対象で、実ファイル内容には依存しないため、
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替えて
/// 実 FS を使わない unit テストとして構成する。
@Suite
@MainActor
struct ViewerWindowControllerCLIOptionsTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/note.md")

    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    private func makePerFileState(
        defaults: UserDefaults
    ) -> PerFileStateStore {
        PerFileStateStore(
            zoom: ZoomStore(defaults: defaults),
            sourceMode: SourceModeStore(defaults: defaults),
            scrollPosition: ScrollPositionStore(defaults: defaults),
            sidebar: SidebarStateStore(defaults: defaults),
            windowFrame: WindowFrameStore(defaults: defaults)
        )
    }

    /// 実ファイル内容・実 watcher を必要としない、モック済みの ViewerStore を作る。
    private func makeMockStore(defaults: UserDefaults, contents: String = "# hi") -> ViewerStore {
        ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: InMemoryFileReader(files: [file.path: contents]),
            defaults: defaults
        )
    }

    @Test("CLI の --source/--preview 指定は保存済みのソース表示モードより優先される")
    func sourceModeOverrideTakesPrecedenceOverSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(false, for: file)
        let perFileState = PerFileStateStore(
            zoom: ZoomStore(defaults: defaults),
            sourceMode: sourceModeStore,
            scrollPosition: ScrollPositionStore(defaults: defaults),
            sidebar: SidebarStateStore(defaults: defaults),
            windowFrame: WindowFrameStore(defaults: defaults)
        )

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults, perFileState: perFileState,
            bookmarkStore: BookmarkStore(defaults: defaults),
            sourceModeOverride: true,
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.isSourceMode)
        // 保存値自体は書き換えない(この起動限りの上書き)。
        #expect(!sourceModeStore.isSourceMode(for: file))
    }

    @Test("CLI のオプション未指定時は保存済みのソース表示モードがそのまま復元される")
    func noSourceModeOverridePreservesSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file)
        let perFileState = PerFileStateStore(
            zoom: ZoomStore(defaults: defaults),
            sourceMode: sourceModeStore,
            scrollPosition: ScrollPositionStore(defaults: defaults),
            sidebar: SidebarStateStore(defaults: defaults),
            windowFrame: WindowFrameStore(defaults: defaults)
        )

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults, perFileState: perFileState,
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }

    @Test("CLI の --line-numbers 指定は showLineNumbers に反映される")
    func lineNumbersOverrideIsAppliedToStore() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            showLineNumbersOverride: true,
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
    }

    @Test("CLI の --line-numbers 指定は保存済みのグローバル設定を書き換えない")
    func lineNumbersOverrideDoesNotPersistToUserDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(false, forKey: "ShowLineNumbers")

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            showLineNumbersOverride: true,
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
        #expect(!defaults.bool(forKey: "ShowLineNumbers"))
    }

    @Test("CLI のオプション未指定時は保存済みの行番号設定がそのまま復元される")
    func noLineNumbersOverridePreservesSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(true, forKey: "ShowLineNumbers")

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            store: makeMockStore(defaults: defaults),
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
    }

    @Test("store を明示注入した場合でも --line-numbers 指定が反映される")
    func lineNumbersOverrideIsAppliedEvenWithExplicitStore() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(false, forKey: "ShowLineNumbers")
        let injectedStore = makeMockStore(defaults: defaults)

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            showLineNumbersOverride: true,
            store: injectedStore,
            directoryLister: noEntries
        )
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
        #expect(!defaults.bool(forKey: "ShowLineNumbers"))
    }

    @Test("CLI の --sort 指定はサイドバーの並び順(FileListModel.sortOrder)に反映される")
    func sortOrderOverrideIsAppliedToFileListModel() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        var receivedSortOrder: befold.SortOrder?

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            initialSortOrder: .alphabetical,
            store: makeMockStore(defaults: defaults),
            directoryLister: { _, sortOrder, _ in
                receivedSortOrder = sortOrder
                return []
            }
        )
        defer { controller.close() }

        #expect(receivedSortOrder == .alphabetical)
        #expect(controller.fileListModel.sortOrder == .alphabetical)
    }
}
