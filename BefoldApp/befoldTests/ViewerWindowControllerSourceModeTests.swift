import AppKit
@testable import befold
import Foundation
import Testing

/// ファイル切替・直接オープン時のソース表示モード復元(SourceModeStore 連携)を検証する。
/// ViewerWindowControllerTests から分離: 型本体の行数制約(SwiftLint type_body_length)対応。
@Suite
@MainActor
struct ViewerWindowControllerSourceModeTests {
    private func makeController(
        file: URL,
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
            )
        )
    }

    @Test("switchFile は切替先ファイルの保存済みソース表示モードを復元する")
    func switchFileRestoresSavedSourceModeForTargetFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.md", contents: "# first")
        let file2 = try tmp.file(named: "second.md", contents: "# second")
        let controller = makeController(file: file1)
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
    func switchFilePreservesSavedSourceModeForBothFiles() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.md", contents: "# first")
        let file2 = try tmp.file(named: "second.md", contents: "# second")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file1)
        sourceModeStore.setSourceMode(false, for: file2)
        let controller = makeController(file: file1, sourceModeStore: sourceModeStore, defaults: defaults)
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存済みモードが独立して保たれる。
        #expect(sourceModeStore.isSourceMode(for: file1))
        #expect(!sourceModeStore.isSourceMode(for: file2))
    }

    @Test("直接開いた場合も保存済みのソース表示モードが復元される")
    func openingFileDirectlyRestoresSavedSourceMode() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "note.md", contents: "# hi")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file)

        let controller = makeController(file: file, sourceModeStore: sourceModeStore, defaults: defaults)
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }
}
