import Foundation
import Testing

/// 同期的にスレッドを塞ぐ待機（`DispatchSemaphore.wait()`）に、必ず上限を付けるための
/// ヘルパー。フェイクが「遅い実装」を演じるためにブロックする箇所で使う。
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

    recordBlockingWaitTimeout(label, budget: budget, sourceLocation: sourceLocation)
}

private func recordBlockingWaitTimeout(_ label: String, budget: Double, sourceLocation: SourceLocation) {
    Issue.record(
        "\(label): 同期待機が \(budget) 秒で上限に達した（解放されないまま協調スレッドを塞いでいる）",
        sourceLocation: sourceLocation
    )
}

/// `open()` されるまで呼び出しスレッドを**同期的に**塞ぐゲート。`AsyncGate` の同期版で、
/// async にできない同期プロトコル実装（`FileReading.readData` など）のフェイクが
/// 「遅い実装」を演じる箇所で使う。開いた後の `wait` は何回来ても即座に戻る。
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

    /// ゲートを開き、待機中の全員を再開する。以後の `wait` は即座に戻る。
    public func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }

    /// ゲートが開くまで呼び出しスレッドを塞ぐ。上限に達したら `Issue.record` して戻る
    /// （上限が要る理由は `waitOrRecordTimeout` の doc を参照）。
    /// - Returns: ゲートが開いて戻ったら true。上限に達したら false。
    ///   呼び出し元がテスト本体なら無視してよい（失敗は記録済み）。ゲート自身の
    ///   テストのように「上限で戻った」を通過と区別したい場合にだけ参照する。
    @discardableResult
    public func wait(
        _ label: String,
        fallback seconds: Double = 15,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Bool {
        let budget = testTimeoutSeconds(fallback: seconds)
        let deadline = Date(timeIntervalSinceNow: budget)
        condition.lock()
        defer { condition.unlock() }
        while !opened {
            guard condition.wait(until: deadline) else {
                recordBlockingWaitTimeout(label, budget: budget, sourceLocation: sourceLocation)
                return false
            }
        }
        return true
    }
}
