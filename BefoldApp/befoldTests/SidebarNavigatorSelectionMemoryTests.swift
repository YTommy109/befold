@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// フォルダーを離れる直前の選択を覚え、通常のクリック操作で再びそこへ入ったときに
/// 復元する挙動(TASK-309)を検証する。戻る/進む履歴は使わない経路であることが要点で、
/// 実ディレクトリ列挙は伴わず directoryLister をスタブに差し替える
/// (前例: SidebarNavigatorFolderNavigationTests)。
@Suite
@MainActor
struct SidebarNavigatorSelectionMemoryTests {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    @Test("再びそのフォルダーへ入ると、直前にそこで選択していた項目が復元される")
    func revisitingFolderRestoresPreviousSelection() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorSelectionMemoryTests-revisit")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let first = sub.appendingPathComponent("a.mmd")
        let second = sub.appendingPathComponent("b.mmd")
        let listings = [
            tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)],
            sub.normalizedPathKey: [
                FileListEntry(url: first, kind: .file),
                FileListEntry(url: second, kind: .file),
            ],
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: sub,
            selection: second,
            listings: { listings[$0.normalizedPathKey] ?? [] }
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(tmp)
        await navigator.awaitSettled()
        navigator.navigateToFolder(sub)
        await navigator.awaitSettled()

        // 先頭(a.mmd)ではなく、直前に選択していた b.mmd が戻る。
        #expect(navigator.fileListModel.selection?.lastPathComponent == "b.mmd")
        // 選択を書くだけではプレビューが追従しないので、切替まで行われていること(TASK-310)。
        #expect(host.currentFileURL == second)
    }

    @Test("記憶していた項目が消えていたら先頭行の選択へフォールバックする")
    func revisitingFolderFallsBackWhenRememberedEntryIsGone() async {
        let tmp = Self.home.appendingPathComponent("SidebarNavigatorSelectionMemoryTests-gone")
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        let first = sub.appendingPathComponent("a.mmd")
        let second = sub.appendingPathComponent("b.mmd")
        var listings = [
            tmp.normalizedPathKey: [FileListEntry(url: sub, kind: .folder)],
            sub.normalizedPathKey: [
                FileListEntry(url: first, kind: .file),
                FileListEntry(url: second, kind: .file),
            ],
        ]
        let (navigator, host) = makeNavigator(
            currentDirectory: sub,
            selection: second,
            listings: { listings[$0.normalizedPathKey] ?? [] }
        )
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(tmp)
        await navigator.awaitSettled()
        // 離れている間に b.mmd が削除された。
        listings[sub.normalizedPathKey] = [FileListEntry(url: first, kind: .file)]
        navigator.navigateToFolder(sub)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.selection?.lastPathComponent == "a.mmd")
    }

    /// directoryLister を差し替えたナビゲーターを作る。列挙結果はクロージャで供給し、
    /// テストの途中でディレクトリの中身が変わる状況も表せるようにする(実 FS には触れない)。
    private func makeNavigator(
        currentDirectory: URL,
        selection: URL?,
        listings: @escaping (URL) -> [FileListEntry]
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: listings(currentDirectory),
            selection: selection,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorSelectionMemoryTests")
            ),
            directoryLister: { url, _, _ in DirectoryListing(rootChildren: listings(url)) },
            git: SidebarGitReadingStub(repositoryRoot: { _ in nil })
        )
        let host = SidebarNavigatorStubHost(currentFileURL: selection ?? currentDirectory)
        navigator.attach(to: host)
        return (navigator, host)
    }
}
