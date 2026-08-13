@testable import befold
import BefoldTestSupport
import Foundation
import libgit2
import Testing

/// 実 git を起動しない `GitLibrary` の unit テスト。
///
/// 開けないリポジトリのフィクスチャは `.git/` を手で組み立てる(実 git を使わない)。
/// libgit2 は `core.repositoryformatversion = 1` と未知の `extensions.*` を見た時点で
/// 失敗するため、オブジェクトもコミットも要らない。
struct GitLibraryTests {
    /// `.git/` を手で組み立てて「libgit2 が開けないリポジトリ」を作る。
    ///
    /// - Parameter extensionEntry: `[extensions]` セクションへ書く `キー = 値`。
    static func makeUnopenableRepository(in directory: URL, extensionEntry: String) throws {
        let gitDir = directory.appendingPathComponent(".git")
        for sub in ["objects", "refs/heads"] {
            try FileManager.default.createDirectory(
                at: gitDir.appendingPathComponent(sub), withIntermediateDirectories: true
            )
        }
        try "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )
        let config = """
        [core]
        \trepositoryformatversion = 1
        \tbare = false
        [extensions]
        \t\(extensionEntry)

        """
        try config.write(
            to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8
        )
    }

    // MARK: - config 検索パスの有効・無効

    /// 無効化が外れたら（あるいは無効化しすぎたら）ここが落ちる。
    ///
    /// 「偽ホームを置いて config が読まれないこと」を直接測る形にはしない。
    /// libgit2 の検索パスはプロセス全体の設定であり、テスト中に `HOME` を差し替えると
    /// 並行実行中の他テスト(`homeDirectoryForCurrentUser` を使う `DirectoryListerTests` や
    /// `TempDir(base:)` など多数)の前提を壊す。加えて `git_libgit2_init()` の中で
    /// `git_sysdir_global_init()` が全レベルの検索パスを**先読みで** guess するため、
    /// 初期化後に `HOME` / `XDG_CONFIG_HOME` を変えても観測結果は変わらない
    /// (libgit2 1.9.2 `src/libgit2/sysdir.c`)。無効化そのものを観測すれば、
    /// 外れた瞬間にも増えた瞬間にも落ちる。
    ///
    /// 個数ではなく配列そのものを比べる。個数比較だと、中身が別のレベルへ
    /// 入れ替わっても通ってしまう。
    ///
    /// C シム(`CGitShim` の検索パス set / get)の担保もここが兼ねる。
    /// bootstrap が set した結果を get で読み戻しているため、往復が壊れれば落ちる。
    /// production が set へ渡す値は `""` だけなので、専用の往復テストは要らない
    /// (書き込みを増やすと `git_sysdir__dirs` の data race になる = TASK-462)。
    @Test("bootstrap 後に無効化されている config 検索パスは system だけ")
    func disablesOnlySystemConfigSearchPath() {
        #expect(GitLibrary.disabledConfigLevels == [GIT_CONFIG_LEVEL_SYSTEM])
        #expect(GitLibrary.configSearchPath(for: GIT_CONFIG_LEVEL_SYSTEM) == "")
    }

    /// ユーザー自身の設定(`~/.gitconfig` と `~/.config/git/`)は意図して有効なままにしている。
    /// どちらかを無効化すると `core.excludesFile` によるグローバルな ignore 設定が効かなくなり、
    /// 除外したつもりのファイルが untracked として現れる。
    ///
    /// XDG は特に 2 経路が同時に潰れる。`~/.config/git/config` の `core.excludesFile` に加え、
    /// `core.excludesFile` 未設定時の既定フォールバックである `~/.config/git/ignore` も
    /// 見つからなくなる(libgit2 の `attr_cache__lookup_path` は `core.excludesfile` が
    /// 無いとき XDG の検索パスだけを見る)。TASK-467 の実害はこちらだった。
    ///
    /// 先回りで無効化リストへ足したらこのテストが落ちる。
    @Test("global と xdg の config 検索パスは無効化しない")
    func keepsUserConfigSearchPathsEnabled() throws {
        #expect(!GitLibrary.disabledConfigLevels.contains(GIT_CONFIG_LEVEL_GLOBAL))
        #expect(!GitLibrary.disabledConfigLevels.contains(GIT_CONFIG_LEVEL_XDG))

        let home = try #require(ProcessInfo.processInfo.environment["HOME"])
        #expect(GitLibrary.configSearchPath(for: GIT_CONFIG_LEVEL_GLOBAL) == home)

        // XDG の既定は `$XDG_CONFIG_HOME/git`、未設定なら `~/.config/git`
        // (libgit2 `git_sysdir_guess_xdg_dirs`)。空でないことに加え、既定と
        // 一致することまで見る(空でない別の値へ差し替えられても落ちるように)。
        let xdgBase = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        #expect(GitLibrary.configSearchPath(for: GIT_CONFIG_LEVEL_XDG) == "\(xdgBase)/git")
    }

