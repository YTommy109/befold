import Foundation

/// 短時間に連続する呼び出しを合一し、最後の呼び出しから一定時間後に 1 回だけ実行する。
/// NSLock で排他制御し、スレッド安全性を保証する。
final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private let lock = NSLock()

    init(delay: TimeInterval, queue: DispatchQueue) {
        self.delay = delay
        self.queue = queue
    }

    /// アクションをスケジュールする。既にスケジュール済みのアクションがあればキャンセルして置き換える。
    func schedule(action: @escaping @Sendable () -> Void) {
        let item = lock.withLock {
            workItem?.cancel()
            let item = DispatchWorkItem(block: action)
            workItem = item
            return item
        }
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// スケジュール済みのアクションをキャンセルする。
    func cancel() {
        lock.withLock {
            workItem?.cancel()
            workItem = nil
        }
    }
}
