import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 並び順オーバーライドがサイドバーの entries 表示へ反映されることを、実ディレクトリ列挙の
/// 結果で検証するため Integration に残す。
/// オーバーライドの適用そのもの(行番号・ソース表示・サイドバー開閉)は TASK-116.13 で
/// ViewerWindowManagerDisplayOverridesTests(unit)へ移設済み。
@Suite
@MainActor
struct ViewerWindowManagerDisplayOverridesIntegrationTests {
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

        manager.applyDisplayOverrides(
            showLineNumbers: nil, sourceMode: nil, sortOrder: .alphabetical, showSidebar: nil
        )
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.sortOrder == .alphabetical)
        #expect(controller.fileListModel.entries.map(\.kind) == [.file, .folder])
        manager.controllers.values.forEach { $0.close() }
    }
}
