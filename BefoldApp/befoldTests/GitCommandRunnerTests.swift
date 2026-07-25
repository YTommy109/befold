@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// `GitCommandRunner` が全 git 呼び出しへ無害化オプションを前置することを固定する。
/// 開いた文書のリポジトリ設定(`core.fsmonitor`)による任意コマンド実行を防ぐ要のため、
/// 将来のリファクタで静かに落ちないよう引数構築と実挙動の両方で押さえる。
struct GitCommandRunnerTests {
    /// 実 git を叩くテスト用のランナー。git 1 回あたりの予算は他のポーリング待機と同じ
    /// 単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。少コアの CI で数百テストを
    /// 並行実行すると git の起動自体が遅れうるため、本番既定の 10 秒に縛らない。
    private func makeRunner() -> GitCommandRunner {
        GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10))
    }

    @Test("git 呼び出しには常に core.fsmonitor 無効化が前置される")
    func alwaysPrependsFsmonitorHardening() {
        let args = GitCommandRunner.processArguments(for: ["ls-files", "-z"])

        // サブコマンドより前に置かないと git が解釈しないため、位置まで固定する。
        #expect(args == [
            "--no-pager", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null", "ls-files", "-z",
        ])
    }

    @Test("引数無しの呼び出しでも無害化オプションは落ちない")
    func hardeningSurvivesEmptyArguments() {
        // hardeningOptions を参照して組み立てると恒真になるため、期待値は直値で書く。
        #expect(GitCommandRunner.processArguments(for: [])
            == ["--no-pager", "-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null"])
    }

    /// `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_*` のような GIT_* 変数はコマンドラインの `-c` を
    /// 上書きしうるため、継承すると無害化オプションを素通しされる。環境を丸ごと差し替えて
    /// いること(`ProcessInfo.processInfo.environment` から作り直していないこと)を固定する。
    @Test("git へ渡す環境は固定で、呼び出し元の GIT_* を引き継がない")
    func processEnvironmentDropsInheritedGitVariables() {
        // 値 0 は「追加設定なし」の宣言で、並行実行中の他テストの git を壊さない。
        setenv("GIT_CONFIG_COUNT", "0", 1)
        defer { unsetenv("GIT_CONFIG_COUNT") }

        let environment = GitCommandRunner.processEnvironment()

        #expect(environment["GIT_CONFIG_COUNT"] == nil, "呼び出し元の GIT_* を引き継いでいる")
        #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
    }

    @Test("core.fsmonitor を仕込んだリポジトリでもコマンドが実行されない")
    func doesNotExecuteRepositoryFsmonitorCommand() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let marker = temp.url.appendingPathComponent("marker")
        try makeRepoWithFsmonitor(temp.url, marker: marker)

        // 対照: 無害化しない生の git では実際に実行されることを確かめる。ここが再現しない
        // 環境(fsmonitor 未対応の git など)ではこのテストは検証力を持たないため、
        // 引数構築テスト(alwaysPrependsFsmonitorHardening)側の固定に委ねて抜ける。
        rawGit(temp.url, ["ls-files", "-z"])
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.removeItem(at: marker)

        _ = makeRunner().run(["ls-files", "-z"], in: temp.url)

        #expect(FileManager.default.fileExists(atPath: marker.path) == false)
    }

    /// 索引はロックを保持したまま git を待つため、git が返らないと他ウィンドウの
    /// パス解決まで巻き添えで止まる。タイムアウトで必ず打ち切ることを固定する。
    @Test("返ってこない git はタイムアウトで打ち切られる", .timeLimit(.minutes(1)))
    func abortsHangingGit() {
        let started = Date()
        // シェルエイリアス経由で 30 秒眠る git を作る(git 自体が返ってこない状況の再現)。
        // git を殺しても孫プロセスが標準出力を握ったままになりうる形なので、
        // 「pipe が閉じるのを待つ」だけの実装ではここで止まる。
        let result = GitCommandRunner(timeout: 0.5).run(["-c", "alias.zzz=!sleep 30", "zzz"])
        let elapsed = Date().timeIntervalSince(started)

        // 打ち切りは「git が動いて出した答え」ではないため unavailable(キャッシュ不可)。
        #expect(result == .unavailable)
        #expect(elapsed < 10, "タイムアウトが効かず \(elapsed) 秒待っている")
    }

    /// 打ち切りは呼び出し元を解放するだけで、読み取り中の fd に触ってはならない。
    /// 読み取りは別スレッドで走るため、打ち切り側から読み取り端を閉じると
    /// (a) まだ read に入っていなければ EBADF で `NSFileHandleOperationException` が飛び、
    /// 誰も catch できないのでアプリごと落ちる。(b) 閉じた番号が別ファイルに再利用されると
    /// 無関係な読み取りを壊す。CI では実際に SIGABRT でテストプロセスが落ちた。
    @Test("打ち切り後に読み取りスレッドが動いてもクラッシュしない", .timeLimit(.minutes(1)))
    func survivesTimeoutBeforeReadStarts() {
        // 読み取りスレッドが起動する前に打ち切りへ入りやすいよう予算 0 で回す。
        // どちらが先着するかは競争なので 1 回ごとの結果は固定できない(読み取りが
        // 間に合えば出力が返る)。ここで確かめたいのは打ち切り経路を通ってもプロセスが
        // 生きていることそのもので、落ちれば実行全体が落ちて検知される。
        var timedOutCount = 0
        for _ in 0 ..< 20 where GitCommandRunner(timeout: 0).run(["--version"]) == .unavailable {
            timedOutCount += 1
        }

        // 20 回とも読み取りが先着すると打ち切り経路を一度も通らず、このテストは
        // 無検証でグリーンになる。予算 0 では起動〜EOF〜reap が同一瞬間に終わらない限り
        // 必ず打ち切られるため、1 回以上を要求してもフレークしない。
        #expect(timedOutCount >= 1)

        // 打ち切り後も後続の git 実行が壊れていないこと(fd を壊していないこと)を確かめる。
        #expect(GitCommandRunner().run(["--version"]) != .unavailable)
    }

    /// 読み取りを `DispatchQueue.global` に投げていると、共有ワーカープールが他所の
    /// ブロッキング処理で埋まっているときに読み取り自体が起動できず、git が正常終了
    /// していても毎回タイムアウトして `.unavailable` になる(CI で実際に発生した)。
    /// 予算を延ばしても直らないため、共有プールに依存しないことをここで固定する。
    ///
    /// 検証のためプールを一時的に埋める。この飽和は QoS を問わずプロセス全体の
    /// `DispatchQueue.global` を止めるため、窓は可能な限り短く保つ:
    /// 固定 sleep ではなく起動ハンドシェイクで飽和の成立を検出し、git 実行を挟んだら
    /// defer で必ず解放する。ハンドシェイクは検証力の担保も兼ねる。固定 sleep では
    /// 負荷の高い CI で 1 本も掴めていなくても素通りし、無検証でグリーンになりうる。
    @Test("共有ワーカープールが埋まっていても git の結果を取りこぼさない", testTimeLimit())
    func readsOutputWhileGlobalQueueIsSaturated() {
        // 非 overcommit プールの上限(`kern.wq_max_constrained_threads`、実測 64)より
        // 多めに投げる。他のテストが既に何本か握っていても飽和が成立する。
        // 上限を超えた分は起動できないまま滞留するので、全部の起動は待てない。
        let blockerCount = 80
        let blocker = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        defer {
            // 起動できなかったブロックも、ワーカーが空き次第起動して 1 つ消費する。
            // 投げた数だけ signal しておけば全部が確実に抜ける。
            for _ in 0 ..< blockerCount {
                blocker.signal()
            }
        }
        for _ in 0 ..< blockerCount {
            DispatchQueue.global(qos: .utility).async {
                started.signal()
                blocker.wait()
            }
        }

        // 新しい起動が止まった時点が飽和の成立。何本目で止まるかは他テストの占有状況に
        // 依存するので数は固定できないが、「もう起動できない」こと自体が飽和の定義なので
        // 検証力は本数に依らない。
        var startedCount = 0
        while startedCount < blockerCount, started.wait(timeout: .now() + 0.2) == .success {
            startedCount += 1
        }
        // 1 本も掴めていなければ飽和させられておらず、この後の判定は無意味になる。
        #expect(startedCount > 0)

        #expect(makeRunner().run(["--version"]) != .unavailable)
    }

    /// 無害化オプションを通さずに git を実行する(対照用)。
    private func rawGit(_ dir: URL, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// marker を作るだけのフックを `core.fsmonitor` に仕込んだリポジトリを作る
    /// (`.git/` 込みのアーカイブを展開して開いた状況の再現)。
    private func makeRepoWithFsmonitor(_ dir: URL, marker: URL) throws {
        rawGit(dir, ["init"])
        rawGit(dir, ["config", "user.email", "t@example.com"])
        rawGit(dir, ["config", "user.name", "t"])
        try "print(1)".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        rawGit(dir, ["add", "main.swift"])
        rawGit(dir, ["commit", "-m", "init"])

        let hook = dir.appendingPathComponent("fsmonitor-hook.sh")
        // exit 1 で git にフック未対応を伝え、監視結果の解釈まで進ませない。
        try "#!/bin/sh\ntouch \"\(marker.path)\"\nexit 1\n"
            .write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        rawGit(dir, ["config", "core.fsmonitor", hook.path])
    }
}
