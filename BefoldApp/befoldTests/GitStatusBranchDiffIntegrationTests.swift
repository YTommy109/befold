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

    /// 同じ base からの分岐で見分けるべき 3 つの状態を 1 つのリポジトリに同居させる
    /// (TASK-662.6。以前は状態ごとに init・commit していた)。
    ///
    /// - `changed.md`: ブランチ内でコミット済み・作業ツリーはクリーン → branchModified
    /// - `added.md`: ブランチで**追加**したファイルは A であって M ではない。以前は真偽値 1 個しか
    ///   持ち帰っておらず、追加も変更も一律 M で表示されていた(TASK-344)
    /// - `dirty.md`: worktree の変更は branchModified と両立する。バッジは worktree 側が優先されるが
    ///   (`GitStatusBadgeTests`)、状態としては両方立っていること自体を固定する
    /// - `base.md`: base から触っていないファイルには何も付かない
    @Test("base ブランチからのコミット済み変更・追加・worktree 変更との両立を見分ける")
    func classifiesChangesAgainstBaseBranch() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        for name in ["base.md", "changed.md", "dirty.md"] {
            _ = try temp.file(named: name, contents: "base")
        }
        GitTestRepo.commitAll(in: temp.url)
        // 既定ブランチ名は git のバージョン/設定で master にも main にもなりうるため、
        // 検出は実装(origin/HEAD → main → master)に委ね、ここでは分岐だけ作る。
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        _ = try temp.file(named: "changed.md", contents: "after")
        _ = try temp.file(named: "added.md", contents: "new")
        _ = try temp.file(named: "dirty.md", contents: "committed")
        GitTestRepo.commitAll(message: "change", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("dirty.md", contents: "dirty", in: temp.url)

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url, target: .defaultBranch))

        func status(_ name: String) -> GitFileStatus? {
            snapshot.statuses[temp.url.appendingPathComponent(name).normalizedPathKey]
        }
        #expect(status("changed.md")?.branchChange == .modified)
        #expect(status("added.md")?.branchChange == .added)
        #expect(status("dirty.md")?.branchChange == .modified)
        #expect(status("dirty.md")?.worktreeChange == .modified)
        #expect(status("base.md") == nil)
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

        let snapshot = try #require(makeReader().status(forRepositoryAt: temp.url, target: .defaultBranch))
        let status = snapshot.statuses[temp.url.appendingPathComponent("a.md").normalizedPathKey]

        #expect(status?.worktreeChange == .modified)
        #expect(status?.branchChange == nil)
    }
}
