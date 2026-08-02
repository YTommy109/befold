@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 資源残留テストのポーリング予算(秒)。`.timeLimit` と `waitUntil` の双方をここから導く。
/// 両者を独立に書くとドリフトし、「予算を延ばしたのに打ち切られる」「宣言した予算が
/// 内側の待機へ伝わらない」の両方が起きる(`Waiting.swift` の doc 参照)。
private let leakPollingBudget: Double = 30

/// 返ってこない git に与える予算(秒)。
///
/// 短くしすぎると git がエイリアスのシェルを fork する前に打ち切られ、残留させたい子孫が
/// そもそも生まれない(0.2 秒では実際にそうなった)。逆に長くすると素の待ち時間になる。
/// 2 秒は、fork が済んだことをポーリング(50ms 間隔)で確かめる窓としても充分に広い。
/// git は別プロセスなのでサニタイザによる減速の影響を受けず、CI 予算に連動させる必要はない。
private let hangingBudget: TimeInterval = 2

/// 打ち切りを試みてから読み取りスレッドが EOF を諦めるまでの猶予に注入する短縮値(秒)。
///
/// `releasesResourcesWhenWriteEndSurvivesTermination` は「猶予切れで確実に資源が返る」こと
/// 自体を検証するため、猶予の満了を待つことが検証の一部であり待ち時間を省略できない。
/// 本番既定の 5 秒のままだと構造的に遅いテストになるため、猶予の長さに依存しない同じ
/// 不変条件(猶予切れで fd・スレッドが返る)を短い猶予でも検証する。
private let shortTerminationGrace: TimeInterval = 0.5

/// 実 git を叩くテスト用のランナー。git 1 回あたりの予算は他のポーリング待機と同じ
/// 単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。少コアの CI で数百テストを
/// 並行実行すると git の起動自体が遅れうるため、本番既定の 10 秒に縛らない。
///
/// `GitCommandRunnerTests` / `GitCommandRunnerResourceLeakTests` の両スイートから使うため
/// ファイルスコープの関数として単一情報源にする(スイートごとの複製を避ける)。
private func makeRunner() -> GitCommandRunner {
    GitCommandRunner(timeout: testTimeoutSeconds(fallback: 10))
}

/// 返ってこない git を専用スレッドで `count` 本走らせ、結果を貯める箱を返す。
/// 呼び出し元は打ち切りが起きるまでの間に、消すべき子孫の実在を確かめられる。
///
/// 専用スレッドを使うのは、返ってこない git を待つブロッキング呼び出しで
/// 共有ワーカープールや Swift Concurrency のスレッドを塞がないため。
private func runInBackground(
    _ runner: GitCommandRunner, _ sleeper: URL, in directory: URL, count: Int = 1
) -> LockedBox<[GitCommandOutcome]> {
    let results = LockedBox<[GitCommandOutcome]>([])
    let arguments = hangingAliasArguments(sleeper)
    for _ in 0 ..< count {
        Thread {
            let outcome = runner.run(arguments, in: directory)
            results.update { $0.append(outcome) }
        }.start()
    }
    return results
}

/// 返ってこない git に、`Process` からは直接殺せない子孫が標準出力を握る形で再現する引数列。
private func hangingAliasArguments(_ sleeper: URL) -> [String] {
    ["-c", "alias.zzz=!\(sleeper.path)", "zzz"]
}

