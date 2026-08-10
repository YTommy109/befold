@testable import befold
import Foundation
import Testing

/// `SidebarGitStatus` の引き当て。git も UI も要らない純粋な写像。
///
/// 中心にあるのは porcelain の畳み込み(`-unormal` は未追跡ディレクトリを `dir/` の
/// 1 レコードにまとめる)への対処。畳まれた配下は `files` にキーを持たないため、
/// 素直に辞書を引くだけではバッジが 1 つも出ない(TASK-345)。
struct SidebarGitStatusTests {
    private let root = "/repo"

    private func status(_ statuses: [String: GitFileStatus]) -> SidebarGitStatus {
        SidebarGitStatus(repositoryRootKey: root, statuses: statuses)
    }

    /// 未追跡ディレクトリ 1 レコードだけを持つ状態。実際の porcelain 出力と同じ形。
    private func collapsedUntrackedDirectory() -> SidebarGitStatus {
        status(["\(root)/new": GitFileStatus(isUntracked: true)])
    }

    /// 適用範囲はリポジトリルート配下。取得したディレクトリとの**等値**へ戻すと
    /// 「ルート配下のサブディレクトリ」のケースが落ちる。区切り文字を含めない
    /// 素の前方一致へ緩めると「兄弟パス」のケースが落ちる(TASK-361.2)。
    @Test("適用範囲はリポジトリルート自身とその配下だけ")
    func coversRepositoryRootAndDescendantsOnly() {
        let sidebar = status([:])

        #expect(sidebar.covers(URL(fileURLWithPath: root)))
        #expect(sidebar.covers(URL(fileURLWithPath: "\(root)/src/deep")))
        // 前方一致だけで判定すると通ってしまう兄弟パス。
        #expect(!sidebar.covers(URL(fileURLWithPath: "\(root)2")))
        #expect(!sidebar.covers(URL(fileURLWithPath: "/elsewhere")))
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

    // MARK: - ネストしたリポジトリ・サブモジュール(TASK-403)

    /// サブモジュールの実際の形。親の porcelain には `sub` の 1 レコードしか出ず、
    /// 配下のファイルは 1 件も現れない。
    private func submodule() -> SidebarGitStatus {
        SidebarGitStatus(
            repositoryRootKey: root,
            statuses: ["\(root)/sub": GitFileStatus(indexChange: nil, worktreeChange: .modified)],
            indeterminateRoots: ["\(root)/sub"]
        )
    }

    /// ネストしたリポジトリの実際の形。親から見ると未追跡ディレクトリ 1 レコードへ
    /// 畳まれるため、**畳み込みの配下**と**境界の配下**が同じ位置で重なる。
    private func nestedRepository() -> SidebarGitStatus {
        SidebarGitStatus(
            repositoryRootKey: root,
            statuses: ["\(root)/child": GitFileStatus(isUntracked: true)],
            indeterminateRoots: ["\(root)/child"]
        )
    }

    /// AC#1 と AC#2 を 1 つのテストで押さえる。バッジだけ消して絞り込みを直さないと
    /// 配下が黙って消え、絞り込みだけ直してバッジを消さないと嘘のバッジが残る。
    @Test("サブモジュール配下はバッジが出ず、かつ絞り込みでも消えない")
    func submoduleDescendantsAreIndeterminateAndKept() {
        let sidebar = submodule()
        let descendant = "\(root)/sub/a.txt"

        #expect(sidebar.fileStatus(at: descendant) == nil)
        #expect(sidebar.folderStatus(at: "\(root)/sub/inner") == nil)
        #expect(sidebar.isIndeterminate(at: descendant))
        #expect(sidebar.isIndeterminate(at: "\(root)/sub/inner/deep.txt"))
    }

    /// 境界の検出が畳み込みより先に効かないと、子リポジトリでコミット済み・クリーンな
    /// ファイルまで「新規」と表示される(TASK-403 の AC#2)。
    @Test("ネストしたリポジトリ配下は畳み込みの未追跡を継承しない")
    func nestedRepositoryDescendantsDoNotInheritUntracked() {
        let sidebar = nestedRepository()

        #expect(sidebar.fileStatus(at: "\(root)/child/committed.txt") == nil)
        #expect(sidebar.folderStatus(at: "\(root)/child/src") == nil)
        #expect(sidebar.isIndeterminate(at: "\(root)/child/committed.txt"))
    }

    /// 境界の**行そのもの**は親が答えを持っている。ここまで消すと、サブモジュールが
    /// 変更されていることも、新しいディレクトリが増えたことも見えなくなる。
    @Test("境界の行そのものは自分の状態を保つ")
    func boundaryRowKeepsItsOwnStatus() {
        #expect(submodule().fileStatus(at: "\(root)/sub")?.worktreeChange == .modified)
        #expect(submodule().isIndeterminate(at: "\(root)/sub") == false)
        #expect(nestedRepository().fileStatus(at: "\(root)/child")?.isUntracked == true)
        #expect(nestedRepository().isIndeterminate(at: "\(root)/child") == false)
    }

    /// 境界の外側は従来どおり。境界を足したことで畳み込みの扱いが壊れていないこと。
    @Test("境界の外側では畳み込みの未追跡がこれまでどおり効く")
    func collapsedUntrackedStillWorksOutsideBoundaries() {
        let sidebar = SidebarGitStatus(
            repositoryRootKey: root,
            statuses: [
                "\(root)/new": GitFileStatus(isUntracked: true),
                "\(root)/sub": GitFileStatus(indexChange: nil, worktreeChange: .modified),
            ],
            indeterminateRoots: ["\(root)/sub"]
        )

        #expect(sidebar.fileStatus(at: "\(root)/new/a.txt")?.isUntracked == true)
        #expect(sidebar.isIndeterminate(at: "\(root)/new/a.txt") == false)
    }
}