    /// 無効化しすぎていないことの担保。リポジトリ内の config は引き続き読めなければならない。
    @Test("リポジトリ内の config は無効化の対象外で読める")
    func repositoryLocalConfigStaysReadable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try Self.makeReadableRepository(
            in: tmp.url, section: "befold", entry: "probe = local-value"
        )

        let value = GitLibrary.withRepository(at: tmp.url) { repository -> String? in
            var config: OpaquePointer?
            guard git_repository_config(&config, repository) == 0, let config else { return nil }
            defer { git_config_free(config) }
            var buf = git_buf()
            defer { git_buf_dispose(&buf) }
            guard git_config_get_string_buf(&buf, config, "befold.probe") == 0 else { return nil }
            return buf.ptr.map { String(cString: $0) }
        }
        #expect(value == .success("local-value"))
    }

    // MARK: - 検索パスの書き手を 1 箇所に閉じる

    /// libgit2 の config 検索パスはプロセスグローバル(`git_sysdir__dirs`)で、libgit2 は
    /// この書き込みをロックで守らない。書き手が `GitLibrary.bootstrap` の一度きり初期化
    /// だけなら、以降の読み手はすべて swift_once の happens-before の後ろに並んで競合しない。
    /// 初期化後に書く箇所が 1 つでも増えると、並行実行中の別テストがリポジトリを開く際の
    /// 読み取りと競合する(TASK-462: シムの往復テストが PROGRAMDATA レベルを書き換え、
    /// thread-sanitizer が 5 本連続で data race を報告した。`git_repository_open_ext` は
    /// macOS でも PROGRAMDATA を読むため「読まれないレベルを選ぶ」では並行安全にならない)。
    ///
    /// doc コメントでは守られないので、書き手が増えたらここが落ちるようにしておく。
    ///
    /// 探す識別子は連結で組み立てる。ソース中へ直に書くと、この検査自体が「書き手」として
    /// 引っかかり、自分のファイルを除外する穴を開ける羽目になる(そうするとテストファイルに
    /// 書き手が増えても落ちなくなる。今回の違反元がテストだったので、そこを外すと意味が無い)。
    @Test("config 検索パスを書くのは GitLibrary だけ")
    func searchPathIsWrittenOnlyByGitLibrary() throws {
        let needle = "befold_git_opts_set" + "_search_path"
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let walker = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        )
        var writers: [String] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            guard !file.path.contains("/.build/") else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(needle) else { continue }
            writers.append(file.lastPathComponent)
        }
        #expect(writers == ["GitLibrary.swift"])
    }

    // MARK: - AC #9 / #10: 開けないリポジトリの写像

    @Test("未知の extensions を持つリポジトリは使用不可へ写る")
    func unknownExtensionMapsToUnusable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try Self.makeUnopenableRepository(in: tmp.url, extensionEntry: "befoldUnknown = yes")

        let outcome = GitLibrary.withRepository(at: tmp.url) { _ in true }
        #expect(outcome == .failure(.unusable))
    }

    @Test("partial clone のリポジトリは使用不可へ写る")
    func partialCloneMapsToUnusable() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try Self.makeUnopenableRepository(in: tmp.url, extensionEntry: "partialClone = origin")

        let outcome = GitLibrary.withRepository(at: tmp.url) { _ in true }
        #expect(outcome == .failure(.unusable))
    }

    /// 管理外(確定)と使用不可(不明)は呼び出し側でキャッシュ可否が分かれるため、
    /// 同じ失敗へ畳んではならない。
    @Test("git 管理外のディレクトリは管理外へ写り、使用不可とは区別される")
    func plainDirectoryMapsToNotARepository() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let outcome = GitLibrary.withRepository(at: tmp.url) { _ in true }
        #expect(outcome == .failure(.notARepository))
    }

    /// 開けないリポジトリを続けて開いてもプロセスが落ちないこと(AC #9 の「クラッシュしない」)。
    @Test("開けないリポジトリを繰り返し開いてもクラッシュしない")
    func repeatedOpenOfUnopenableRepositoryIsSafe() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try Self.makeUnopenableRepository(in: tmp.url, extensionEntry: "befoldUnknown = yes")

        for _ in 0 ..< 20 {
            #expect(GitLibrary.withRepository(at: tmp.url) { _ in true } == .failure(.unusable))
        }
    }

    // MARK: - フィクスチャ

    /// libgit2 が開ける最小のリポジトリを実 git 抜きで組み立てる。
    static func makeReadableRepository(
        in directory: URL, section: String, entry: String
    ) throws {
        let gitDir = directory.appendingPathComponent(".git")
        for sub in ["objects/info", "objects/pack", "refs/heads", "refs/tags"] {
            try FileManager.default.createDirectory(
                at: gitDir.appendingPathComponent(sub), withIntermediateDirectories: true
            )
        }
        try "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )
        let config = """
        [core]
        \trepositoryformatversion = 0
        \tbare = false
        [\(section)]
        \t\(entry)

        """
        try config.write(
            to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8
        )
    }
}