/// git リポジトリを作り、その中に「標準出力を握ったまま眠り続けるスクリプト」を置いて返す。
/// `!` 付きエイリアスはリポジトリの外では動かないため `git init` まで含めて 1 つの仕掛けとする。
/// スクリプトのパスは一時ディレクトリ名で一意なので `pgrep -f` で追える。
///
/// `trap '' TERM` が再現の要。`!` 付きエイリアスで git は自分の子としてこのシェルを
/// fork し、その完了を待つ。子が素直に SIGTERM で死ぬ形だと git が子を道連れに畳んで
/// くれるため、`process.terminate()` だけでパイプが閉じてしまい残留を再現できない。
/// SIG_IGN は fork/exec を越えて継承されるので、先頭で一度伏せればサブシェルにも効く。
/// こうすると git 自身も子を待ったまま SIGTERM で死ねなくなり、git・シェル・サブシェルの
/// 三者が標準出力を握ったまま残る = 打ち切ってもパイプが閉じない、解消したい残留の形になる。
/// 無視できない SIGKILL をプロセスグループへ送る実装だけがここを抜けられる。
///
/// 末尾を素朴に `sleep 300` と書かないのは、シェルが最後のコマンドを `exec` 最適化して
/// 単一プロセスに潰し、`pgrep` から追えなくなるため。
///
/// - Parameter escapesProcessGroup: 眠る側を `setsid` で自前のセッションへ抜けさせる。
///   git のプロセスグループへ SIGKILL を送っても届かなくなるので、「書き込み端を握る
///   プロセスを殺し切れない」状況(自分を daemon 化するフックなど)の再現に使う。
///   `setsid(1)` は macOS に無いため、常にある perl から `POSIX::setsid` を呼ぶ。
private func makeHangingRepo(in dir: URL, escapesProcessGroup: Bool = false) throws -> URL {
    GitTestRepo.run(["init"], in: dir)
    let sleepForever = escapesProcessGroup
        // 末尾の "$0"(スクリプト自身のパス)は perl からは使わない。argv に混ぜて
        // `pgrep -f` の対象に含めるためのマーカー。
        ? "/usr/bin/perl -e 'use POSIX; POSIX::setsid(); sleep 1 while 1;' \"$0\" &"
        : "while true; do sleep 1; done &"
    let script = dir.appendingPathComponent("befold-sleeper.sh")
    try "#!/bin/sh\ntrap '' TERM\n\(sleepForever)\nwait\n"
        .write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

/// 残ってしまった sleeper を SIGKILL で始末する。実装が壊れているとテストは失敗するが、
/// SIGTERM を伏せた無限ループがマシンに残り続けるのは別問題なので、後始末は必ず行う。
private func killSleepers(matching pattern: String) {
    _ = runTool("/usr/bin/pkill", ["-9", "-f", pattern])
}

/// argv に `pattern` を含むプロセスが存在するか。
/// spawn できなかった場合は「存在しない」と嘘をつかないよう nil を返す。
private func processExists(matching pattern: String) -> Bool? {
    runTool("/usr/bin/pgrep", ["-f", pattern]).map { $0 == 0 }
}

/// このプロセスが開いている pipe の fd 数。
///
/// fd を全部数えると、並行実行中の他スイートが開くファイルやソケットが基準線に混ざる。
/// 残したくないのは打ち切った git の `Pipe` なので、種別を pipe に絞って数える。
private func openPipeCount() -> Int {
    var count = 0
    for descriptor in 0 ..< getdtablesize() {
        var status = stat()
        if fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFIFO {
            count += 1
        }
    }
    return count
}

/// `GitCommandRunner` の読み取りスレッドの本数。
///
/// 全スレッドを数えると GCD のワーカー本数の増減が基準線に乗ってしまうため、
/// ランナーが付けた名前で絞る。名前が変わればここも合わせて直す必要がある。
private func readerThreadCount() -> Int {
    var threads: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS,
          let threads
    else { return 0 }
    // task_threads は各スレッドへの送信権と配列そのものを呼び出し側へ渡すので、
    // 数えるだけでも両方返さないとポート枯渇とリークを起こす。
    defer {
        for index in 0 ..< Int(count) {
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: UnsafeRawPointer(threads))),
            vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
        )
    }
    return (0 ..< Int(count)).count { threadName(threads[$0]) == "GitCommandRunner.read" }
}

/// スレッドに付けられた名前(付いていなければ空文字)。
private func threadName(_ thread: thread_t) -> String {
    var info = thread_extended_info_data_t()
    var infoCount = mach_msg_type_number_t(
        MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
            thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &infoCount)
        }
    }
    guard result == KERN_SUCCESS else { return "" }
    return withUnsafePointer(to: info.pth_name) { pointer in
        pointer.withMemoryRebound(
            to: CChar.self, capacity: MemoryLayout.size(ofValue: info.pth_name)
        ) { String(cString: $0) }
    }
}

/// 補助ツールを同期実行して終了コードを返す。spawn に失敗したら `Issue` として記録し nil を返す。
///
/// 起動できなかった `Process` へ `waitUntilExit()` / `terminationStatus` を呼ぶと、Swift から
/// 捕捉できない `NSInvalidArgumentException` が飛んでテストプロセスごと落ちる。spawn 失敗は
/// fd リーク退行の検証中(EMFILE)にこそ起きやすく、そこでクラッシュすると defer の後始末まで
/// 飛ばして SIGTERM を伏せた sleeper を CI マシンに残す。起動できたときだけ待つ。
private func runTool(
    _ executable: String,
    _ arguments: [String],
    in directory: URL? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) -> Int32? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        Issue.record("\(executable) を起動できなかった: \(error)", sourceLocation: sourceLocation)
        return nil
    }
    process.waitUntilExit()
    return process.terminationStatus
}

