@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 純粋関数: gh-stack のスタックファイルの解釈。
struct GitParentBranchResolverParsingTests {
    private func parse(_ json: String, _ branch: String) -> String? {
        GitParentBranchResolver.parentBranch(of: branch, inStackFile: Data(json.utf8))
    }

    private let stack = """
    {"schemaVersion": 1, "repository": "x", "stacks": [
      {"trunk": {"branch": "main", "head": "h"},
       "branches": [{"branch": "a", "base": "b"}, {"branch": "b"}, {"branch": "c"}]},
      {"trunk": {"branch": "dev"}, "branches": [{"branch": "z"}]}
    ]}
    """

    @Test("スタックの途中のブランチは一つ前のブランチが親")
    func middleBranchHasPreviousAsParent() {
        #expect(parse(stack, "b") == "a")
        #expect(parse(stack, "c") == "b")
    }

    @Test("スタックの先頭は trunk が親")
    func firstBranchHasTrunkAsParent() {
        #expect(parse(stack, "a") == "main")
    }

    @Test("複数スタックのうち属するほうの trunk を返す")
    func picksTheOwningStack() {
        #expect(parse(stack, "z") == "dev")
    }

    @Test("どのスタックにも属さないブランチと trunk 自身は nil")
    func unknownBranchIsNil() {
        #expect(parse(stack, "other") == nil)
        #expect(parse(stack, "main") == nil)
    }

    @Test("未知の schemaVersion と壊れた JSON は nil")
    func unsupportedOrBrokenIsNil() {
        #expect(parse(stack.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2"), "a") == nil)
        #expect(parse("{not json", "a") == nil)
        #expect(parse("{}", "a") == nil)
    }
}

/// 実リポジトリにスタックファイルを手書きして、配置場所ごとの解決と縮退を確かめる。
struct GitParentBranchIntegrationTests {
    /// default ← feat-a ← feat-b の履歴を作り、feat-b をチェックアウトした状態にする。
    private struct Stacked {
        let temp: TempDir
        let trunk: String
        let aHead: String
        let bHead: String
    }

