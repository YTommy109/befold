import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 直接オープン時のソース表示モード復元(SourceModeStore 連携)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替える。
/// switchFile 経由の復元・保持は実 store の切替を踏むため Integration へ移した。
@Suite
@MainActor
struct ViewerWindowControllerSourceModeTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/note.md")

    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    private func makeController(
        sourceModeStore: SourceModeStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
    ) -> ViewerWindowController {
        ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            perFileState: PerFileStateStore(
                zoom: ZoomStore(defaults: defaults),
                sourceMode: sourceModeStore ?? SourceModeStore(defaults: defaults),
                scrollPosition: ScrollPositionStore(defaults: defaults),
                sidebar: SidebarStateStore(defaults: defaults),
                windowFrame: WindowFrameStore(defaults: defaults)
            ),
            store: ViewerStore(
                watcherFactory: { _, _, _ in MockFileWatcher() },
                fileReader: InMemoryFileReader(files: [file.path: "# hi"]),
                defaults: defaults
            ),
            directoryLister: noEntries
        )
    }

    @Test("直接開いた場合も保存済みのソース表示モードが復元される")
    func openingFileDirectlyRestoresSavedSourceMode() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file)

        let controller = makeController(sourceModeStore: sourceModeStore, defaults: defaults)
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }
}
