@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 実 git を spawn する Integration テスト。porcelain の書式網羅は
/// `GitStatusReaderTests`(フィクスチャ)に任せ、ここでは「実 git の出力を実際に
/// 解釈でき、絶対パスのキーで引ける」ことのスモークに絞る(実 git を起動するテストは
/// `GitCommandRunnerResourceLeakTests` の基準線にノイズを乗せるため本数を絞る規約)。
struct GitStatusReaderIntegrationTests {
    /// git 1 回あたりの予算は他のポーリング待機と同じ単一情報源から採る
    /// (少コアの CI では git の起動自体が遅れうるため、本番既定の 10 秒に縛らない)。
    private func makeReader() -> GitStatusReader {
        let runner = GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10))
        return GitStatusReader(runner: runner, repository: GitRepository(runner: runner))
    }

    @Test("staged / unstaged / untracked を実 git の出力から判別する")
    func classifiesRealRepositoryStatuses() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "staged.swift", in: temp.url)
        try GitTestRepo.commitFile(named: "unstaged.swift", in: temp.url)
        try GitTestRepo.stageChange(to: "staged.swift", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("unstaged.swift", in: temp.url)
        try GitTestRepo.addUntrackedFile(named: "new.swift", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        func status(_ name: String) -> GitFileStatus? {
            snapshot.statuses[temp.url.appendingPathComponent(name).normalizedPathKey]
        }
        #expect(status("staged.swift") == GitFileStatus(indexChange: .modified, worktreeChange: nil))
        #expect(status("unstaged.swift") == GitFileStatus(indexChange: nil, worktreeChange: .modified))
        #expect(status("new.swift")?.isUntracked == true)
        // `.git/index` の fingerprint を同梱して返す(Phase 2 のキャッシュ無効化で使う)。
        #expect(snapshot.indexFingerprint != nil)
    }

    /// Reader / Store / SidebarNavigator を本番と同じ組み合わせで繋ぎ、実リポジトリの
    /// 変更がサイドバーのモデルまで届くことを確認する(描画そのものは手動チェック対象)。
    @MainActor
    @Test("実リポジトリの状態がサイドバーのモデルまで届く")
    func deliversRealStatusesToSidebarModel() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", in: temp.url)

        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: temp.url,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "GitStatusReaderIntegrationTests")
            ),
            directoryLister: { _, _, _ in [] },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        let key = temp.url.appendingPathComponent("a.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatuses[key]?.worktreeChange == .modified)
    }

    /// TASK-186.2 の中核。`.git/index` の監視から状態の取り直しまでを実物どうしで繋ぎ、
    /// 「git 操作のあと、明示 refresh なしにバッジが変わる」ことを確認する。
    @MainActor
    @Test("git add の後、明示 refresh なしでサイドバーの状態が更新される", .timeLimit(.minutes(1)))
    func updatesWithoutExplicitRefreshAfterStaging() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", in: temp.url)

        let gitFileIndex = GitCommandFileIndex()
        let store = GitStatusStore(
            reader: makeReader(),
            resolveRepositoryRoot: { gitFileIndex.repositoryRoot(forDirectoryAt: $0) }
        )
        let navigator = SidebarNavigator(
            currentDirectory: temp.url,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "GitStatusIndexWatch")
            ),
            directoryLister: { _, _, _ in [] },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }
        defer { navigator.cancelPendingListing() }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value
        let key = temp.url.appendingPathComponent("a.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatuses[key]?.worktreeChange == .modified)

        // ここから先は明示的な refresh を一切呼ばない。`.git/index` の監視だけが契機。
        GitTestRepo.run(["add", "a.md"], in: temp.url)

        await waitUntilOnMainActor { navigator.fileListModel.gitStatuses[key]?.indexChange == .modified }
        #expect(navigator.fileListModel.gitStatuses[key]?.worktreeChange == nil)
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

        #expect(navigator.fileListModel.gitStatuses.isEmpty)
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
            directoryLister: { _, _, _ in entries },
            loadGitStatuses: { directory, policy in
                await store.statuses(forDirectoryAt: directory, policy: policy)
            }
        )
        navigator.attach(to: host)
        return navigator
    }

    /// 自己励振の防止線。`git status` は既定で index を refresh して mtime を書き換えうるため、
    /// `--no-optional-locks` を外すと「status → index 変化 → 監視発火 → status」の輪ができる。
    @Test("status 実行は .git/index の fingerprint を変えない")
    func statusDoesNotDisturbIndexFingerprint() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", in: temp.url)
        let reader = makeReader()
        let before = reader.indexFingerprint(forRepositoryAt: temp.url)

        _ = reader.status(forRepositoryAt: temp.url)
        _ = reader.status(forRepositoryAt: temp.url)

        #expect(reader.indexFingerprint(forRepositoryAt: temp.url) == before)
    }

    // MARK: - Branch Diff (TASK-186.3)

    /// ブランチ内でコミット済み・作業ツリーはクリーンなファイルに branchModified が付く。
    @Test("base ブランチからのコミット済み変更に branchModified が付く")
    func marksFilesChangedInCurrentBranch() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "base.md", contents: "base", in: temp.url)
        try GitTestRepo.commitFile(named: "changed.md", contents: "before", in: temp.url)
        // 既定ブランチ名は git のバージョン/設定で master にも main にもなりうるため、
        // 検出は実装(origin/HEAD → main → master)に委ね、ここでは分岐だけ作る。
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        try GitTestRepo.commitChange(to: "changed.md", contents: "after", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        func status(_ name: String) -> GitFileStatus? {
            snapshot.statuses[temp.url.appendingPathComponent(name).normalizedPathKey]
        }
        #expect(status("changed.md")?.isBranchModified == true)
        #expect(status("base.md") == nil)
    }

    /// worktree の変更は branchModified と両立する。バッジは worktree 側が優先されるが
    /// (`GitStatusBadgeTests`)、状態としては両方立っていること自体を固定する。
    @Test("ブランチ内変更と worktree の変更は両立する")
    func combinesBranchModifiedWithWorktreeChange() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.md", contents: "base", in: temp.url)
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        try GitTestRepo.commitChange(to: "a.md", contents: "committed", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", contents: "dirty", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))
        let status = snapshot.statuses[temp.url.appendingPathComponent("a.md").normalizedPathKey]

        #expect(status?.isBranchModified == true)
        #expect(status?.worktreeChange == .modified)
    }

    /// デフォルトブランチを特定できない場合(origin が無く main/master も無い)は
    /// branchModified だけを諦め、他の状態は出し続ける。
    @Test("デフォルトブランチ検出不可なら branchModified のみ無効化する")
    func disablesOnlyBranchModifiedWhenDefaultBranchIsUnknown() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        // main / master のどちらでもないブランチだけを持たせ、origin も付けない。
        GitTestRepo.run(["checkout", "-b", "topic"], in: temp.url)
        try GitTestRepo.commitFile(named: "a.md", contents: "base", in: temp.url)
        try GitTestRepo.commitChange(to: "a.md", contents: "committed", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.md", contents: "dirty", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))
        let status = snapshot.statuses[temp.url.appendingPathComponent("a.md").normalizedPathKey]

        #expect(status?.worktreeChange == .modified)
        #expect(status?.isBranchModified == false)
    }

    @Test("変更が無いリポジトリでは空のスナップショットを返す")
    func returnsEmptySnapshotForCleanRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses.isEmpty)
    }

    /// 非リポジトリでは git が非 0 で終わる(`.rejected`)。答えとして確定しているので
    /// nil ではなく空のスナップショットに縮退し、呼び出し側がキャッシュしてよい形にする。
    @Test("非リポジトリでは空のスナップショットへ縮退する")
    func degradesToEmptySnapshotOutsideRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))

        #expect(snapshot.statuses.isEmpty)
    }
}