    private func makeStackedRepository() throws -> Stacked {
        let temp = try TempDir()
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "0\n", in: temp.url)
        let resolver = GitComparisonBaseResolver()
        let trunk = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .defaultBranch)?.baseBranch)
        GitTestRepo.createBranch(named: "feat-a", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "1\n", in: temp.url)
        let aHead = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .head)?.baseID)
        GitTestRepo.createBranch(named: "feat-b", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "2\n", in: temp.url)
        let bHead = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .head)?.baseID)
        return Stacked(temp: temp, trunk: trunk, aHead: aHead, bHead: bHead)
    }

    private func writeStack(trunk: String, in temp: TempDir) throws {
        try GitTestRepo.writeGhStack(
            trunk: trunk, branches: ["feat-a", "feat-b"],
            toGitDirectory: temp.url.appendingPathComponent(".git")
        )
    }

    @Test("親ブランチ基準は一つ前のブランチとの merge-base で、スタック全体基準と区別される")
    func resolvesParentFromCommonDir() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        let aHead = repo.aHead
        defer { withExtendedLifetime(temp) {} }
        try writeStack(trunk: trunk, in: temp)
        let resolver = GitComparisonBaseResolver()

        let parent = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .parentBranch))
        #expect(parent.baseID == aHead)
        #expect(parent.baseBranch == "feat-a")
        #expect(parent.degraded == false)
        #expect(parent.parentDiffersFromDefault)

        let whole = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .defaultBranch))
        #expect(whole.baseID != aHead)
        #expect(whole.baseBranch?.hasSuffix(trunk) == true)
        #expect(whole.degraded == false)
        #expect(whole.parentDiffersFromDefault)
    }

    @Test("作業中基準は HEAD そのもの")
    func headTargetIsHead() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        let bHead = repo.bHead
        defer { withExtendedLifetime(temp) {} }
        try writeStack(trunk: trunk, in: temp)
        let head = try #require(GitComparisonBaseResolver().comparisonBase(forRepositoryAt: temp.url, target: .head))
        #expect(head.baseID == bHead)
        #expect(head.baseBranch == nil)
    }

    @Test("スタックの先頭ブランチの親は trunk(デフォルトブランチ)で、差は無い扱いになる")
    func firstBranchParentIsTrunk() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        defer { withExtendedLifetime(temp) {} }
        try writeStack(trunk: trunk, in: temp)
        GitTestRepo.run(["checkout", "feat-a"], in: temp.url)

        let parent = try #require(GitComparisonBaseResolver().comparisonBase(
            forRepositoryAt: temp.url,
            target: .parentBranch
        ))
        #expect(parent.baseBranch == trunk)
        #expect(parent.parentDiffersFromDefault == false)
        #expect(parent.degraded == false)
    }

    @Test("スタックファイルが無ければデフォルトブランチへ縮退し、縮退が分かる")
    func degradesWithoutStackFile() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        defer { withExtendedLifetime(temp) {} }
        let resolver = GitComparisonBaseResolver()
        let parent = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .parentBranch))
        let whole = try #require(resolver.comparisonBase(forRepositoryAt: temp.url, target: .defaultBranch))
        #expect(parent.degraded)
        #expect(parent.baseID == whole.baseID)
        #expect(parent.baseBranch == whole.baseBranch)
        #expect(parent.parentDiffersFromDefault == false)
    }

    @Test("未知の schemaVersion・現在ブランチがスタックに無い・detached HEAD は縮退する")
    func degradesOnUnusableStack() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        defer { withExtendedLifetime(temp) {} }
        let gitDir = temp.url.appendingPathComponent(".git")
        let resolver = GitComparisonBaseResolver()

        try GitTestRepo.writeGhStack(
            trunk: trunk,
            branches: ["feat-a", "feat-b"],
            schemaVersion: 2,
            toGitDirectory: gitDir
        )
        #expect(resolver.comparisonBase(forRepositoryAt: temp.url, target: .parentBranch)?.degraded == true)

        try GitTestRepo.writeGhStack(trunk: trunk, branches: ["feat-a"], toGitDirectory: gitDir)
        #expect(resolver.comparisonBase(forRepositoryAt: temp.url, target: .parentBranch)?.degraded == true)

        try writeStack(trunk: trunk, in: temp)
        GitTestRepo.run(["checkout", "--detach"], in: temp.url)
        #expect(resolver.comparisonBase(forRepositoryAt: temp.url, target: .parentBranch)?.degraded == true)
    }

    @Test("親ブランチが refs/heads にも origin にも無ければ縮退する")
    func degradesWhenParentBranchIsGone() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        defer { withExtendedLifetime(temp) {} }
        try writeStack(trunk: trunk, in: temp)
        GitTestRepo.run(["branch", "-D", "feat-a"], in: temp.url)

        let parent = try #require(GitComparisonBaseResolver().comparisonBase(
            forRepositoryAt: temp.url,
            target: .parentBranch
        ))
        #expect(parent.degraded)
        #expect(parent.parentDiffersFromDefault == false)
    }

    @Test("親ブランチがローカルに無くても refs/remotes/origin に残っていれば使う")
    func usesRemoteTrackingParent() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        let aHead = repo.aHead
        defer { withExtendedLifetime(temp) {} }
        try writeStack(trunk: trunk, in: temp)
        GitTestRepo.run(["update-ref", "refs/remotes/origin/feat-a", aHead], in: temp.url)
        GitTestRepo.run(["branch", "-D", "feat-a"], in: temp.url)

        let parent = try #require(GitComparisonBaseResolver().comparisonBase(
            forRepositoryAt: temp.url,
            target: .parentBranch
        ))
        #expect(parent.degraded == false)
        #expect(parent.baseID == aHead)
    }

    @Test("linked worktree では per-worktree の admin dir にあるスタックファイルを読む(gh-stack v0.1.1)")
    func resolvesParentFromPerWorktreeDir() throws {
        let repo = try makeStackedRepository()
        let temp = repo.temp
        let trunk = repo.trunk
        let aHead = repo.aHead
        defer { withExtendedLifetime(temp) {} }
        let worktree = temp.url.appendingPathComponent("wt")
        GitTestRepo.run(["worktree", "add", "-b", "feat-w", worktree.path, "feat-b"], in: temp.url)
        // common dir には何も置かず、worktree の admin dir だけに置く。
        let adminDir = temp.url.appendingPathComponent(".git/worktrees/wt")
        try GitTestRepo.writeGhStack(trunk: trunk, branches: ["feat-a", "feat-w"], toGitDirectory: adminDir)

        let parent = try #require(GitComparisonBaseResolver().comparisonBase(
            forRepositoryAt: worktree,
            target: .parentBranch
        ))
        #expect(parent.degraded == false)
        #expect(parent.baseBranch == "feat-a")
        #expect(parent.baseID == aHead)
    }
}

