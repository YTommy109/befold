import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// task-82: パス無し CLI 転送(`befold --line-numbers` 等)で開いている既存ウィンドウへ
/// 行番号/ソース表示/並び順のオーバーライドが反映されることを検証する。
@Suite
@MainActor
struct ViewerWindowManagerDisplayOverridesTests {
    private func makeManager(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerDisplayOverridesTests")
    ) -> ViewerWindowManager {
        ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            hiddenFilesPreference: HiddenFilesPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults)
        )
    }

    @Test("開いている全ウィンドウへ行番号/ソース/並び順を反映する")
    func applyDisplayOverridesAffectsAllOpenWindows() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.md", contents: "# hello")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)

        manager.applyDisplayOverrides(showLineNumbers: true, sourceMode: true, sortOrder: .alphabetical)

        for controller in manager.controllers.values {
            #expect(controller.store.showLineNumbers)
            #expect(controller.isSourceMode)
            #expect(controller.fileListModel.sortOrder == .alphabetical)
        }
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("既存ウィンドウへの並び順オーバーライドはサイドバーのentries表示にも反映される")
    func applyDisplayOverridesRefreshesSidebarEntries() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        // フォルダ名を "zzz-" にすることで、foldersFirst と alphabetical の並び順が確実に異なるようにする。
        _ = try tmp.file(atPath: "zzz-folder/inner.md", contents: "# inner")
        let file = try tmp.file(named: "aaa-file.md", contents: "# hello")
        let manager = makeManager()
        manager.openViewer(for: file, forceSidebarVisible: true)
        let controller = try #require(manager.controllers[file.normalizedPathKey])
        await controller.sidebar.pendingListingTask?.value
        #expect(controller.fileListModel.entries.map(\.kind) == [.folder, .file])

        manager.applyDisplayOverrides(showLineNumbers: nil, sourceMode: nil, sortOrder: .alphabetical)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.sortOrder == .alphabetical)
        #expect(controller.fileListModel.entries.map(\.kind) == [.file, .folder])
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("nil を渡したオーバーライドは既存ウィンドウの状態を変更しない")
    func applyDisplayOverridesLeavesUnspecifiedOptionsUntouched() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file)
        let controller = try #require(manager.controllers[file.normalizedPathKey])
        let originalSortOrder = controller.fileListModel.sortOrder
        let originalSourceMode = controller.isSourceMode

        manager.applyDisplayOverrides(showLineNumbers: true, sourceMode: nil, sortOrder: nil)

        #expect(controller.store.showLineNumbers)
        #expect(controller.isSourceMode == originalSourceMode)
        #expect(controller.fileListModel.sortOrder == originalSortOrder)
        manager.controllers.values.forEach { $0.close() }
    }
}
