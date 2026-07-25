import BefoldCLI
import Foundation

/// CLIRequestForwarder.forward() が使う ACK の待ち受け。
///
/// 生成した時点で観測を開始し、`cancel()` まで解除しない。post のたびに登録・解除を
/// 繰り返すと、post 直後〜登録前と、再送の合間に ACK を取りこぼす窓ができるため、
/// 「観測の開始」と「待つ」を別の操作に分けている。
public protocol AckWaiting {
    /// ACK を最大 `timeout` 秒待つ。生成後〜この呼び出しより前に届いた ACK も観測済みとして true を返す。
    ///
    /// 待機は必ず async にする。CLI の実行経路(ArgumentParser の async main →
    /// `@MainActor run() async`)は Swift 並行処理のコンテキストであり、そこで
    /// `RunLoop.run(_:before:)` を同期的に回すと Distributed Notification が配送されない
    /// (コンパイラもこの API を async コンテキストでは使用不可としている)。
    /// await して中断点を作れば、通知はメインキュー側で配送される。
    func wait(timeout: TimeInterval) async -> Bool
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
            forName: CLIRequestWire.ackNotificationName, object: nil, queue: nil
        ) { [weak self] notification in
            guard CLIRequestWire.ackRequestID(from: notification.userInfo) == requestID else { return }
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

    public func wait(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isAcked, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
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
