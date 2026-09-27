@testable import befold
import Testing

/// レビュー表示で展開するフォルダーの算出(TASK-637)。git は呼ばない純粋な写像。
@Suite
struct SidebarGitStatusRevealTests {
    private let root = "/repo"

    private func status(
        _ statuses: [String: GitFileStatus], indeterminateRoots: Set<String> = []
    ) -> SidebarGitStatus {
        SidebarGitStatus(
            repositoryRootKey: root, statuses: statuses, indeterminateRoots: indeterminateRoots
        )
    }

    private let modified = GitFileStatus(indexChange: nil, worktreeChange: .modified)

    @Test("変更ファイルの祖先フォルダーを全階層で返し、ファイル自身は返さない")
    func returnsEveryAncestorFolder() {
        let sidebar = status(["\(root)/a/b/c.md": modified, "\(root)/top.md": modified])

        let result = sidebar.foldersToReveal(under: root) { _ in false }

        #expect(result == ["\(root)/a", "\(root)/a/b"])
    }

    @Test("表示中ディレクトリの外と、表示中ディレクトリ自身は返さない")
    func excludesOutsideOfDirectory() {
        let sidebar = status(["\(root)/a/b/c.md": modified, "\(root)/x/y.md": modified])

        let result = sidebar.foldersToReveal(under: "\(root)/a") { _ in false }

        #expect(result == ["\(root)/a/b"])
    }

    @Test("丸ごと新しい未追跡フォルダーは実ディレクトリのときだけ返す（ファイルは返さない）")
    func revealsUntrackedDirectoryOnlyWhenDirectory() {
        let sidebar = status([
            "\(root)/newdir": GitFileStatus(isUntracked: true),
            "\(root)/new.md": GitFileStatus(isUntracked: true),
        ])

        let result = sidebar.foldersToReveal(under: root) { $0 == "\(root)/newdir" }

        #expect(result == ["\(root)/newdir"])
    }

    @Test("サブモジュール・ネストしたリポジトリの境界とその配下は返さない")
    func excludesIndeterminateRoots() {
        let sidebar = status(
            [
                "\(root)/sub": modified,
                "\(root)/child": GitFileStatus(isUntracked: true),
                "\(root)/lib/x.md": modified,
            ],
            indeterminateRoots: ["\(root)/sub", "\(root)/child"]
        )

        let result = sidebar.foldersToReveal(under: root) { _ in true }

        #expect(result == ["\(root)/lib"])
    }
}
