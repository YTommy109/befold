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
            displayDefaults: SidebarDisplayDefaults(defaults: defaults),
            diffDisplayPreference: DiffDisplayPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            makeContentView: placeholderViewerContent
        )
    }

    /// サイドバー表示 4 値の反映範囲。TASK-480 で「アプリ全体で 1 つ」から
    /// **窓ごとのライブ値**(ADR 0002「窓の状態」)へ移したため、ここが固定するのは
    /// 「操作した窓だけが変わる」こと。全窓へ配る形へ戻すと落ちる。
    ///
    /// メニュー(⌃⌘H / ⌘⌃G / ⌃⌘T)もサイドバーヘッダーのアイコンボタンも、
    /// 同じ `SidebarNavigator.applyDisplayChange(_:)` を通る 1 本の経路になったため、
    /// 入口ごとの分岐は持たない(TASK-480.3 で delegate 経由の往復を撤去した)。
    private struct DisplayChangeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let change: SidebarDisplayChange
        /// 変更が届いた窓で true になる読み出し。
        let applied: @MainActor @Sendable (ViewerWindowController) -> Bool
        var testDescription: String {
            name
        }
    }

    private nonisolated static let displayChanges: [DisplayChangeCase] = [
        DisplayChangeCase(
            name: "不可視ファイル表示(⌃⌘H)", change: .toggleHiddenFiles,
            applied: { $0.fileListModel.entries.map(\.url.lastPathComponent).contains(".hidden.mmd") }
        ),
        DisplayChangeCase(
            name: "変更ファイルのみ表示(⌘⌃G)", change: .toggleChangedFilesOnly,
            applied: { $0.fileListModel.showChangedFilesOnly }
        ),
        DisplayChangeCase(
            name: "表示形式(⌃⌘T)", change: .toggleLayoutMode,
            applied: { $0.fileListModel.layoutMode == .tree }
        ),
        DisplayChangeCase(
            name: "並び順", change: .setSortOrder(.alphabetical),
            applied: { $0.fileListModel.sortOrder == .alphabetical }
        ),
    ]

    @Test("サイドバー表示の変更は、操作したウィンドウだけに反映される", arguments: displayChanges)
    private func displayChangeStaysInTheOperatedWindow(_ testCase: DisplayChangeCase) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let file1 = try tmp.file(named: "first.mmd", contents: "graph TD;")
        let file2 = try tmp.file(named: "second.mmd", contents: "graph TD;")
        let manager = makeManager()
        manager.openViewer(for: file1)
        manager.openViewer(for: file2)
        let first = try #require(manager.controllers[file1.normalizedPathKey]?.first)
        let second = try #require(manager.controllers[file2.normalizedPathKey]?.first)
        for controller in manager.allControllers {
            await controller.sidebar.awaitSettled()
            #expect(!testCase.applied(controller))
        }

        first.sidebar.applyDisplayChange(testCase.change)
        // もう一方の窓も取り直してから見る。取り直しの契機で保存値を読み直す形へ戻すと、
        // ここで初めて他窓の操作が届く(読むだけでは素通しする)。
        second.sidebar.refreshFileList()
        for controller in manager.allControllers {
            await controller.sidebar.awaitSettled()
        }

        #expect(testCase.applied(first))
        #expect(!testCase.applied(second))
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
