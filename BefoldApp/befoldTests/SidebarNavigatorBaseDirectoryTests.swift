@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator が基準ディレクトリ(サイドバーヘッダーの表示元)を
/// 注入された解決器で更新するかを検証する。git の実行は伴わない。
@Suite
@MainActor
struct SidebarNavigatorBaseDirectoryTests {
    /// ファイル切替を行わないダミーの host。基準ディレクトリの更新だけを見る。
    private final class StubHost: SidebarNavigatorHost {
        let currentFileURL: URL

        init(currentFileURL: URL) {
            self.currentFileURL = currentFileURL
        }

        func performFileSwitch(to _: URL) -> FileSwitchOutcome {
            .switched
        }

        func historyStateDidChange() {}
    }

    private func makeNavigator(
        currentDirectory: URL,
        gitRoot: URL?
    ) -> (SidebarNavigator, StubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            hiddenFilesPreference: HiddenFilesPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorBaseDirectoryTests")
            ),
            directoryLister: { _, _, _ in [] },
            resolveGitRoot: { _ in gitRoot }
        )
        let host = StubHost(currentFileURL: currentDirectory.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        return (navigator, host)
    }

    @Test("git 管理下では基準ディレクトリが git ルートになる")
    func usesGitRootWhenTracked() async {
        let gitRoot = URL(fileURLWithPath: "/Users/me/repo")
        let (navigator, host) = makeNavigator(
            currentDirectory: gitRoot.appendingPathComponent("docs"),
            gitRoot: gitRoot
        )
        defer { withExtendedLifetime(host) {} }

        await navigator.pendingBaseDirectoryTask?.value

        #expect(navigator.fileListModel.baseDirectory?.kind == .gitRoot)
        #expect(navigator.fileListModel.baseDirectory?.url == gitRoot)
    }

    @Test("git 管理外では基準ディレクトリが rootDirectory になる")
    func fallsBackToRootDirectory() async {
        let directory = URL(fileURLWithPath: "/Users/me/notes")
        let (navigator, host) = makeNavigator(currentDirectory: directory, gitRoot: nil)
        defer { withExtendedLifetime(host) {} }

        await navigator.pendingBaseDirectoryTask?.value

        #expect(navigator.fileListModel.baseDirectory?.kind == .plainFolder)
        #expect(navigator.fileListModel.baseDirectory?.url == directory)
    }

    @Test("一覧の再取得でも基準ディレクトリが取り直される")
    func refreshFileListUpdatesBaseDirectory() async {
        let gitRoot = URL(fileURLWithPath: "/Users/me/repo")
        let (navigator, host) = makeNavigator(
            currentDirectory: gitRoot.appendingPathComponent("docs"),
            gitRoot: gitRoot
        )
        defer { withExtendedLifetime(host) {} }
        await navigator.pendingBaseDirectoryTask?.value
        navigator.fileListModel.baseDirectory = nil

        navigator.refreshFileList()
        await navigator.pendingBaseDirectoryTask?.value

        #expect(navigator.fileListModel.baseDirectory?.url == gitRoot)
    }
}
