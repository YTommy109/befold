import AppKit
@testable import befold
import Foundation
import Testing

/// CLI から渡される表示オプション(TASK-73.3: 隠しファイル・並び順・行番号・ソース/プレビューモード)が
/// ウィンドウオープン時に適用されることを検証する。
@Suite
@MainActor
struct ViewerWindowControllerCLIOptionsTests {
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

    @Test("CLI の --source/--preview 指定は保存済みのソース表示モードより優先される")
    func sourceModeOverrideTakesPrecedenceOverSavedValue() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
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
            fileURL: file, defaults: defaults, perFileState: perFileState, sourceModeOverride: true
        )
        defer { controller.close() }

        #expect(controller.isSourceMode)
        // 保存値自体は書き換えない(この起動限りの上書き)。
        #expect(!sourceModeStore.isSourceMode(for: file))
    }

    @Test("CLI のオプション未指定時は保存済みのソース表示モードがそのまま復元される")
    func noSourceModeOverridePreservesSavedValue() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
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

        let controller = ViewerWindowController(fileURL: file, defaults: defaults, perFileState: perFileState)
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }

    @Test("CLI の --line-numbers 指定は showLineNumbers に反映される")
    func lineNumbersOverrideIsAppliedToStore() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            showLineNumbersOverride: true
        )
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
    }

    @Test("CLI の --sort 指定はサイドバーの並び順(FileListModel.sortOrder)に反映される")
    func sortOrderOverrideIsAppliedToFileListModel() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        var receivedSortOrder: befold.SortOrder?

        let controller = ViewerWindowController(
            fileURL: file, defaults: defaults,
            perFileState: makePerFileState(defaults: defaults),
            initialSortOrder: .alphabetical,
            directoryLister: { directory, sortOrder, showHiddenFiles in
                receivedSortOrder = sortOrder
                return DirectoryLister.listEntries(
                    in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles
                )
            }
        )
        defer { controller.close() }

        #expect(receivedSortOrder == .alphabetical)
        #expect(controller.fileListModel.sortOrder == .alphabetical)
    }
}