/// 比較の起点がバッジと差分で揃っていること(`GitDiffComparisonBaseIntegrationTests` の基準別版)。
struct GitComparisonTargetAgreementTests {
    /// 3 基準を固定して解決するリゾルバ(バッジと差分に同じ基準を渡すため)。
    private struct FixedTarget: GitComparisonBaseResolving {
        let target: GitComparisonTarget
        func comparisonBase(forRepositoryAt root: URL, target _: GitComparisonTarget) -> GitComparisonResolution? {
            GitComparisonBaseResolver().comparisonBase(forRepositoryAt: root, target: target)
        }
    }

    /// AC#5: バッジと差分の一致。バッジが「ブランチで変えた」と言うファイルには
    /// 必ず差分があり、言わないファイルには差分が無い。片方だけ基準を変えるとここが落ちる。
    /// 基準(親ブランチ / デフォルトブランチ / HEAD)ごとに同じ関係が成り立つこと(TASK-353.1)。
    @Test("バッジがブランチ変更を示すファイルにだけ差分がある", arguments: GitComparisonTarget.allCases)
    func badgeAndDiffAgreeOnBranchChange(target: GitComparisonTarget) throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        try GitTestRepo.commitChange(to: "b.swift", contents: "let b = 1\n", in: temp.url)
        let trunk = try #require(
            GitComparisonBaseResolver().comparisonBase(forRepositoryAt: temp.url, target: .defaultBranch)?.baseBranch
        )
        GitTestRepo.createBranch(named: "feat-a", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)
        GitTestRepo.createBranch(named: "feat-b", in: temp.url)
        try GitTestRepo.commitChange(to: "b.swift", contents: "let b = 2\n", in: temp.url)
        try GitTestRepo.writeGhStack(
            trunk: trunk, branches: ["feat-a", "feat-b"], toGitDirectory: temp.url.appendingPathComponent(".git")
        )
        let resolver = FixedTarget(target: target)
        let statusReader = GitStatusReader(comparisonBase: resolver)
        let diffReader = GitDiffReader(comparisonBase: resolver)
        let snapshot = try #require(statusReader.status(forRepositoryAt: temp.url))

        // 親基準では b.swift だけ、デフォルト基準では両方、HEAD 基準ではどちらも空。
        let expectChanged: [String: Bool] = switch target {
        case .parentBranch: ["a.swift": false, "b.swift": true]
        case .defaultBranch: ["a.swift": true, "b.swift": true]
        case .head: ["a.swift": false, "b.swift": false]
        }
        for (name, expected) in expectChanged {
            let file = temp.url.appendingPathComponent(name)
            let badge = snapshot.statuses[file.normalizedPathKey]?.branchChange != nil
            let hasDiff = if case .diff = diffReader.diff(forFileAt: file, in: temp.url) { true } else { false }
            #expect(badge == expected, "\(target) \(name): バッジ")
            #expect(hasDiff == expected, "\(target) \(name): 差分")
        }
    }
}
