import Foundation

/// 実 git を叩く Integration テスト向けの共通ヘルパー。`GitRepositoryIntegrationTests` /
/// `GitCommandRunnerTests`(GitCommandRunner を実行するテスト群)の双方で「リポジトリを作る」
/// 実装が別々に育たないよう、ここへ単一情報源化する。プロダクトコードの `GitCommandRunner` が
/// 前置する無害化オプションをあえて経由しない生の git 実行のため、対照実験
/// (無害化なしでは再現する挙動)にも使える。
/// `GitCommandRunnerTests` 側は TASK-244 の直列化制約(`GitCommandRunner` を実行する全テストを
/// 資源残留系の直列スイートへ寄せる)により `〜IntegrationTests.swift` へは分離していない。
public enum GitTestRepo {
    /// 無害化オプションを通さず git を実行する。テストのセットアップ用途のため、
    /// 失敗は無視して呼び出し側の後続アサーションに委ねる。
    ///
    /// 起動できなかった `Process` へ `waitUntilExit()` を呼ぶと、Swift から捕捉できない
    /// `NSInvalidArgumentException` が飛んでテストプロセスごと落ちる。spawn 失敗は fd リーク
    /// 退行の検証中(EMFILE)にこそ起きやすく、そこでクラッシュすると呼び出し元の defer による
    /// 後始末まで飛ばしかねないため、起動できたときだけ待つ。
    public static func run(_ args: [String], in dir: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", dir.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        process.waitUntilExit()
    }

    /// dir を git リポジトリとして初期化し、コミットに必要な最低限の設定を入れる。
    public static func initRepository(
        at dir: URL, userEmail: String = "t@example.com", userName: String = "t"
    ) {
        run(["init"], in: dir)
        run(["config", "user.email", userEmail], in: dir)
        run(["config", "user.name", userName], in: dir)
    }

    /// dir にファイルを 1 つ作って追跡・コミットする(最小の初期コミット)。
    public static func commitFile(
        named name: String = "main.swift", contents: String = "print(1)", in dir: URL
    ) throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        run(["add", name], in: dir)
        run(["commit", "-m", "init"], in: dir)
    }

    /// 既存ファイルを書き換えて `git add` まで済ませる(index にのみ変更がある状態)。
    public static func stageChange(
        to name: String, contents: String = "print(2)", in dir: URL
    ) throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        run(["add", name], in: dir)
    }

    /// 既存ファイルを書き換えるだけで add はしない(worktree にのみ変更がある状態)。
    public static func modifyWithoutStaging(
        _ name: String, contents: String = "print(3)", in dir: URL
    ) throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// 追跡されていない新規ファイルを作る。
    public static func addUntrackedFile(
        named name: String, contents: String = "untracked", in dir: URL
    ) throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// 新しいブランチを作って切り替える(base からの分岐を作るため)。
    public static func createBranch(named name: String, in dir: URL) {
        run(["checkout", "-b", name], in: dir)
    }

    /// ファイルを書き換えてコミットする(ブランチ内のコミット済み変更を作る)。
    public static func commitChange(
        to name: String, contents: String, message: String = "change", in dir: URL
    ) throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        run(["add", name], in: dir)
        run(["commit", "-m", message], in: dir)
    }
}