/// marker を作るだけのフックを `core.fsmonitor` に仕込んだリポジトリを作る
/// (`.git/` 込みのアーカイブを展開して開いた状況の再現)。
private func makeRepoWithFsmonitor(_ dir: URL, marker: URL) throws {
    GitTestRepo.initRepository(at: dir)
    try GitTestRepo.commitFile(in: dir)

    let hook = dir.appendingPathComponent("fsmonitor-hook.sh")
    // exit 1 で git にフック未対応を伝え、監視結果の解釈まで進ませない。
    try "#!/bin/sh\ntouch \"\(marker.path)\"\nexit 1\n"
        .write(to: hook, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    GitTestRepo.run(["config", "core.fsmonitor", hook.path], in: dir)
}

/// `GitCommandRunner` が全 git 呼び出しへ無害化オプションを前置することを固定する。
/// 開いた文書のリポジトリ設定(`core.fsmonitor`)による任意コマンド実行を防ぐ要のため、
/// 将来のリファクタで静かに落ちないよう引数構築と実挙動の両方で押さえる。
///
/// プロセス全体の基準線(`openPipeCount` / `readerThreadCount`)を読む資源残留系テストは
/// [`GitCommandRunnerResourceLeakTests`] に分離してあるため、ここは並列実行できる
/// (各テストが自己完結で、他テストの計測に影響する共有状態を持たない)。
///
/// `GitCommandRunner` を実行するテスト(`.run()` を呼ぶもの)はここへ置かない。並列実行中に
/// pipe / リーダースレッドを一時的に生成すると、`GitCommandRunnerResourceLeakTests` 側が
/// 開始時点で 1 回だけ読む基準線を水増しし、検証力を落とす(`GitCommandRunnerResourceLeakTests`
/// の型コメント参照)。`GitCommandRunner` を実行するテストは全て `GitCommandRunnerResourceLeakTests`
/// へ置くこと。
struct GitCommandRunnerTests {
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
}

/// プロセス全体の基準線(`openPipeCount` / `readerThreadCount`)を読む資源残留系テストの
/// 直列化専用スイート。同じスイートには共有ワーカープールを 64 本埋めるテストや、
/// 打ち切った git のリーダースレッドを猶予いっぱい保持するテストがあり、並列に走ると
/// 残留の基準線がそれらのノイズで揺れる。数え方を対象限定にした上で
/// (`openPipeCount` / `readerThreadCount`)、同居ノイズも直列化で断つ。
///
/// `openPipeCount` / `readerThreadCount` を直接読むテストだけでなく、`GitCommandRunner` を
/// 1 回でも実行するテストは全てここに置く。理由は基準線側の性質にある:
/// `repeatedTimeoutsDoNotAccumulateResources` / `releasesResourcesWhenWriteEndSurvivesTermination`
/// は開始時点の pipe / リーダースレッド数を 1 回だけサンプリングして基準線とするため、その瞬間に
/// 別テストが `GitCommandRunner` を動かして pipe やリーダースレッドを一時的に生成していると
/// 基準線が水増しされ、閾値判定が緩んで検証力を失う(落ちる方向ではなく通ってしまう方向の
/// 劣化なので気づきにくい)。これは並列スイート側の見かけの実行時間とは無関係な理由なので、
/// `GitCommandRunner` を全く実行しない引数構築・環境変数テストのみを `GitCommandRunnerTests`
/// (並列)側に残し、それ以外は実行時間に関わらずこちらへ寄せる。
/// (`readsOutputWhileGlobalQueueIsSaturated` は基準線を読まないが、`DispatchQueue.global` を
/// プロセス全体で飽和させる副作用があり、他 2 テストの `readerThreadCount()` 計測へノイズを
/// 乗せうるため、同じ理由でこのスイートに残す。)
///
/// `.serialized` はスイート内しか直列化しないため、`GitCommandRunnerTests` (並列実行) と
/// 同時に走ることはある。しかしその並列側は `GitCommandRunner` を一切実行しないので、
/// pipe / リーダースレッドの基準線を動かさない。基準線ノイズの吸収は他スイート由来の分として
/// 許容幅(`slack`)側に持たせたままでよく(`repeatedTimeoutsDoNotAccumulateResources` 参照)、
/// 分割前と検証力は変わらない。
@Suite(.serialized)
struct GitCommandRunnerResourceLeakTests {
    @Test("core.fsmonitor を仕込んだリポジトリでもコマンドが実行されない")
    func doesNotExecuteRepositoryFsmonitorCommand() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let marker = temp.url.appendingPathComponent("marker")
        try makeRepoWithFsmonitor(temp.url, marker: marker)

        // 対照: 無害化しない生の git では実際に実行されることを確かめる。ここが再現しない
        // 環境(fsmonitor 未対応の git など)ではこのテストは検証力を持たないため、
        // 引数構築テスト(alwaysPrependsFsmonitorHardening)側の固定に委ねて抜ける。
        GitTestRepo.run(["ls-files", "-z"], in: temp.url)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.removeItem(at: marker)

        _ = makeRunner().run(["ls-files", "-z"], in: temp.url)

        #expect(FileManager.default.fileExists(atPath: marker.path) == false)
    }

    /// 索引はロックを保持したまま git を待つため、git が返らないと他ウィンドウの
    /// パス解決まで巻き添えで止まる。タイムアウトで必ず打ち切ることを固定する。
    @Test("返ってこない git はタイムアウトで打ち切られる", testTimeLimit())
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
    @Test("打ち切り後に読み取りスレッドが動いてもクラッシュしない", testTimeLimit())
    func survivesTimeoutBeforeReadStarts() async {
        // 読み取りスレッドが起動する前に打ち切りへ入りやすいよう予算 0 で回す。
        // どちらが先着するかは競争なので 1 回ごとの結果は固定できない(読み取りが
        // 間に合えば出力が返る)。ここで確かめたいのは打ち切り経路を通ってもプロセスが
        // 生きていることそのもので、落ちれば実行全体が落ちて検知される。
        //
        // 20 回は互いに独立な試行なので `runInBackground` と同じ要領で並行に投げ、
        // ウォールクロックを 1 回ぶんへ畳む(逐次だと git --version の起動コストが
        // 20 回積み上がり 1〜2 秒かかっていた)。20 本同時 spawn は pipe / リーダースレッドの
        // バーストを生むため、このテストは直列スイート側に置き、資源残留系テストの
        // 基準線サンプリングと重ならないようにする。
        let results = LockedBox<[GitCommandOutcome]>([])
        for _ in 0 ..< 20 {
            Thread {
                let outcome = GitCommandRunner(timeout: 0).run(["--version"])
                results.update { $0.append(outcome) }
            }.start()
        }
        await waitUntil { results.get().count == 20 }
        let timedOutCount = results.get().count { $0 == .unavailable }

        // 20 回とも読み取りが先着すると打ち切り経路を一度も通らず、このテストは
        // 無検証でグリーンになる。予算 0 では起動〜EOF〜reap が同一瞬間に終わらない限り
        // 必ず打ち切られるため、1 回以上を要求してもフレークしない。並行に投げても
        // 各試行は独立したプロセス・タイマーなので、この判定条件は変わらない。
        #expect(timedOutCount >= 1)

        // 打ち切り後も後続の git 実行が壊れていないこと(fd を壊していないこと)を確かめる。
        #expect(GitCommandRunner().run(["--version"]) != .unavailable)
    }

    /// git が孫プロセスへ標準出力を渡していて、その孫が SIGTERM に応じないと、git 単体への
    /// SIGTERM では書き込み端が残ってパイプが閉じない。打ち切りがプロセスグループごと
    /// 消していることを、子孫が実際に消えることで固定する(残る実装ではここが落ちる)。
    @Test("打ち切りは標準出力を握った孫プロセスごと解放する", testTimeLimit())
    func killsGrandchildHoldingStandardOutput() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let sleeper = try makeHangingRepo(in: temp.url)
        defer { killSleepers(matching: sleeper.path) }

        let results = runInBackground(GitCommandRunner(timeout: hangingBudget), sleeper, in: temp.url)
        // 「消えたこと」だけを見ると、git が孫を fork する前に打ち切られた回でも通ってしまう。
        // 打ち切りが起きる前に、消すべき対象が実在したことを先に固定する。
        #expect(await waitUntil { processExists(matching: sleeper.path) == true })
        #expect(await waitUntil { results.get() == [GitCommandOutcome.unavailable] })

        // 打ち切りから孫の消滅までは非同期なのでポーリングで待つ。
        // 一時ディレクトリ名が一意なので、他テストの sleeper とは取り違えない。
        await waitUntil { processExists(matching: sleeper.path) == false }
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
        // 依存する。自分の投げた分が 1 本も起動しないこともある(他のテストが既に上限まで
        // 握っている場合。CI で実際に起きる)が、それは飽和がより強く成立している
        // ということなので、本数を検証条件にしてはならない。
        // 「もう起動できない」こと自体が飽和の定義で、検証力は本数に依らない。
        while started.wait(timeout: .now() + 0.2) == .success {}

        #expect(makeRunner().run(["--version"]) != .unavailable)
    }

    /// 索引の warm はファイルを開くたび・タブを切り替えるたびに走るため、打ち切り 1 回ごとに
    /// 読み取りスレッドと Pipe の fd が残ると、応答しないリポジトリでは残留が積み上がって
    /// GUI アプリの soft RLIMIT_NOFILE(典型 256)に届く。繰り返しても増え続けないことを固定する。
    @Test("打ち切りを繰り返しても fd とスレッドが残留しない", testTimeLimit(pollingBudgetFallback: leakPollingBudget))
    func repeatedTimeoutsDoNotAccumulateResources() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let sleeper = try makeHangingRepo(in: temp.url)
        defer { killSleepers(matching: sleeper.path) }
        let runner = GitCommandRunner(timeout: hangingBudget)

        // 数えるのは pipe の fd と `GitCommandRunner.read` という名前のスレッドだけなので、
        // Thread や Process の一度きりの確保はそもそも数に入らない。空打ちのウォームアップは要らない。
        let baselinePipes = openPipeCount()
        let baselineReaders = readerThreadCount()

        // 逐次に回すと 1 ラウンドぶんの予算をラウンド数だけ積むことになる。打ち切りは互いに
        // 独立なので並行に走らせ、ウォールクロックを 1 ラウンドぶんへ畳む。残留は「全部
        // 返ってきて落ち着いた後に残っているか」で見るため、並行にしても検出力は変わらない。
        let rounds = 20
        let results = runInBackground(runner, sleeper, in: temp.url, count: rounds)
        // 打ち切りの前に、残留させたい孫が実在したことを固定する(空成立の防止)。
        #expect(await waitUntil { processExists(matching: sleeper.path) == true })
        #expect(await waitUntil { results.get().count == rounds })
        #expect(results.get().allSatisfy { $0 == .unavailable })

        // 解放は読み取りスレッドが EOF に達してから起きるのでポーリングで待つ。
        // 許容幅は他スイートの git 呼び出しが一瞬だけ立てる pipe / リーダースレッドを吸収する
        // ためのもの。残留があればラウンド数(20)ぶん積み上がるので、許容幅 3 に対して
        // 検出マージンは約 6.7 倍あり、幅を狭めても検証力は落ちない。
        // 待つほど条件が満たされやすくなる形なので、一時的なノイズで落ちることもない。
        let slack = 3
        let budget = testTimeout(fallback: leakPollingBudget)
        await waitUntil(timeout: budget) { openPipeCount() <= baselinePipes + slack }
        await waitUntil(timeout: budget) { readerThreadCount() <= baselineReaders + slack }
    }

    /// 書き込み端を握るプロセスを殺し切れない場合(孫が自前のセッションへ抜けていて、git の
    /// プロセスグループへの SIGKILL が届かない)でも、リーダースレッドと pipe の fd が返ることを
    /// 固定する。EOF の到来を資源解放の唯一の条件にしている実装ではここが落ちる。
    @Test("殺し切れない孫が標準出力を握っていてもスレッドと fd は返る", testTimeLimit(pollingBudgetFallback: leakPollingBudget))
    func releasesResourcesWhenWriteEndSurvivesTermination() async throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        let sleeper = try makeHangingRepo(in: temp.url, escapesProcessGroup: true)
        defer { killSleepers(matching: sleeper.path) }
        let baselinePipes = openPipeCount()
        let baselineReaders = readerThreadCount()

        // 猶予切れで資源が返ることの検証は猶予の満了そのものを待つため、この待ちだけは
        // テスト側の工夫では縮められない。既定の 5 秒だと構造的に遅いテストになるので、
        // 短い猶予を注入して「猶予切れで返る」という不変条件だけを短時間で固定する。
        let runner = GitCommandRunner(timeout: hangingBudget, terminationGrace: shortTerminationGrace)
        let results = runInBackground(runner, sleeper, in: temp.url)
        #expect(await waitUntil { processExists(matching: sleeper.path) == true })
        #expect(await waitUntil { results.get() == [GitCommandOutcome.unavailable] })

        // 孫は生き残るので EOF は永遠に来ない。それでも資源は返らなければならない。
        let budget = testTimeout(fallback: leakPollingBudget)
        await waitUntil(timeout: budget) { openPipeCount() <= baselinePipes }
        await waitUntil(timeout: budget) { readerThreadCount() <= baselineReaders }
        #expect(processExists(matching: sleeper.path) == true, "この経路では孫が残るのが仕様")
    }
}
