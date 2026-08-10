import Foundation

/// 実 git を叩く Integration テスト向けの共通ヘルパー。git 連携そのものは libgit2 実装に
/// 移ったが(TASK-435)、**検証用のリポジトリを作る**手段としては実 git が要る。
/// libgit2 の実装が実 git の生成物を正しく読めるかを確かめるのが目的であり、
/// フィクスチャ側まで libgit2 で作ると同じ実装で書いて同じ実装で読むことになる。
///
/// 「リポジトリを作る」実装が各テストで別々に育たないよう、ここへ単一情報源化する。
public enum GitTestRepo {
    /// git を実行する。テストのセットアップ用途のため、失敗は無視して
    /// 呼び出し側の後続アサーションに委ねる。
    ///
    /// 起動できなかった `Process` へ `waitUntilExit()` を呼ぶと、Swift から捕捉できない
    /// `NSInvalidArgumentException` が飛んでテストプロセスごと落ちる。そこでクラッシュすると
    /// 呼び出し元の defer による後始末まで飛ばしかねないため、起動できたときだけ待つ。
    ///
    /// 待ちには上限を付ける。`waitUntilExit()` は呼び出したスレッドを塞ぎ、Swift Testing の
    /// テストは協調スレッドプール上で動くため、git が 1 つハングするとプール幅(コア数)ぶんで
    /// テストプロセス全体が止まりうる(TASK-424 で `DispatchSemaphore.wait()` が
    /// 少コアの CI を実際に停止させたのと同じ形)。猶予を過ぎたら終了させてから待つ。
    public static func run(_ args: [String], in dir: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", dir.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + testTimeoutSeconds(fallback: 30), execute: watchdog
        )
        process.waitUntilExit()
        watchdog.cancel()
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
