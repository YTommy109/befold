@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 「変更されたファイルのみ表示」(TASK-264 / TASK-285)を実 git リポジトリで通す Integration テスト。
/// 絞り込みの判定は porcelain の畳み込み・リポジトリ解決の有無・状態の到着順に依存するため、
/// フィクスチャではなく実 git の出力で確かめる。
struct SidebarChangedFilesOnlyIntegrationTests {
    private func makeReader() -> GitStatusReader {
        GitStatusReader()
    }

    /// TASK-264。実リポジトリの状態で「変更のあるファイルのみ表示」を通し、
    /// 変更ファイルと配下に変更を持つフォルダーだけが一覧に残ることを確認する。
    @MainActor
    @Test("変更のみ表示 ON で、実リポジトリの変更ファイルと変更を含むフォルダーだけが残る")
    func filtersSidebarToRealChangedEntries() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "changed.md", in: temp.url)
        try GitTestRepo.commitFile(named: "clean.md", in: temp.url)
        for folder in ["nested", "quiet"] {
            try FileManager.default.createDirectory(
                at: temp.url.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        try GitTestRepo.commitFile(named: "nested/inner.md", in: temp.url)
        try GitTestRepo.commitFile(named: "quiet/inner.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("changed.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("nested/inner.md", in: temp.url)
        let entries = [
            FileListEntry(url: temp.url.appendingPathComponent("changed.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("clean.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("nested"), kind: .folder),
            FileListEntry(url: temp.url.appendingPathComponent("quiet"), kind: .folder),
        ]
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "GitStatusChangedFilesOnly")
        )
        preference.showChangedFilesOnly = true
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        await navigator.pendingGitStatusTask?.value

        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent)
                == ["changed.md", "nested"]
        )
    }

    /// TASK-285。porcelain の既定は未追跡ディレクトリを 1 レコードへ畳むため、新規フォルダー
    /// 配下のファイルは状態マップにキーを持たない。それでも一覧から消えてはいけない。
    @MainActor
    @Test("未追跡フォルダーの中へ入っても、配下のファイルが絞り込みで消えない")
    func keepsFilesInsideFoldedUntrackedDirectory() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "root.md", in: temp.url)
        let newDirectory = temp.url.appendingPathComponent("newdir")
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        try GitTestRepo.addUntrackedFile(named: "newdir/b.md", in: temp.url)
        try GitTestRepo.addUntrackedFile(named: "newdir/c.md", in: temp.url)
        // 前提の確認: 実 git が畳んでいる(配下のファイル個別のレコードは出ない)。
        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))
        #expect(snapshot.statuses[newDirectory.appendingPathComponent("b.md").normalizedPathKey] == nil)
        let entries = [
            FileListEntry(url: newDirectory.appendingPathComponent("b.md"), kind: .file),
            FileListEntry(url: newDirectory.appendingPathComponent("c.md"), kind: .file),
        ]
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "GitStatusFoldedUntracked")
        )
        preference.showChangedFilesOnly = true
        let host = SidebarNavigatorStubHost(currentFileURL: newDirectory)
        let navigator = makeNavigator(
            directory: newDirectory, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        await navigator.pendingGitStatusTask?.value

        #expect(
            navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["b.md", "c.md"]
        )
    }

    /// TASK-285。変更ゼロのリポジトリは「空の状態」であって未解決ではない。
    /// ここを取り違えると、綺麗なリポジトリでトグルが黙って効かなくなる。
    @MainActor
    @Test("変更が無いリポジトリでは、絞り込み ON で一覧が変更ファイルだけ(= 空)になる")
    func filterAppliesInCleanRepository() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.commitFile(named: "b.md", in: temp.url)
        let entries = [
            FileListEntry(url: temp.url.appendingPathComponent("a.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("b.md"), kind: .file),
        ]
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "GitStatusCleanRepository")
        )
        preference.showChangedFilesOnly = true
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        await navigator.pendingGitStatusTask?.value

        // リポジトリは解決できている(未解決の nil ではない)。
        #expect(navigator.fileListModel.gitStatus != nil)
        #expect(navigator.fileListModel.visibleEntries.isEmpty)
    }

    /// TASK-264 の縮退。git 管理外のディレクトリではトグル ON でも一覧が空にならない。
    @MainActor
    @Test("非 git ディレクトリでは変更のみ表示 ON でも一覧が空にならない")
    func changedFilesOnlyDegradesOutsideRepository() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        _ = try temp.file(named: "a.md", contents: "graph TD;")
        let entries = [FileListEntry(url: temp.url.appendingPathComponent("a.md"), kind: .file)]
        let preference = SidebarDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "GitStatusChangedFilesOnlyDegrade")
        )
        preference.showChangedFilesOnly = true
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        await navigator.pendingGitStatusTask?.value

        // 非 git なので状態は未解決のまま。空の状態(= 変更ゼロのリポジトリ)とは区別する。
        #expect(navigator.fileListModel.gitStatus == nil)
        #expect(navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["a.md"])
    }

    /// 実 Reader / Store を本番と同じ組み合わせで繋いだ SidebarNavigator を作る。
    @MainActor
    private func makeNavigator(
        directory: URL, entries: [FileListEntry], preference: SidebarDisplayPreference,
        host: SidebarNavigatorStubHost
    ) -> SidebarNavigator {
        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: directory,
            entries: entries,
            selection: nil,
            sidebarDisplayPreference: preference,
            directoryLister: { _, _, _ in DirectoryListing(parentEntry: nil, rootChildren: entries) },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        navigator.attach(to: host)
        return navigator
    }
}
