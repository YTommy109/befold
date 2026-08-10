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

    Issue.record(
        "\(label): 同期待機が \(budget) 秒で上限に達した（signal されないまま協調スレッドを塞いでいる）",
        sourceLocation: sourceLocation
    )
}
