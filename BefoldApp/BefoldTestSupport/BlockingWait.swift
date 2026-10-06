import Foundation
import Testing

/// 同期的にスレッドを塞ぐ待機（`DispatchSemaphore.wait()`）に、必ず上限を付けるための
/// ヘルパー。**テスト本体の側**が、バックグラウンドの完了（サブプロセスの終了など）を
/// 同期に待つ箇所で使う。フェイクが「遅い実装」を演じる足止めには使わない
/// （`BlockingGate` を使う。足止めに壁時計の上限を付けると、上限が MainActor の
/// 順番待ちを測ってしまう = ADR 0012）。
///
/// なぜ上限が要るか（TASK-424 の実測）:
/// 上限なしの `wait()` は、待っている間そのスレッドを協調スレッドプールから外す。
/// プールの幅はコア数で決まるため、ローカル（10 コア）では他のテストが進めてしまい
/// 表面化しないが、CI の macOS ランナー（3〜4 コア）では埋まり切って**テストプロセス
/// 全体が停止**する。実際に 2026-08-07 と 08-09 の CI で、テスト出力が途中で完全に
/// 止まったままジョブがキャンセルされるまで数十分〜数時間動かなくなった。
///
/// `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（プール幅 1）でフルスイートを回すと確実に
/// 再現し、`sample(1)` で `GitStatusStoreTests.FakeReader.status` と
/// `GitCommandFileIndexConcurrencyTests.BlockingRepository.trackedFiles` の 2 本が
/// `semaphore_wait_trap` のまま永久停止していることを確認した。メインスレッドは
/// `CFRunLoopRun` で空回りしており、仕事が無いのではなく供給されない状態だった。
///
/// 上限に達したら `Issue.record` で失敗させて戻る。停止は「何も分からないまま止まる」が、
/// 失敗ならどのテストのどの待機かがログに出る。
public func waitOrRecordTimeout(
    _ semaphore: DispatchSemaphore,
    _ label: String,
    fallback seconds: Double = 15,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let budget = testTimeoutSeconds(fallback: seconds)
    guard semaphore.wait(timeout: .now() + budget) == .timedOut else { return }

    Issue.record(
        "\(label): 同期待機が \(budget) 秒で上限に達した（解放されないまま協調スレッドを塞いでいる）",
        sourceLocation: sourceLocation
    )
}

/// `open()` されるまで呼び出しスレッドを**同期的に**塞ぐゲート。`AsyncGate` の同期版で、
/// async にできない同期プロトコル実装（`FileReading.readData` など）のフェイクが
/// 「遅い実装」を演じる箇所で使う。開いた後の `waitUntilOpen` は何回来ても即座に戻る。
/// async の注入点が既にある箇所では、こちらではなく `AsyncGate` を先に選ぶ。
///
/// なぜ `DispatchSemaphore` を 1 回 signal する形で代用しないか（TASK-427 の実測）:
/// signal は待機者を 1 つしか通さないため、テスト終了後に走った再描画が同じフェイクを
/// もう一度呼ぶと、その待機は誰にも signal されず上限に達して `Issue.record` する。
/// テストが既に終わっているので記録はどのテストにも紐づかず、
/// `Test «unknown» recorded an issue at ...` として現れ、全スイートが pass していても
/// run 全体が exit 1 で落ちる（PR #468 の CI: run 31386949217 / job 93449413264 で
/// 1389 tests・202 suites すべて pass しながらこの 1 件で失敗した）。
/// 余分に signal してカウントを数合わせする方式も採れない——初期値より減ったまま
/// 解放された `DispatchSemaphore` は libdispatch がプロセスごと落とすため、
/// 数合わせ自体が別のフレーク源になる。開閉フラグで持てばどちらも起きない。
public final class BlockingGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var opened: Bool

    /// - Parameter isOpen: `true` なら最初から開いた状態で作る（足止めせず素通しさせたい経路用）。
    public init(isOpen: Bool = false) {
        opened = isOpen
    }

    /// ゲートを開き、待機中の全員を再開する。以後の `waitUntilOpen` は即座に戻る。
    public func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }

    /// ゲートが開くまで、**上限なしで**呼び出しスレッドを塞ぐ。
    ///
    /// **壁時計の上限は持たず、呼び出し側が指定する手段も無い（ADR 0012）。** ゲートを
    /// 開けるのはテスト本体で、そこへ着くまでの時間は MainActor の順番待ちで決まる。
    /// 上限があると、それは模した処理の遅さではなく順番待ちを測り、混雑が超えるたびに
    /// 正しいテストが落ちる（TASK-619 は 60 秒、TASK-665 は 15 秒、TASK-672 は 120 秒で
    /// 落ちた）。戻らない回帰の打ち切りは、async の待機と同じくスイートの `.timeLimit` に
    /// 委ねる。
    ///
    /// **塞いではいけない場所では塞がない。** 閉じたゲートを `blockingHazard()` が nil で
    /// ない場所で待とうとしたら、`Issue.record` してすぐ戻る。フェイクを呼ぶ本番コードが
    /// `withBlockingWork` をやめてタスクの上やメインスレッドで同期に呼ぶ退行は、
    /// これで待たずに失敗になる。開いたゲートは、どこから来ても素通しする。
    ///
    /// テスト本体では `defer { gate.open() }` を置くこと。開け忘れたまま結果を待つと
    /// テストが戻らず、`.timeLimit` の記録は出るが run が終わらない（ADR 0012 の実測）。
    /// - Returns: ゲートが開いて戻ったら true。塞ぐのを拒んで戻ったら false。
    ///   フェイクは無視してよい（失敗は記録済み）。
    @discardableResult
    public func waitUntilOpen(sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if opened { return true }
        if let hazard = Self.blockingHazard() {
            Issue.record(
                """
                閉じた BlockingGate を、塞いではいけない場所（\(hazard)）で待とうとした。\
                同期に塞ぐとその前進が止まるため、塞がずに戻った。フェイクを呼ぶ処理が \
                withBlockingWork の専用スレッドへ逃がされているかを確認すること
                """,
                sourceLocation: sourceLocation
            )
            return false
        }
        while !opened {
            condition.wait()
        }
        return true
    }

    /// 呼び出し元の場所を同期に塞ぐと何が止まるか。塞いでよい場所（専用スレッド）なら nil。
    ///
    /// Swift Concurrency のタスクは協調スレッドプールか MainActor の上で走るので、
    /// タスクの上で塞げばそのどちらかが止まる。メインスレッドは、タスクの外
    /// （メインキューのコールバックなど）から来た場合も塞いではいけない。
    /// `DispatchQueue.global()` のワーカーは拾えない（タスクの上ではないため）。
    public static func blockingHazard() -> String? {
        if Thread.isMainThread { return "メインスレッド" }
        if withUnsafeCurrentTask(body: { $0 != nil }) { return "Swift Concurrency のタスク" }
        return nil
    }
}
