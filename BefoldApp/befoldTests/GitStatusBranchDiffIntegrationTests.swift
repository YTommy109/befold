@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ブランチ差分(base ブランチからのコミット済み変更 = `branchChange`)の Integration テスト。
///
/// `GitStatusReaderIntegrationTests` から分けてあるのは file_length / type_body_length を
/// 超えたため(規約どおり閾値を緩めずに分割する)。境界は「比較起点を要するか」で切っており、
/// こちらは `GitComparisonBaseResolving` が解決した起点との差分だけを扱う。
struct GitStatusBranchDiffIntegrationTests {
    private func makeReader() -> GitStatusReader {
        GitStatusReader()
    }

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
        #expect(status("changed.md")?.branchChange == .modified)
        #expect(status("base.md") == nil)
    }

    /// ブランチで**追加**したファイルは A であって M ではない。以前は真偽値 1 個しか
    /// 持ち帰っておらず、追加も変更も一律 M で表示されていた(TASK-344)。
    @Test("ブランチで新規追加したコミット済みファイルは added になる")
    func marksFilesAddedInCurrentBranch() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "base.md", contents: "base", in: temp.url)
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        try GitTestRepo.commitFile(named: "added.md", contents: "new", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url))
        let key = temp.url.appendingPathComponent("added.md").normalizedPathKey

        #expect(snapshot.statuses[key]?.branchChange == .added)
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

        #expect(status?.branchChange == .modified)
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
        #expect(status?.branchChange == nil)
    }
}
