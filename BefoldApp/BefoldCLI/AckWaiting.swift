import Foundation

/// CLIInstanceRouter.forward() が使う ACK の待ち受け。
///
/// 生成した時点で観測を開始し、`cancel()` まで解除しない。post のたびに登録・解除を
/// 繰り返すと、post 直後〜登録前と、再送の合間に ACK を取りこぼす窓ができるため、
/// 「観測の開始」と「待つ」を別の操作に分けている。
public protocol AckWaiting {
    /// ACK を最大 `timeout` 秒待つ。生成後〜この呼び出しより前に届いた ACK も観測済みとして true を返す。
    func wait(timeout: TimeInterval) -> Bool
    /// 観測を終了する。以後 `wait` は使えない。
    func cancel()
}

/// DistributedNotificationCenter 経由の ACK を待つ既定の実装。
///
/// 通知は投稿側のスレッドで配送されうるため、観測フラグはロックで保護する。
public final class DistributedAckWaiter: AckWaiting, @unchecked Sendable {
    private let lock = NSLock()
    private var acked = false
    private var observer: (any NSObjectProtocol)?

    public init(requestID: String) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: CLIInstanceRouter.openRequestAckNotificationName, object: nil, queue: nil
        ) { [weak self] notification in
            guard notification.userInfo?["requestID"] as? String == requestID else { return }
            self?.markAcked()
        }
    }

    deinit { cancel() }

    private func markAcked() {
        lock.lock()
        defer { lock.unlock() }
        acked = true
    }

    private var isAcked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return acked
    }

    public func wait(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isAcked, Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
        }
        return isAcked
    }

    public func cancel() {
        lock.lock()
        let observer = observer
        self.observer = nil
        lock.unlock()
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
    }
}
