@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 実 git が作ったリポジトリを `GitRepository`(libgit2 実装)が読めることの Integration テスト。
///
/// libgit2 化で「git の出力テキストをパースする純関数」が無くなったため、worktree 列挙の
/// 網羅(本体の含有・ブランチ短縮・detached・並び順)もここが担う。インメモリの
/// フィクスチャで代替できる部分は無い(libgit2 に読ませる実リポジトリが要る)。
struct GitRepositoryIntegrationTests {
    private func makeRepository() -> GitRepository {
        GitRepository()
    }

    private func makeRepo(_ dir: URL) throws {
        GitTestRepo.initRepository(at: dir)
        try GitTestRepo.commitFile(in: dir)
    }

    @Test("root と追跡ファイルを取得する")
    func rootAndTrackedFiles() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = makeRepository()
        let lookup = repo.root(forFileAt: temp.url.appendingPathComponent("main.swift"))
        let root = try #require(lookup.foundRoot)
        #expect(root.standardizedFileURL == temp.url.standardizedFileURL)
        #expect(repo.trackedFiles(at: root)?.map(\.lastPathComponent) == ["main.swift"])
    }

    /// 外部 git 方式が `ls-files -z` を使っていた理由そのものの検証。改行区切りの出力では
    /// スペースや引用符を含むファイル名が `core.quotepath` でエスケープされて壊れた。
    /// index から生バイトで取る libgit2 方式でも同じ結果になることを固定する。
    @Test("スペース・引用符を含むファイル名も欠けずに列挙される")
    func trackedFilesHandleSpacesAndQuotesInNames() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let awkwardNames = ["my notes.md", "quote\"name.md", "日本語 メモ.md"]
        for name in awkwardNames {
            try "x".write(to: temp.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        GitTestRepo.run(["add", "."], in: temp.url)

        let tracked = makeRepository().trackedFiles(at: temp.url)?.map(\.lastPathComponent)

        for name in awkwardNames {
            #expect(tracked?.contains(name) == true, "\(name) が列挙されていない")
        }
    }

    /// 実 git が作ったリポジトリで「管理外」が確定として返ること。開けなかった場合との
    /// 区別(`.undetermined`)は `GitRepositoryTests` が実 git 抜きで担保する。
    @Test("git 管理外は notARepository として返る")
    func reportsNotARepositoryOutsideRepo() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        #expect(makeRepository().root(forFileAt: temp.url.appendingPathComponent("x.md")) == .notARepository)
    }

    @Test("index の更新で fingerprint が変わる")
    func fingerprintChangesOnIndexUpdate() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)
        let repo = makeRepository()
        let before = repo.indexFingerprint(at: temp.url)
        #expect(before != nil)
        try "x".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        GitTestRepo.run(["add", "b.txt"], in: temp.url)
        let after = repo.indexFingerprint(at: temp.url)
        #expect(after != before)
    }

    @Test("本体リポジトリの identity はディレクトリ名と自身のルートを返す")
    func repositoryIdentityForMainRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let identity = makeRepository().repositoryIdentity(forRoot: temp.url)

        #expect(identity.label == temp.url.standardizedFileURL.lastPathComponent)
        #expect(identity.mainRoot.resolvingSymlinksInPath() == temp.url.resolvingSymlinksInPath())
    }

    @Test("worktree の identity は本体ルートを指す")
    func repositoryIdentityForWorktree() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("feature-x")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feature-x"], in: main.url)

        let identity = makeRepository().repositoryIdentity(forRoot: worktreeDir)

        #expect(identity.label == "\(main.url.standardizedFileURL.lastPathComponent) (feature-x)")
        #expect(identity.mainRoot.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
    }

    /// 本体 + ブランチ付き worktree + detached worktree の 3 件で、worktree 列挙の
    /// 期待値をまとめて固定する。
    ///
    /// `git_worktree_list` はリンク worktree だけを返し本体を含まないため、本体が
    /// 抜けていないことが最初の関門(AC #3)。ブランチ名は `git_worktree_*` からは
    /// 取れず、各 worktree を開いて HEAD から読んでいる。
    @Test("worktree 一覧は本体を含み、各エントリのブランチ名を返す")
    func worktreesIncludeMainAndBranchNames() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        // ディレクトリ名とブランチ名を意図的にずらし、ブランチ側を拾っていることを確かめる。
        let worktreeDir = worktreeParent.url.appendingPathComponent("etc002")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feat/repository"], in: main.url)
        let detachedDir = worktreeParent.url.appendingPathComponent("detached-wt")
        GitTestRepo.run(["worktree", "add", "--detach", detachedDir.path], in: main.url)

        let fromMain = makeRepository().worktrees(forRoot: main.url)

        #expect(fromMain.count == 3)
        // 本体が先頭に来る(メニューの表示順がこれに依る)。
        #expect(fromMain.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
        // isMain は一覧の位置ではなく共通 gitdir 由来かで決まる。並び順と別々に固定して、
        // 片方だけが壊れた場合も落ちるようにする。
        #expect(fromMain.filter(\.isMain).map(\.root.lastPathComponent) == [main.url.lastPathComponent])
        #expect(fromMain.first?.branch != nil)

        let branched = fromMain.first { $0.root.resolvingSymlinksInPath() == worktreeDir.resolvingSymlinksInPath() }
        #expect(branched?.branch == "feat/repository")
        #expect(branched?.displayName == "feat/repository (etc002)")

        // detached HEAD ではブランチが無く、表示はディレクトリ名だけになる。
        let detached = fromMain.first { $0.root.resolvingSymlinksInPath() == detachedDir.resolvingSymlinksInPath() }
        #expect(detached?.branch == nil)
        #expect(detached?.displayName == "detached-wt")
    }

    /// worktree 側から列挙しても同じ一覧・同じ並びになる。`worktrees(forRoot:)` は
    /// root が本体でない場合だけ共通 gitdir 経由で開き直すため、この経路は本体からの
    /// 呼び出しとは別のコードを通る。
    @Test("worktree 側から列挙しても本体が先頭に来る")
    func worktreesFromLinkedWorktreeStartWithMain() throws {
        let main = try TempDir(prefix: "main-repo")
        defer { withExtendedLifetime(main) {} }
        try makeRepo(main.url)
        let worktreeParent = try TempDir(prefix: "worktree-parent")
        defer { withExtendedLifetime(worktreeParent) {} }
        let worktreeDir = worktreeParent.url.appendingPathComponent("etc002")
        GitTestRepo.run(["worktree", "add", worktreeDir.path, "-b", "feat/repository"], in: main.url)

        let fromWorktree = makeRepository().worktrees(forRoot: worktreeDir)

        #expect(fromWorktree.map(\.isMain) == [true, false])
        #expect(fromWorktree.first?.root.resolvingSymlinksInPath() == main.url.resolvingSymlinksInPath())
        #expect(fromWorktree.last?.branch == "feat/repository")
    }

    /// worktree が本体だけのリポジトリ。`RecentRepositoriesMenuController` は
    /// `worktrees.count > 1` でフラット表示へ縮退するため、ここが 1 件であることが
    /// 「worktree を使っていない普通のリポジトリでサブメニューを出さない」条件になる。
    @Test("worktree を追加していないリポジトリは本体 1 件だけを返す")
    func worktreesForRepositoryWithoutLinkedWorktrees() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeRepo(temp.url)

        let worktrees = makeRepository().worktrees(forRoot: temp.url)

        #expect(worktrees.count == 1)
        #expect(worktrees.first?.isMain == true)
        #expect(worktrees.first?.root.resolvingSymlinksInPath() == temp.url.resolvingSymlinksInPath())
    }

    /// submodule の gitlink は index に載るため、追跡ファイルとして列挙される
    /// (`git ls-files` と同じ挙動)。libgit2 の index 走査でも同じであることを固定する。
    @Test("submodule の gitlink も追跡ファイルとして列挙される")
    func trackedFilesIncludeSubmoduleGitlink() throws {
        let inner = try TempDir(prefix: "inner-repo")
        defer { withExtendedLifetime(inner) {} }
        try makeRepo(inner.url)
        let outer = try TempDir(prefix: "outer-repo")
        defer { withExtendedLifetime(outer) {} }
        try makeRepo(outer.url)
        GitTestRepo.run(
            ["-c", "protocol.file.allow=always", "submodule", "add", inner.url.path, "vendor/sub"], in: outer.url
        )

        let tracked = makeRepository().trackedFiles(at: outer.url)?.map(\.lastPathComponent)

        #expect(tracked?.contains("sub") == true, "submodule の gitlink が列挙されていない: \(tracked ?? [])")
    }
}
