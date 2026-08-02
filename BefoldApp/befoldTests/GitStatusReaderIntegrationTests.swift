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
            hiddenFilesPreference: HiddenFilesPreference(
                defaults: makeIsolatedDefaults(prefix: "GitStatusReaderIntegrationTests")
            ),
            directoryLister: { _, _, _ in [] },
            loadGitStatuses: { await store.statuses(forDirectoryAt: $0) }
        )
        let host = SidebarNavigatorStubHost(currentFileURL: temp.url.appendingPathComponent("a.md"))
        navigator.attach(to: host)
        defer { withExtendedLifetime(host) {} }

        navigator.refreshFileList()
        await navigator.pendingGitStatusTask?.value

        let key = temp.url.appendingPathComponent("a.md").normalizedPathKey
        #expect(navigator.fileListModel.gitStatuses[key]?.worktreeChange == .modified)
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
