@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 実 git を spawn して `GitDiffReader` の分類を確かめる。
///
/// 差分の「本文が無い」理由(未追跡 / 変更なし / バイナリ / コミット前 / 管理外)は
/// git の出力と終了コードの組み合わせでしか判別できず、フィクスチャで固定すると
/// 実際の git と乖離する。ここは実 git でのみ検証する。
struct GitDiffReaderIntegrationTests {
    /// git 1 回あたりの予算は他のポーリング待機と同じ単一情報源から採る。
    private func makeReader() -> GitDiffReader {
        GitDiffReader(runner: GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10)))
    }

    @Test("未ステージの変更が unified diff で返る")
    func returnsUnifiedDiffForUnstagedChange() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.swift", contents: "let a = 2\n", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        guard case let .diff(text) = result else {
            Issue.record("差分が返らなかった: \(String(describing: result))")
            return
        }
        #expect(text.contains("@@"))
        #expect(text.contains("-let a = 1"))
        #expect(text.contains("+let a = 2"))
    }

    /// ビューアは「ファイルを読む」画面なので、変更の周辺だけを抜き出すと前後が飛んで
    /// 読めなくなる。既定の -U3 では 3 行を超えて離れた行が落ちるため、全文を出す。
    @Test("変更から離れた行も含めてファイル全体が差分に載る")
    func includesWholeFileNotJustChangedNeighborhood() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        // 1 行目だけを変更し、-U3 の文脈からは外れる 10 行目以降まで用意する。
        let original = (1 ... 12).map { "let v\($0) = \($0)\n" }.joined()
        let modified = original.replacingOccurrences(of: "let v1 = 1\n", with: "let v1 = 99\n")
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: original, in: temp.url)
        try GitTestRepo.modifyWithoutStaging("a.swift", contents: modified, in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        guard case let .diff(text) = result else {
            Issue.record("差分が返らなかった: \(String(describing: result))")
            return
        }
        #expect(text.contains(" let v12 = 12"))
        // 全文が 1 つのハンクに収まるので、ハンクの区切りも 1 つだけになる。
        #expect(text.components(separatedBy: "@@ -").count - 1 == 1)
    }

    /// 比較対象を index ではなく HEAD にした理由そのもの。`git diff`(index 比較)だと
    /// ステージ済みの変更が差分から消え、バッジと表示が食い違う。
    @Test("ステージ済みの変更も差分に含まれる")
    func includesStagedChanges() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        try GitTestRepo.stageChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        guard case let .diff(text) = result else {
            Issue.record("差分が返らなかった: \(String(describing: result))")
            return
        }
        #expect(text.contains("+let a = 2"))
    }

    @Test("変更が無ければ noChanges")
    func reportsNoChangesForCleanFile() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        #expect(result == .noChanges)
    }

    /// 未追跡ファイルも diff は成功して空を返す。空かどうかで判定していると
    /// 「変更なし」と誤答する(この分類が退行したらここが落ちる)。
    @Test("未追跡ファイルは untracked（空出力を変更なしと混同しない）")
    func distinguishesUntrackedFromNoChanges() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", in: temp.url)
        try GitTestRepo.addUntrackedFile(named: "new.swift", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("new.swift"), in: temp.url)

        #expect(result == .untracked)
    }

    @Test("バイナリファイルは binary")
    func reportsBinary() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        let binary = temp.url.appendingPathComponent("b.dat")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: binary)
        GitTestRepo.run(["add", "b.dat"], in: temp.url)
        GitTestRepo.run(["commit", "-m", "init"], in: temp.url)
        try Data([0x00, 0x09, 0x7F, 0x00]).write(to: binary)

        #expect(makeReader().diff(forFileAt: binary, in: temp.url) == .binary)
    }

    @Test("コミットが無いリポジトリは noCommits")
    func reportsNoCommits() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.addUntrackedFile(named: "a.swift", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        #expect(result == .noCommits)
    }

    @Test("git 管理外は notInRepository")
    func reportsNotInRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try GitTestRepo.addUntrackedFile(named: "a.swift", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        #expect(result == .notInRepository)
    }

    @Test("上限を超える差分は tooLarge")
    func reportsTooLargeDiff() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "big.txt", contents: "seed\n", in: temp.url)
        let huge = String(repeating: "0123456789abcdef\n", count: GitDiffReader.maxDiffBytes / 8)
        try GitTestRepo.modifyWithoutStaging("big.txt", contents: huge, in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("big.txt"), in: temp.url)

        guard case let .tooLarge(byteCount) = result else {
            Issue.record("tooLarge が返らなかった: \(String(describing: result))")
            return
        }
        #expect(byteCount > GitDiffReader.maxDiffBytes)
    }
}

