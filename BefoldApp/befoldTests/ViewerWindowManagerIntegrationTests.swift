import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// サイドバーの実ディレクトリ列挙(隠しファイルの出現/消滅)と DirectoryLister の実 FS 解決が
/// 検証対象そのものであるため Integration に残す。
/// 辞書管理・セッション記録・サイドバー開閉/フレームの初期状態解決など、実列挙に依存しない
/// 検証は TASK-116.13 で ViewerWindowManagerTests(unit)へ移設済み。
@Suite
@MainActor
struct ViewerWindowManagerIntegrationTests {
    private func makeManager(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowManagerTests")
    ) -> ViewerWindowManager {
        ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            hiddenFilesPreference: HiddenFilesPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            makeContentView: placeholderViewerContent
        )
    }

    @Test("toggleHiddenFiles は状態を反転し開いているサイドバーへ反映する")
    func toggleHiddenFilesRefreshesOpenSidebar() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let manager = makeManager()

        manager.openViewer(for: visible)
        let controller = try #require(manager.controllers[visible.normalizedPathKey]?.first)
        #expect(!controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))

        manager.toggleHiddenFiles()
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        manager.allControllers.forEach { $0.close() }
    }

    @Test("toggleHiddenFiles は複数の開いているウィンドウすべてへ同時に反映する")
    func toggleHiddenFilesAffectsAllOpenWindows() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)

        manager.toggleHiddenFiles()
        for controller in manager.allControllers {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.allControllers {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.allControllers.forEach { $0.close() }
    }

    @Test("ウィンドウのアイコンボタン操作(onToggleHiddenFiles)でも全ウィンドウが同期する")
    func onToggleHiddenFilesCallbackTogglesAllWindows() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey]?.first)

        manager.viewerWindowDidToggleHiddenFiles(first)
        for controller in manager.allControllers {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.allControllers {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.allControllers.forEach { $0.close() }
    }

    @Test("setHiddenFiles は指定値を反映し開いているサイドバーへ即座に反映する(--hidden-files)")
    func setHiddenFilesAppliesGivenValueAndRefreshesOpenSidebar() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: visible)
        let controller = try #require(manager.controllers[visible.normalizedPathKey]?.first)

        manager.setHiddenFiles(true)
        await controller.sidebar.pendingListingTask?.value

        #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        manager.allControllers.forEach { $0.close() }
    }

    @Test("CLI から複数ファイル/フォルダーを指定した起動を模すと、それぞれ別ウィンドウで開く")
    func multipleCLITargetsEachOpenSeparateWindow() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let folderFile = try tmp.file(atPath: "folderB/note.md", contents: "# note")
        let folderURL = folderFile.deletingLastPathComponent()
        let manager = makeManager()

        // AppDelegate.openViewer(for:) と同様、フォルダーは事前に resolveFileToOpen で解決してから渡す。
        let targets = [file1, folderURL].map { url -> URL in
            DirectoryLister.isDirectory(url) ? (DirectoryLister.resolveFileToOpen(at: url) ?? url) : url
        }
        for target in targets {
            manager.openViewer(for: target)
        }

        #expect(manager.controllers.count == 2)
        #expect(manager.controllers[file1.normalizedPathKey] != nil)
        #expect(manager.controllers[folderFile.normalizedPathKey] != nil)
        manager.allControllers.forEach { $0.close() }
    }
}
