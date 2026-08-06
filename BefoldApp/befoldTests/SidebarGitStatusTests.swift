@testable import befold
import Testing

/// `SidebarGitStatus` の引き当て。git も UI も要らない純粋な写像。
///
/// 中心にあるのは porcelain の畳み込み(`-unormal` は未追跡ディレクトリを `dir/` の
/// 1 レコードにまとめる)への対処。畳まれた配下は `files` にキーを持たないため、
/// 素直に辞書を引くだけではバッジが 1 つも出ない(TASK-345)。
struct SidebarGitStatusTests {
    private let root = "/repo"

    private func status(_ statuses: [String: GitFileStatus]) -> SidebarGitStatus {
        SidebarGitStatus(directoryKey: root, statuses: statuses)
    }

    /// 未追跡ディレクトリ 1 レコードだけを持つ状態。実際の porcelain 出力と同じ形。
    private func collapsedUntrackedDirectory() -> SidebarGitStatus {
        status(["\(root)/new": GitFileStatus(isUntracked: true)])
    }

    @Test("畳み込まれた未追跡ディレクトリ配下のファイルも未追跡として引ける")
    func reportsUntrackedForFilesUnderCollapsedDirectory() {
        let sidebar = collapsedUntrackedDirectory()

        #expect(sidebar.fileStatus(at: "\(root)/new/a.md")?.isUntracked == true)
        #expect(sidebar.fileStatus(at: "\(root)/new/deep/b.md")?.isUntracked == true)
    }

    /// ファイル行だけ直すと、同じ畳み込みの下にあるサブフォルダー行が無印のまま残る。
    @Test("畳み込まれた未追跡ディレクトリ配下のサブフォルダーも集約を引ける")
    func reportsUntrackedForFoldersUnderCollapsedDirectory() {
        let sidebar = collapsedUntrackedDirectory()

        #expect(sidebar.folderStatus(at: "\(root)/new/deep")?.hasUntracked == true)
    }

    /// 祖先の判定に `folders[ancestor]?.hasUntracked` を使うと、未追跡ファイルを 1 つ
    /// 含むだけの追跡済みフォルダーで、同じフォルダー内の未変更ファイルまで変更ありに
    /// なる(TASK-285 が警告している誤判定)。畳み込みの事実そのものを見ること。
    @Test("未追跡ファイルを含むだけのフォルダーでは、兄弟の未変更ファイルに印を付けない")
    func doesNotMarkCleanSiblingsOfUntrackedFile() {
        let sidebar = status(["\(root)/src/new.md": GitFileStatus(isUntracked: true)])

        #expect(sidebar.fileStatus(at: "\(root)/src/tracked.md") == nil)
        #expect(sidebar.hasChange(at: "\(root)/src/tracked.md") == false)
    }

    /// 「絞り込みに残る行には必ずバッジが付く」の担保。判定が 2 経路に分かれて
    /// 再び食い違ったらここで落ちる。
    @Test("hasChange はバッジの有無と一致する")
    func hasChangeAgreesWithBadgeLookup() {
        let sidebar = status([
            "\(root)/new": GitFileStatus(isUntracked: true),
            "\(root)/src/edited.md": GitFileStatus(worktreeChange: .modified),
            "\(root)/lib/added.md": GitFileStatus(branchChange: .added),
        ])
        let pathKeys = [
            "\(root)", "\(root)/new", "\(root)/new/a.md", "\(root)/new/deep",
            "\(root)/new/deep/b.md", "\(root)/src", "\(root)/src/edited.md",
            "\(root)/src/clean.md", "\(root)/lib", "\(root)/lib/added.md",
            "\(root)/docs", "\(root)/docs/untouched.md",
        ]

        for pathKey in pathKeys {
            let hasBadge = sidebar.fileStatus(at: pathKey) != nil
                || sidebar.folderStatus(at: pathKey) != nil
            #expect(sidebar.hasChange(at: pathKey) == hasBadge, "\(pathKey)")
        }
    }

    @Test("変更が無いパスでは状態も集約も引けない")
    func returnsNothingForCleanPaths() {
        let sidebar = status(["\(root)/src/edited.md": GitFileStatus(worktreeChange: .modified)])

        #expect(sidebar.fileStatus(at: "\(root)/docs/other.md") == nil)
        #expect(sidebar.folderStatus(at: "\(root)/docs") == nil)
    }
}
