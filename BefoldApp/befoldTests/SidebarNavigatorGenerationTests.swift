@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator.navigateToFolder が発行する一覧取得タスクの世代ガード、および
/// フォルダー移動をまたいだファイル名フィルターの持続を、実ディレクトリ列挙もフルウィンドウ
/// 生成も伴わずに検証する。世代ガードの競合は固定 sleep ではなく AsyncGate で
/// 1 回目の directoryLister 呼び出しを明示的に足止めしてから 2 回目を発行することで、
/// タイミング依存なく決定的に再現する。移設元: SidebarNavigatorIntegrationTests.swift
/// (rapidNavigateToFolderDiscardsStaleResult / filterTextPersistsAcrossFolderNavigation、旧 116-165 行)。
@Suite
@MainActor
struct SidebarNavigatorGenerationTests {
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

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private func makeNavigator(
        currentDirectory: URL,
        directoryLister: @escaping @Sendable (URL, befold.SortOrder, Bool) async -> [FileListEntry]
    ) -> (SidebarNavigator, StubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: currentDirectory,
            entries: [],
            selection: nil,
            hiddenFilesPreference: HiddenFilesPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorGenerationTests")
            ),
            directoryLister: directoryLister,
            resolveGitRoot: { _ in nil }
        )
        let host = StubHost(currentFileURL: currentDirectory.appendingPathComponent("fileA.mmd"))
        navigator.attach(to: host)
        return (navigator, host)
    }

    @Test("連続する navigateToFolder では古い列挙結果が新しい結果を上書きしない")
    func rapidNavigateToFolderDiscardsStaleResult() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGenerationTests-rapid")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let fileB = FileListEntry(url: dirB.appendingPathComponent("fileB.mmd"), kind: .file)

        // 1 回目(base への navigateToFolder)の directoryLister 呼び出しをここで足止めし、
        // 2 回目(dirB への navigateToFolder)を発行してから開放することで、
        // 「先に発行したタスクの結果が後から返る」競合を決定的に再現する。
        let staleGate = AsyncGate()
        let (navigator, host) = makeNavigator(currentDirectory: base) { url, _, _ in
            if url.normalizedPathKey == base.normalizedPathKey {
                await staleGate.wait()
                return [FileListEntry(url: base.appendingPathComponent("fileA.mmd"), kind: .file)]
            }
            return [fileB]
        }
        defer { withExtendedLifetime(host) {} }

        navigator.navigateToFolder(base)
        navigator.navigateToFolder(dirB)
        staleGate.open()
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.currentDirectory.standardizedFileURL == dirB.standardizedFileURL)
        let names = navigator.fileListModel.entries
            .filter { $0.kind != .parentNavigation }
            .map(\.url.lastPathComponent)
        #expect(names == ["fileB.mmd"])
    }

    @Test("フォルダー移動後もファイル名フィルターの文字列が保持される(task-185)")
    func filterTextPersistsAcrossFolderNavigation() async {
        let base = Self.home.appendingPathComponent("SidebarNavigatorGenerationTests-filter")
        let dirB = base.appendingPathComponent("dirB", isDirectory: true)
        let (navigator, host) = makeNavigator(currentDirectory: base) { _, _, _ in [] }
        defer { withExtendedLifetime(host) {} }

        navigator.fileListModel.filterText = "fileA"
        navigator.navigateToFolder(dirB)
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.currentDirectory.standardizedFileURL == dirB.standardizedFileURL)
        #expect(navigator.fileListModel.filterText == "fileA")
    }
}
