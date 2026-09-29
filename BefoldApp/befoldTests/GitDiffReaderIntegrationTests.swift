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
        GitDiffReader()
    }

    /// 読むだけで済む分類を 1 つのリポジトリにまとめて確かめる。ファイルごとに状態を変えた
    /// fixture を 1 回で作り、差分はファイル単位の pathspec で取るので互いに干渉しない
    /// (TASK-662.6。以前は 7 件が個別に init・commit していた)。
    /// `.git/index` の mtime を触る `diffDoesNotDisturbIndexFingerprint` はここへ入れない。
    @Test("読むだけの分類を共有リポジトリで確かめる", arguments: ReadOnlyCase.allCases)
    func classifiesFileInSharedRepository(_ readOnlyCase: ReadOnlyCase) throws {
        let root = try Self.sharedRepository.get().url
        let result = makeReader().diff(forFileAt: root.appendingPathComponent(readOnlyCase.fileName), in: root)
        readOnlyCase.verify(result)
    }

    /// 共有リポジトリ。テストプロセスの寿命と同じだけ生きる(static は解放されないため、
    /// 一時ディレクトリは OS の掃除に任せる)。
    private static let sharedRepository = Result { try makeSharedRepository() }

    private static func makeSharedRepository() throws -> TempDir {
        let temp = try TempDir()
        let root = temp.url
        GitTestRepo.initRepository(at: root)
        for readOnlyCase in ReadOnlyCase.allCases {
            try readOnlyCase.committed?.write(to: root.appendingPathComponent(readOnlyCase.fileName))
        }
        GitTestRepo.commitAll(in: root)
        for readOnlyCase in ReadOnlyCase.allCases {
            try readOnlyCase.current?.write(to: root.appendingPathComponent(readOnlyCase.fileName))
        }
        GitTestRepo.run(["add", ReadOnlyCase.staged.fileName], in: root)
        return temp
    }

    enum ReadOnlyCase: String, CaseIterable, Sendable {
        case unstaged, wholeFile, staged, clean, untracked, combiningCharacters, binary

        var fileName: String {
            switch self {
            case .unstaged: "unstaged.swift"
            case .wholeFile: "whole.swift"
            case .staged: "staged.swift"
            case .clean: "clean.swift"
            case .untracked: "new.swift"
            // Issue #685 の回帰。Foundation のファイル書き込み API はファイルシステム表現を
            // 作る際に合成済み文字(NFC)を分解形(NFD)へ変換するため、実ディスク上のバイト列は
            // NFD になる(実測)。一方 `git add` に渡した文字列(NFC)はそのまま index に記録される
            // (実測: `git ls-files` は NFC のバイト列を返す)。この不一致を揃え損ねると、
            // pathspec・`git_index_get_bypath` のどちらもバイト一致せず untracked と誤判定する。
            case .combiningCharacters: "\u{305F}\u{3099}.md".precomposedStringWithCanonicalMapping // "だ.md"(NFC)
            case .binary: "b.dat"
            }
        }

        /// 1 行目だけを変更し、-U3 の文脈からは外れる 10 行目以降まで用意する。
        private static let twelveLines = (1 ... 12).map { "let v\($0) = \($0)\n" }.joined()

        /// 初期コミットに載せる内容。nil はコミットしない。
        var committed: Data? {
            switch self {
            case .unstaged, .staged, .clean: Data("let a = 1\n".utf8)
            case .wholeFile: Data(Self.twelveLines.utf8)
            case .untracked: nil
            case .combiningCharacters: Data("a\n".utf8)
            case .binary: Data([0x00, 0x01, 0x02, 0x00])
            }
        }

        /// コミット後に作業ツリーへ書く内容。nil は触らない。`staged` はこの後 add する。
        var current: Data? {
            switch self {
            case .unstaged, .staged: Data("let a = 2\n".utf8)
            case .wholeFile:
                Data(Self.twelveLines.replacingOccurrences(of: "let v1 = 1\n", with: "let v1 = 99\n").utf8)
            case .clean: nil
            case .untracked: Data("untracked".utf8)
            case .combiningCharacters: Data("b\n".utf8)
            case .binary: Data([0x00, 0x09, 0x7F, 0x00])
            }
        }

        func verify(_ result: GitFileDiff?) {
            switch self {
            case .unstaged:
                let text = diffText(result)
                #expect(text?.contains("@@") == true)
                #expect(text?.contains("-let a = 1") == true)
                #expect(text?.contains("+let a = 2") == true)
            case .wholeFile:
                // ビューアは「ファイルを読む」画面なので、変更の周辺だけを抜き出すと前後が飛んで
                // 読めなくなる。既定の -U3 では 3 行を超えて離れた行が落ちるため、全文を出す。
                let text = diffText(result)
                #expect(text?.contains(" let v12 = 12") == true)
                // 全文が 1 つのハンクに収まるので、ハンクの区切りも 1 つだけになる。
                #expect(text.map { $0.components(separatedBy: "@@ -").count - 1 } == 1)
            case .staged:
                // 比較対象を index ではなく HEAD にした理由そのもの。`git diff`(index 比較)だと
                // ステージ済みの変更が差分から消え、バッジと表示が食い違う。
                #expect(diffText(result)?.contains("+let a = 2") == true)
            case .clean:
                #expect(result == .noChanges)
            case .untracked:
                // 未追跡ファイルも diff は成功して空を返す。空かどうかで判定していると
                // 「変更なし」と誤答する(この分類が退行したらここが落ちる)。
                #expect(result == .untracked)
            case .combiningCharacters:
                #expect(diffText(result)?.contains("+b") == true, "NFC/NFD 不一致で untracked 扱いになっていないか")
            case .binary:
                #expect(result == .binary)
            }
        }

        private func diffText(_ result: GitFileDiff?) -> String? {
            guard case let .diff(text) = result else {
                Issue.record("差分が返らなかった: \(String(describing: result))")
                return nil
            }
            return text
        }
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

    /// 自己励振の防止線。差分取得が `.git/index` を書き換えると
    /// 「差分取得 → fingerprint 変化 → 監視発火 → 差分取得」の輪ができる。
    ///
    /// **内容を変えずに mtime だけ動かす**のが要点。内容ごと変えた場合、libgit2 は
    /// `GIT_DIFF_UPDATE_INDEX` を設定しても index を書かないため、このフラグを足す
    /// 退行を検知できない(TASK-435.3 の status 側で実測した同じ話)。
    @Test("差分取得は .git/index の fingerprint を変えない")
    func diffDoesNotDisturbIndexFingerprint() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.swift", contents: "same\n", in: temp.url)
        // 同じ内容で書き直して mtime だけ進める(index の stat キャッシュが古くなる)。
        try GitTestRepo.modifyWithoutStaging("a.swift", contents: "same\n", in: temp.url)
        let repository = GitRepository()
        let before = repository.indexFingerprint(at: temp.url)

        _ = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)
        _ = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)

        #expect(repository.indexFingerprint(at: temp.url) == before)
    }

    /// AC #2 の担保。viewer.js の `parseUnifiedDiff` は無改修で動くことが要件だが、
    /// それを直接測る手段が無いため、**守りたいもの(git と同じ unified diff テキスト)**を
    /// 実 git の出力との一致で測る。
    ///
    /// 比較相手は外部 git 方式が実際に使っていた引数そのもの
    /// (`--no-color --no-ext-diff -U1000000 <base> -- <path>`)。
    @Test("実 git の -U1000000 出力と一致する")
    func matchesRealGitUnifiedDiffOutput() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        let original = (1 ... 30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try GitTestRepo.commitFile(named: "a.swift", contents: original, in: temp.url)
        // 先頭・中間・末尾を変え、追加と削除の両方を含む差分にする。
        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines[0] = "changed first"
        lines[15] = "changed middle"
        lines.remove(at: 20)
        lines.insert("inserted", at: 25)
        try GitTestRepo.modifyWithoutStaging(
            "a.swift", contents: lines.joined(separator: "\n"), in: temp.url
        )

        let result = makeReader().diff(forFileAt: temp.url.appendingPathComponent("a.swift"), in: temp.url)
        guard case let .diff(text) = result else {
            Issue.record("差分が返らなかった: \(String(describing: result))")
            return
        }
        // 起点は libgit2 実装と同じものを使う(ここがずれると比較そのものが無意味になる)。
        let base = GitComparisonBaseResolver().comparisonBase(forRepositoryAt: temp.url) ?? "HEAD"
        let expected = try #require(realGitDiff(base: base, path: "a.swift", in: temp.url))

        #expect(text == expected)
    }

    /// 実 git を直接起動して unified diff を採る(テストの比較相手専用)。
    private func realGitDiff(base: String, path: String, in dir: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", dir.path, "--no-pager", "diff", "--no-color", "--no-ext-diff",
            "-U\(GitDiffReader.wholeFileContextLines)", base, "--", path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // fixture と同じくグローバル設定を切る。`diff.noprefix` などで出力の形が変わると
        // libgit2 の出力と一致しなくなる。
        process.environment = GitTestRepo.environment
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    @Test("上限を超える差分は tooLarge")
    func reportsTooLargeDiff() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "big.txt", contents: "seed\n", in: temp.url)
        // 上限は注入して小さくする。本番の 1MB を超えさせるには約 2MB を書いて libgit2 に
        // diff させることになり、それだけで数百 ms かかっていた(TASK-662.6)。
        let limit = 4096
        let huge = String(repeating: "0123456789abcdef\n", count: limit / 8)
        try GitTestRepo.modifyWithoutStaging("big.txt", contents: huge, in: temp.url)

        let result = GitDiffReader(byteLimit: limit)
            .diff(forFileAt: temp.url.appendingPathComponent("big.txt"), in: temp.url)

        guard case let .tooLarge(byteCount) = result else {
            Issue.record("tooLarge が返らなかった: \(String(describing: result))")
            return
        }
        #expect(byteCount > limit)
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
        GitDiffReader()
    }

    private func makeStatusReader() -> GitStatusReader {
        GitStatusReader()
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

/// バイナリ判定の Integration テスト。
///
/// 判定は git の固定英文(`Binary files … differ`)の行頭一致ではなく、libgit2 が
/// delta に付ける `GIT_DIFF_FLAG_BINARY` で行う。文字列一致に戻すとここが落ちる。
struct GitDiffBinaryDetectionIntegrationTests {
    @Test("NUL を含むファイルの差分は binary")
    func detectsBinaryFile() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "seed.txt", in: temp.url)
        let binary = temp.url.appendingPathComponent("b.dat")
        try Data([0x00, 0x01, 0x02, 0x00, 0xFF]).write(to: binary)
        GitTestRepo.run(["add", "b.dat"], in: temp.url)

        #expect(GitDiffReader().diff(forFileAt: binary, in: temp.url) == .binary)
    }

    /// `Binary files … differ` という文字列を**本文に含む**テキストファイルを
    /// バイナリと誤判定しないこと。行頭一致による判定へ戻すとここが落ちる
    /// (同じ形の誤検知が unified diff のハンク判定で実際に起きている: TASK-316)。
    @Test("本文に Binary files という行を含むテキストファイルは binary にしない")
    func doesNotMisclassifyTextContainingMarker() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        GitTestRepo.initRepository(at: temp.url)
        try GitTestRepo.commitFile(named: "a.txt", contents: "old\n", in: temp.url)
        // 差分の追加行が `Binary files a/x and b/x differ` そのものになる。
        try GitTestRepo.modifyWithoutStaging(
            "a.txt", contents: "Binary files a/x and b/x differ\n", in: temp.url
        )

        let result = GitDiffReader().diff(forFileAt: temp.url.appendingPathComponent("a.txt"), in: temp.url)

        guard case let .diff(text) = result else {
            Issue.record("テキスト差分が返らなかった: \(String(describing: result))")
            return
        }
        #expect(text.contains("+Binary files a/x and b/x differ"))
    }
}
