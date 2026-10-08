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
        try await GitTestRepo.offMainActor {
            GitTestRepo.initRepository(at: temp.url)
            for path in ["changed.md", "clean.md", "nested/inner.md", "quiet/inner.md"] {
                _ = try temp.file(atPath: path, contents: "print(1)")
            }
            GitTestRepo.commitAll(in: temp.url)
            try GitTestRepo.modifyWithoutStaging("changed.md", in: temp.url)
            try GitTestRepo.modifyWithoutStaging("nested/inner.md", in: temp.url)
        }
        let entries = [
            FileListEntry(url: temp.url.appendingPathComponent("changed.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("clean.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("nested"), kind: .folder),
            FileListEntry(url: temp.url.appendingPathComponent("quiet"), kind: .folder),
        ]
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "GitStatusChangedFilesOnly")
        )
        preference.record { $0.showChangedFilesOnly = true }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

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
        let newDirectory = temp.url.appendingPathComponent("newdir")
        try await GitTestRepo.offMainActor {
            GitTestRepo.initRepository(at: temp.url)
            try GitTestRepo.commitFile(named: "root.md", in: temp.url)
            _ = try temp.file(atPath: "newdir/b.md", contents: "untracked")
            _ = try temp.file(atPath: "newdir/c.md", contents: "untracked")
        }
        // 前提の確認: 実 git が畳んでいる(配下のファイル個別のレコードは出ない)。
        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url, target: .defaultBranch))
        #expect(snapshot.statuses[newDirectory.appendingPathComponent("b.md").normalizedPathKey] == nil)
        let entries = [
            FileListEntry(url: newDirectory.appendingPathComponent("b.md"), kind: .file),
            FileListEntry(url: newDirectory.appendingPathComponent("c.md"), kind: .file),
        ]
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "GitStatusFoldedUntracked")
        )
        preference.record { $0.showChangedFilesOnly = true }
        let host = SidebarNavigatorStubHost(currentFileURL: newDirectory)
        let navigator = makeNavigator(
            directory: newDirectory, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

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
        try await GitTestRepo.offMainActor {
            GitTestRepo.initRepository(at: temp.url)
            _ = try temp.file(named: "a.md", contents: "print(1)")
            _ = try temp.file(named: "b.md", contents: "print(1)")
            GitTestRepo.commitAll(in: temp.url)
        }
        let entries = [
            FileListEntry(url: temp.url.appendingPathComponent("a.md"), kind: .file),
            FileListEntry(url: temp.url.appendingPathComponent("b.md"), kind: .file),
        ]
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "GitStatusCleanRepository")
        )
        preference.record { $0.showChangedFilesOnly = true }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

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
        let preference = SidebarDisplayDefaults(
            defaults: makeIsolatedDefaults(prefix: "GitStatusChangedFilesOnlyDegrade")
        )
        preference.record { $0.showChangedFilesOnly = true }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        let navigator = makeNavigator(
            directory: temp.url, entries: entries, preference: preference, host: host
        )
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

        // 非 git なので状態は未解決のまま。空の状態(= 変更ゼロのリポジトリ)とは区別する。
        #expect(navigator.fileListModel.gitStatus == nil)
        #expect(navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["a.md"])
    }

    /// ブランチ内でコミット済みの `changed.md` だけが base..HEAD に載り、作業ツリーはクリーンな
    /// リポジトリ(TASK-353.3)。`.head` ならバッジも絞り込み対象も空になる。
    private func makeBranchChangedRepository() async throws -> (TempDir, [FileListEntry]) {
        let temp = try TempDir()
        try await GitTestRepo.offMainActor {
            GitTestRepo.initRepository(at: temp.url)
            for name in ["changed.md", "clean.md"] {
                _ = try temp.file(named: name, contents: "base")
            }
            GitTestRepo.commitAll(in: temp.url)
            GitTestRepo.createBranch(named: "feature", in: temp.url)
            _ = try temp.file(named: "changed.md", contents: "after")
            GitTestRepo.commitAll(message: "change", in: temp.url)
        }
        let entries = ["changed.md", "clean.md"].map {
            FileListEntry(url: temp.url.appendingPathComponent($0), kind: .file)
        }
        return (temp, entries)
    }

    @MainActor
    @Test("変更のみ表示は窓の比較基準に従い、デフォルトブランチ基準ならコミット済みの変更が残る")
    func filterFollowsDefaultBranchTarget() async throws {
        let (temp, entries) = try await makeBranchChangedRepository()
        defer { withExtendedLifetime(temp) {} }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        host.comparisonTarget = .defaultBranch
        let navigator = makeNavigator(directory: temp.url, entries: entries, host: host)
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

        let key = temp.url.appendingPathComponent("changed.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatus?.fileStatus(at: key)?.branchChange == .modified)
        #expect(navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])
    }

    /// 「作業中の変更」(.head)は base = HEAD で、ブランチ内のコミット済み変更にバッジを出さない。
    /// 実装側に `.head` の特別扱いは無く、base..HEAD が空になることの帰結。
    @MainActor
    @Test("作業中の変更基準では、コミット済みの変更にバッジも絞り込みの残りも出ない")
    func headTargetShowsNoBranchChanges() async throws {
        let (temp, entries) = try await makeBranchChangedRepository()
        defer { withExtendedLifetime(temp) {} }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        host.comparisonTarget = .head
        let navigator = makeNavigator(directory: temp.url, entries: entries, host: host)
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.gitStatus != nil)
        #expect(navigator.fileListModel.visibleEntries.isEmpty)
    }

    /// 基準を切り替えると、`.git/index` が動いていなくてもバッジが取り直される。
    /// `GitStatusStore` のキャッシュが target 違いで再利用されると、旧基準のバッジが残る。
    @MainActor
    @Test("基準を切り替えて取り直すと、バッジと絞り込みが新しい基準に追従する")
    func switchingTargetRecomputesBadges() async throws {
        let (temp, entries) = try await makeBranchChangedRepository()
        defer { withExtendedLifetime(temp) {} }
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url)
        host.comparisonTarget = .defaultBranch
        let navigator = makeNavigator(directory: temp.url, entries: entries, host: host)
        defer { navigator.cancelPendingListing() }
        navigator.refreshFileList()
        await navigator.awaitSettled()
        #expect(navigator.fileListModel.visibleEntries.map(\.url.lastPathComponent) == ["changed.md"])

        host.comparisonTarget = .head
        navigator.refreshGitStatuses(policy: .always)
        await navigator.awaitSettled()

        #expect(navigator.fileListModel.visibleEntries.isEmpty)
    }

    /// 実 Reader / Store を本番と同じ組み合わせで繋いだ SidebarNavigator を作る。
    @MainActor
    private func makeNavigator(
        directory: URL, entries: [FileListEntry], preference: SidebarDisplayDefaults? = nil,
        host: SidebarNavigatorStubHost
    ) -> SidebarNavigator {
        let preference = preference ?? {
            let preference = SidebarDisplayDefaults(defaults: makeIsolatedDefaults(prefix: "GitStatusTarget"))
            preference.record { $0.showChangedFilesOnly = true }
            return preference
        }()
        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: directory,
            entries: entries,
            selection: nil,
            displayDefaults: preference,
            directoryLister: { _, _, _ in DirectoryListing(rootChildren: entries) },
            git: SidebarGitReader(fileIndex: gitFileIndex, statusStore: store)
        )
        navigator.attach(to: host)
        return navigator
    }
}
