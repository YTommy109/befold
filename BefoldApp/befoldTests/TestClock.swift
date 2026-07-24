import Foundation
import Testing

/// 実時間に依存しない手動進行クロック。`advance(by:)` で仮想時刻を進め、
/// 期限が到来した `sleep` の continuation を resume する。
/// グレース期間タイマー(ViewerStore.scheduleFileGone)のテストを決定的にするために使う。
///
/// register-after-advance レース対策として `pendingSleepCount` を公開し、
/// `advance` の前に `waitForPendingSleepers(atLeast:)` でスリーパー登録を待てるようにする。
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    var now: Instant {
        lock.withLock { current }
    }

    var minimumResolution: Duration {
        .zero
    }

    /// 現在 `sleep` で待機中のスリーパー数。テストが `advance` 前に登録完了を待つために使う。
    var pendingSleepCount: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = lock.withLock { () -> Int in
            let value = nextID
            nextID += 1
            return value
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                // onCancel と本体を lock で直列化し、登録前キャンセルの取りこぼしを防ぐ。
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                lock.unlock()
                return
            }
            let sleeper = sleepers.remove(at: index)
            lock.unlock()
            sleeper.continuation.resume(throwing: CancellationError())
        }
    }

    /// 仮想時刻を進め、期限が到来したスリーパーを resume する。
    func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        lock.unlock()
        // 再入を避けるため lock 解放後に resume する。
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// スリーパーが指定数以上登録されるまで待つ。実時間 sleep には依存せず yield で譲る。
    func waitForPendingSleepers(atLeast count: Int, maxYields: Int = 100_000) async {
        var yields = 0
        while pendingSleepCount < count, yields < maxYields {
            await Task.yield()
            yields += 1
        }
    }
}

/// MainActor 上の保留タスク(グレースタスクの継続など)を進めるため数回 yield する。
/// 「発火しない」ことを確認する否定的アサーションで使う。
@MainActor
func yieldMainActor(_ times: Int = 10) async {
    for _ in 0 ..< times {
        await Task.yield()
    }
}

/// 条件が満たされるまで MainActor 上で yield し続ける。実時間 sleep には依存しない。
/// 「発火する」ことを確認する肯定的アサーションで使う。
/// `maxYields` に達しても条件が成立しなければ失敗を記録する（黙って素通りさせない）。
@MainActor
@discardableResult
func waitUntilYielding(
    maxYields: Int = 100_000,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async -> Bool {
    var yields = 0
    while !condition(), yields < maxYields {
        await Task.yield()
        yields += 1
    }
    if condition() { return true }
    Issue.record(
        "waitUntilYielding が \(maxYields) 回の yield で条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}
