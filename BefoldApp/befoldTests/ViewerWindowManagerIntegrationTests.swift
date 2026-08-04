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
            sidebarDisplayPreference: SidebarDisplayPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            makeContentView: placeholderViewerContent
        )
    }

    /// 隠しファイル表示のトリガー経路。全経路が「開いている全ウィンドウのサイドバーへ
    /// 同時に反映される」という同じ結果に至ることを、複数ウィンドウのセットアップに
    /// 統一して検証する(単一ウィンドウでの反映は複数ウィンドウの結果に包含される)。
    private struct HiddenFilesTrigger: Sendable, CustomTestStringConvertible {
        let name: String
        let trigger: @MainActor @Sendable (ViewerWindowManager, ViewerWindowController) -> Void
        var testDescription: String {
            name
        }
    }

    private nonisolated static let hiddenFilesTriggers: [HiddenFilesTrigger] = [
        HiddenFilesTrigger(name: "toggleHiddenFiles", trigger: { manager, _ in manager.toggleHiddenFiles() }),
        HiddenFilesTrigger(
            name: "onToggleHiddenFiles コールバック(アイコンボタン操作)",
            trigger: { manager, first in manager.viewerWindowDidToggleHiddenFiles(first) }
        ),
        HiddenFilesTrigger(
            name: "setHiddenFiles(true)(--hidden-files)",
            trigger: { manager, _ in manager.setHiddenFiles(true) }
        ),
    ]

    @Test("隠しファイル表示のトリガー経路によらず、開いている全ウィンドウへ同時に反映される", arguments: hiddenFilesTriggers)
    private func hiddenFilesTriggerRefreshesAllOpenWindows(_ testCase: HiddenFilesTrigger) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey]?.first)
        for controller in manager.allControllers {
            #expect(!controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }

        testCase.trigger(manager, first)
        for controller in manager.allControllers {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.allControllers {
            #expect(controller.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd"))
        }
        manager.allControllers.forEach { $0.close() }
    }

    /// git 変更のみ表示のトリガー経路。メニュー(⌘⌃G)とサイドバーのアイコンボタンの
    /// どちらからでも、開いている全ウィンドウへ同じ結果が届くことを検証する。
    private struct ChangedFilesOnlyTrigger: Sendable, CustomTestStringConvertible {
        let name: String
        let trigger: @MainActor @Sendable (ViewerWindowManager, ViewerWindowController) -> Void
        var testDescription: String {
            name
        }
    }

    private nonisolated static let changedFilesOnlyTriggers: [ChangedFilesOnlyTrigger] = [
        ChangedFilesOnlyTrigger(
            name: "toggleChangedFilesOnly(メニュー ⌘⌃G)",
            trigger: { manager, _ in manager.toggleChangedFilesOnly() }
        ),
        ChangedFilesOnlyTrigger(
            name: "onToggleChangedFilesOnly コールバック(アイコンボタン操作)",
            trigger: { manager, first in manager.viewerWindowDidToggleChangedFilesOnly(first) }
        ),
    ]

    @Test(
        "git 変更のみ表示は経路によらず、開いている全ウィンドウのサイドバーへ反映される",
        arguments: changedFilesOnlyTriggers
    )
    private func changedFilesOnlyToggleReachesAllOpenWindows(
        _ testCase: ChangedFilesOnlyTrigger
    ) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey]?.first)
        for controller in manager.allControllers {
            #expect(!controller.fileListModel.showChangedFilesOnly)
        }

        testCase.trigger(manager, first)
        for controller in manager.allControllers {
            await controller.sidebar.pendingListingTask?.value
        }

        for controller in manager.allControllers {
            #expect(controller.fileListModel.showChangedFilesOnly)
        }
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
