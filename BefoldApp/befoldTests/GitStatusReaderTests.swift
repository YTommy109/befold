@testable import befold
import Foundation
import Testing

/// `git status --porcelain=v2 -z` のパースを、実 git を起動せずフィクスチャで検証する
/// (`GitRepositoryTests.parsesWorktreeListPorcelain` と同じ方針)。
struct GitStatusReaderTests {
    /// NUL 区切りのレコード列を組み立てる。末尾にも NUL が付くのが実際の出力形。
    private func porcelain(_ records: [String]) -> Data {
        Data(records.joined(separator: "\u{0}").utf8) + Data([0])
    }

    private func statuses(_ records: [String]) -> [String: GitFileStatus] {
        Dictionary(
            uniqueKeysWithValues: GitStatusReader.parsePorcelainV2(porcelain(records))
                .map { ($0.path, $0.status) }
        )
    }

    @Test("staged / unstaged / untracked を XY コードから判別する")
    func classifiesStagedUnstagedUntracked() {
        let parsed = statuses([
            "1 M. N... 100644 100644 100644 aaa bbb staged.swift",
            "1 .M N... 100644 100644 100644 aaa bbb unstaged.swift",
            "? untracked.swift",
        ])

        #expect(parsed["staged.swift"] == GitFileStatus(indexChange: .modified, worktreeChange: nil))
        #expect(parsed["unstaged.swift"] == GitFileStatus(indexChange: nil, worktreeChange: .modified))
        #expect(parsed["untracked.swift"]
            == GitFileStatus(indexChange: nil, worktreeChange: nil, isUntracked: true))
    }

    @Test("staged と unstaged が両立するファイルは両辺の変更種別を保持する")
    func keepsBothSidesWhenStagedAndUnstaged() {
        let parsed = statuses(["1 AM N... 000000 100644 100644 aaa bbb both.swift"])

        #expect(parsed["both.swift"] == GitFileStatus(indexChange: .added, worktreeChange: .modified))
    }

    @Test("ヘッダ行・ignored・変更なしはバッジ対象に含めない")
    func skipsHeadersIgnoredAndUnchanged() {
        let parsed = statuses([
            "# branch.oid aaaaaaa",
            "# branch.head main",
            "! ignored.swift",
            "1 .. N... 100644 100644 100644 aaa bbb unchanged.swift",
        ])

        #expect(parsed.isEmpty)
    }

    /// 改名レコード(`2`)は元パスが次の NUL フィールドとして続く。読み飛ばさないと
    /// 元パスを次のレコードとして解釈してしまい、以降の対応がすべてずれる。
    @Test("改名レコードの元パスを読み飛ばし、後続レコードがずれない")
    func skipsOriginalPathFieldOfRenameRecords() {
        let parsed = statuses([
            "2 R. N... 100644 100644 100644 aaa bbb R100 new.swift",
            "old.swift",
            "1 .M N... 100644 100644 100644 aaa bbb after.swift",
        ])

        #expect(parsed["new.swift"] == GitFileStatus(indexChange: .renamed, worktreeChange: nil))
        #expect(parsed["after.swift"] == GitFileStatus(indexChange: nil, worktreeChange: .modified))
        #expect(parsed["old.swift"] == nil)
        #expect(parsed.count == 2)
    }

    @Test("未マージ(u)レコードは両辺を unmerged として扱う")
    func parsesUnmergedRecords() {
        let parsed = statuses(["u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.swift"])

        #expect(parsed["conflict.swift"] == GitFileStatus(indexChange: .unmerged, worktreeChange: .unmerged))
    }

    // MARK: - Branch Diff (TASK-186.3)

    @Test("name-status: 変更後のパスを列挙する")
    func parsesNameStatusPaths() {
        let paths = GitStatusReader.parseNameStatus(porcelain(["M", "changed.swift", "A", "added.swift"]))

        #expect(paths == ["changed.swift", "added.swift"])
    }

    /// 改名・複製だけはパスが 2 つ続く。読み進める数を間違えると以降が丸ごとずれる。
    @Test("name-status: 改名・複製は変更後のパスだけを採り、後続がずれない")
    func parsesRenameAndCopyEntries() {
        let paths = GitStatusReader.parseNameStatus(
            porcelain(["R100", "old.swift", "new.swift", "C75", "src.swift", "copy.swift", "M", "after.swift"])
        )

        #expect(paths == ["new.swift", "copy.swift", "after.swift"])
    }

    @Test("name-status: 空の出力は空の一覧になる")
    func parsesEmptyNameStatus() {
        #expect(GitStatusReader.parseNameStatus(Data()).isEmpty)
    }

    @Test("スペースを含むファイル名でもパスが欠けない")
    func keepsPathsContainingSpaces() {
        let parsed = statuses([
            "1 .M N... 100644 100644 100644 aaa bbb my notes.md",
            "? new file.md",
        ])

        #expect(parsed["my notes.md"] == GitFileStatus(indexChange: nil, worktreeChange: .modified))
        #expect(parsed["new file.md"]?.isUntracked == true)
    }
}
