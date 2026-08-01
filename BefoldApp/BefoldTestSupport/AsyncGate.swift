import Foundation

/// open() されるまで待機者をサスペンドさせるゲート。
/// スピン(yield ループ)ではなく continuation で待つため、並列実行中の
/// 他テストから CPU を奪わない。固定 sleep で「十分待ったつもり」になる代わりに、
/// テストが制御したいタイミングで明示的に解放して競合を決定的に再現するのに使う。
public final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// ゲートを開き、待機中の全員を再開する。以後の wait() は即座に戻る。
    public func open() {
        lock.lock()
        opened = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending {
            waiter.resume()
        }
    }

    /// ゲートが開くまでサスペンドする。
    public func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