/// 比較の起点がサイドバーのバッジと揃っていることを実 git で確かめる。
///
/// バッジ(`GitStatusReader.branchChanges`)は `merge-base HEAD <defaultBranch>` から
/// HEAD までを見て「ブランチで変えたもの」を出す。差分ビューアが HEAD 基準のままだと、
/// ブランチでコミット済み・作業ツリーがきれいなファイルで「バッジは M なのに差分は空」に
/// なる(TASK-352)。ここが落ちたら基準がずれている。
struct GitDiffComparisonBaseIntegrationTests {
    private func makeReader() -> GitDiffReader {
        GitDiffReader(runner: GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10)))
    }

    private func makeStatusReader() -> GitStatusReader {
        let runner = GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10))
        return GitStatusReader(runner: runner, repository: GitRepository())
    }

    /// AC#1: ブランチでコミット済み・作業ツリーがきれいでも差分が出る。
    @Test("ブランチでコミットした変更が、作業ツリーがきれいでも差分に出る")
    func showsBranchCommittedChangeWithCleanWorktree() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        guard case let .diff(text) = result else {
            Issue.record("差分が返らなかった: \(String(describing: result))")
            return
        }
        #expect(text.contains("-let a = 1"))
        #expect(text.contains("+let a = 2"))
    }

    /// AC#5: バッジと差分の一致。バッジが「ブランチで変えた」と言うファイルには
    /// 必ず差分がある。片方だけ基準を変えるとここが落ちる。
    @Test("バッジがブランチ変更を示すファイルには差分がある")
    func badgeAndDiffAgreeOnBranchChange() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        GitTestRepo.createBranch(named: "feature", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)
        let file = temp.url.appendingPathComponent("a.swift")

        let snapshot = try #require(makeStatusReader().status(forRepositoryAt: temp.url))
        let status = try #require(snapshot.statuses[file.normalizedPathKey])
        #expect(status.branchChange != nil)

        let result = makeReader().diff(forFileAt: file, in: temp.url)
        if case .diff = result {} else {
            Issue.record("バッジは変更ありなのに差分が空: \(String(describing: result))")
        }
    }

    /// AC#2: デフォルトブランチの上では merge-base が HEAD 自身になるため、
    /// コミット済みの変更は差分に出ない(従来どおり「未コミットの変更」を見る)。
    @Test("デフォルトブランチ上ではコミット済みの変更は差分に出ない")
    func doesNotShowCommittedChangeOnDefaultBranch() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        #expect(result == .noChanges)
    }

    /// AC#3: 起点を特定できないときは HEAD へ落とす。差分が空だったから落とす、ではない。
    /// デフォルトブランチ名でも origin/HEAD でもないブランチしか無いリポジトリで測る。
    @Test("デフォルトブランチを特定できないときは HEAD 基準へ落ちる")
    func fallsBackToHeadWhenDefaultBranchIsUnknown() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "let a = 1\n", in: temp.url)
        // main / master / origin/HEAD のいずれでもない名前だけにする。
        GitTestRepo.run(["branch", "-m", "trunk"], in: temp.url)
        try GitTestRepo.commitChange(to: "a.swift", contents: "let a = 2\n", in: temp.url)

        let file = temp.url.appendingPathComponent("a.swift")
        // HEAD 基準なので、コミット済みの変更は出ない。
        #expect(makeReader().diff(forFileAt: file, in: temp.url) == .noChanges)

        // 未コミットの変更は HEAD 基準でも出る(機能全体が死んでいないことの確認)。
        try GitTestRepo.modifyWithoutStaging("a.swift", contents: "let a = 3\n", in: temp.url)
        if case .diff = makeReader().diff(forFileAt: file, in: temp.url) {} else {
            Issue.record("HEAD 基準の差分すら出なかった")
        }
    }
}

/// 本文からのバイナリ判定だけは、実 git を起こさず書式で固定する。
struct GitDiffBinaryDetectionTests {
    @Test("Binary files 行を含む差分をバイナリと判定する")
    func detectsBinaryMarker() {
        let text = """
        diff --git a/b.dat b/b.dat
        index c94be36..04d3356 100644
        Binary files a/b.dat and b/b.dat differ

        """
        #expect(GitDiffReader.isBinaryDiff(text))
    }

    /// 追加行として `Binary files ` を含むテキストファイルを誤判定しないこと。
    /// 差分本文の行は必ず `+` / `-` / ` ` で始まるため行頭一致で区別できる。
    @Test("本文中の Binary files という文字列では誤判定しない")
    func doesNotMisclassifyTextContainingMarker() {
        let text = """
        diff --git a/a.txt b/a.txt
        index 1111111..2222222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -old
        +Binary files a/x and b/x differ

        """
        #expect(!GitDiffReader.isBinaryDiff(text))
    }
}
