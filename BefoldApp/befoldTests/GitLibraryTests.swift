@testable import befold
import BefoldTestSupport
import CGitShim
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

    // MARK: - AC #7: グローバル config の無効化

    /// 無効化が外れたらここが落ちる。
    ///
    /// 「偽ホームを置いて `~/.gitconfig` が読まれないこと」を直接測る形にはしない。
    /// libgit2 の検索パスはプロセス全体の設定であり、テスト中に `HOME` を差し替えると
    /// 並行実行中の他テスト(`homeDirectoryForCurrentUser` を使う `DirectoryListerTests` や
    /// `TempDir(base:)` など多数)の前提を壊す。無効化そのものを観測すれば、外れた瞬間に落ちる。
    @Test("bootstrap 後は system/xdg/global の config 検索パスが無効化されている")
    func disablesGlobalConfigSearchPaths() {
        for level in GitLibrary.disabledConfigLevels {
            #expect(GitLibrary.configSearchPath(for: level) == "", "level=\(level.rawValue)")
        }
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

    // MARK: - C シムの往復

    /// `git_libgit2_opts` は C 可変長引数のため Swift から直接呼べない。シム越しに
    /// 設定と取得が往復することを確かめる。macOS では読まれない PROGRAMDATA レベルを使い、
    /// 他テストが依存するレベルへ触れないようにする。
    @Test("C シム経由で config 検索パスを設定・取得できる")
    func configSearchPathRoundTripsThroughShim() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        GitLibrary.ensureInitialized()
        let level = GIT_CONFIG_LEVEL_PROGRAMDATA.rawValue
        defer { _ = befold_git_opts_set_search_path(level, "") }

        #expect(befold_git_opts_set_search_path(level, tmp.url.path) == 0)
        #expect(GitLibrary.configSearchPath(for: GIT_CONFIG_LEVEL_PROGRAMDATA) == tmp.url.path)
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
