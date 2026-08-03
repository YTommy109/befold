@testable import befold
import Foundation
import Testing

/// フォルダー配下の git 変更を集約する純関数。git も UI も要らない。
struct GitFolderStatusTests {
    private let root = "/repo"

    private func aggregate(_ statuses: [String: GitFileStatus]) -> [String: GitFolderStatus] {
        GitFolderStatus.aggregate(statuses: statuses)
    }

    @Test("直下の変更ファイルは親フォルダーに集約される")
    func aggregatesDirectChild() throws {
        let result = aggregate(["\(root)/src/a.swift": GitFileStatus(worktreeChange: .modified)])

        let folder = try #require(result["\(root)/src"])
        #expect(folder.hasUnstaged)
        #expect(!folder.hasStaged)
    }

    /// 折りたたまれたフォルダーの中を見なくても気づけることが本機能の目的なので、
    /// 孫階層だけの変更が中間フォルダーとルートの両方に伝わる必要がある。
    @Test("孫階層だけの変更でも中間の全祖先フォルダーに伝わる")
    func aggregatesToEveryAncestor() throws {
        let result = aggregate(["\(root)/src/deep/nested/a.swift": GitFileStatus(indexChange: .added)])

        let ancestors = ["/src/deep/nested", "/src/deep", "/src", ""].map { root + $0 }
        for path in ancestors {
            let folder = try #require(result[path], "\(path) に集約されていない")
            #expect(folder.hasStaged)
        }
    }

    @Test("配下に変更が無いフォルダーはマップに現れない")
    func omitsFoldersWithoutChanges() {
        let result = aggregate(["\(root)/src/a.swift": GitFileStatus(worktreeChange: .modified)])

        #expect(result["\(root)/docs"] == nil)
    }

    @Test("変更が 1 件も無ければ空のマップになる")
    func emptyForNoChanges() {
        #expect(aggregate([:]).isEmpty)
    }

    /// porcelain の既定(-unormal)では未追跡ディレクトリが `dir/` の 1 エントリに畳まれ、
    /// 配下のファイルは列挙されない。そのディレクトリ自身がバッジ対象になる必要がある。
    @Test("畳み込まれた未追跡ディレクトリはそのフォルダー自身がバッジ対象になる")
    func treatsFoldedUntrackedDirectoryAsFolder() throws {
        let result = aggregate(["\(root)/newdir": GitFileStatus(isUntracked: true)])

        let folder = try #require(result["\(root)/newdir"])
        #expect(folder.hasUntracked)
        #expect(try #require(result[root]).hasUntracked)
    }

    @Test("配下に複数種類の変更があるとすべてのフラグが立つ")
    func mergesMixedChanges() throws {
        var statuses: [String: GitFileStatus] = [:]
        statuses["\(root)/src/a.swift"] = GitFileStatus(indexChange: .added)
        statuses["\(root)/src/b.swift"] = GitFileStatus(worktreeChange: .modified)
        statuses["\(root)/src/c.swift"] = GitFileStatus(isUntracked: true)
        statuses["\(root)/src/d.swift"] = GitFileStatus(isBranchModified: true)
        let result = aggregate(statuses)

        let folder = try #require(result["\(root)/src"])
        #expect(folder.hasStaged)
        #expect(folder.hasUnstaged)
        #expect(folder.hasUntracked)
        #expect(folder.hasBranchModified)
    }

    /// staged かつ unstaged のファイル 1 つでも、フォルダーとしては両方を示す。
    @Test("1 ファイルが staged と unstaged を兼ねる場合は両方のフラグが立つ")
    func mergesBothSidesOfSingleFile() throws {
        let result = aggregate([
            "\(root)/src/a.swift": GitFileStatus(indexChange: .added, worktreeChange: .modified),
        ])

        let folder = try #require(result["\(root)/src"])
        #expect(folder.hasStaged)
        #expect(folder.hasUnstaged)
    }

    /// サイドバーの親移動行(`..`)は現在ディレクトリの親を指す。親は必ず祖先なので、
    /// 配下に変更があれば集約結果に含まれる(行としてバッジを出すかは表示側の判断)。
    @Test("現在ディレクトリの親も祖先として集約される")
    func includesParentOfCurrentDirectory() {
        let result = aggregate(["\(root)/src/deep/a.swift": GitFileStatus(worktreeChange: .modified)])

        #expect(result["\(root)/src"] != nil)
    }

    @Test("クリーンな状態のエントリは集約されない")
    func ignoresCleanEntries() {
        #expect(aggregate(["\(root)/src/a.swift": GitFileStatus()]).isEmpty)
    }
}
