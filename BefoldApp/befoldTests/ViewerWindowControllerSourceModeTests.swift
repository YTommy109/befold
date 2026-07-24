import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ソース表示モードの復元・保持(SourceModeStore 連携)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入し、directoryLister も差し替える。
/// switchFile の存在ガードが store.fileReader 経由になった(TASK-116.12)ため、
/// 切替経由の復元・保持も InMemoryFileReader でモック化して unit で検証する。
@Suite
@MainActor
struct ViewerWindowControllerSourceModeTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/note.md")
    private let file1 = URL(fileURLWithPath: "/mock/first.md")
    private let file2 = URL(fileURLWithPath: "/mock/second.md")

    /// サイドバー初期一覧の取得を実 FS に触れさせないための空リスター。
    private let noEntries: (URL, befold.SortOrder, Bool) -> [FileListEntry] = { _, _, _ in [] }

    private func makeController(
        file: URL,
        extraFiles: [URL] = [],
        sourceModeStore: SourceModeStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
    ) -> ViewerWindowController {
        var files = [file.path: "# hi"]
        for extra in extraFiles {
            files[extra.path] = "# hi"
        }
        return ViewerWindowController(
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
                fileReader: InMemoryFileReader(files: files),
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

        let controller = makeController(file: file, sourceModeStore: sourceModeStore, defaults: defaults)
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }

    @Test("switchFile は切替先ファイルの保存済みソース表示モードを復元する")
    func switchFileRestoresSavedSourceModeForTargetFile() {
        let controller = makeController(file: file1, extraFiles: [file2])
        defer { controller.close() }

        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)

        controller.switchFile(to: file2)
        // file2 は初めて開くファイルなのでレンダリング表示から始まる。
        #expect(!controller.isSourceMode)

        controller.switchFile(to: file1)
        // file1 に戻ると、以前トグルしたソース表示モードが復元される。
        #expect(controller.isSourceMode)
    }

    @Test("switchFile は旧・新ファイルの保存済みソース表示モードを破壊しない")
    func switchFilePreservesSavedSourceModeForBothFiles() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file1)
        sourceModeStore.setSourceMode(false, for: file2)
        let controller = makeController(
            file: file1, extraFiles: [file2], sourceModeStore: sourceModeStore, defaults: defaults
        )
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存済みモードが独立して保たれる。
        #expect(sourceModeStore.isSourceMode(for: file1))
        #expect(!sourceModeStore.isSourceMode(for: file2))
    }
}
