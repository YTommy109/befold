import Foundation

/// 実 git を叩く Integration テスト向けの共通ヘルパー。`GitRepositoryIntegrationTests` /
/// `GitCommandRunnerIntegrationTests` の双方で「リポジトリを作る」実装が別々に育たないよう、
/// ここへ単一情報源化する。プロダクトコードの `GitCommandRunner` が前置する無害化オプションを
/// あえて経由しない生の git 実行のため、対照実験(無害化なしでは再現する挙動)にも使える。
public enum GitTestRepo {
    /// 無害化オプションを通さず git を実行する。テストのセットアップ用途のため、
    /// 失敗は無視して呼び出し側の後続アサーションに委ねる。
    public static func run(_ args: [String], in dir: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", dir.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
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
}
