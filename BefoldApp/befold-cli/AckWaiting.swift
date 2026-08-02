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
    /// `timeout: 0` はポーリングを一切行わず、呼び出し時点の観測状態をそのまま返す。
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
    private let center: NotificationCenter

    /// - Parameter center: 観測対象の通知センター。既定は本番と同じ
    ///   `DistributedNotificationCenter`。テストではローカルの `NotificationCenter()` を
    ///   注入することで、IPC・メインランループを介さない同期配送に対して
    ///   requestID フィルタと cancel() の解除だけを検証できる
    ///   (`AckWaitingTests` を参照。ここが検証しているのは実配送の挙動ではなく
    ///   waiter 自身のロジックなので、注入シームで unit 化する対象)。
    public init(requestID: String, center: NotificationCenter = DistributedNotificationCenter.default()) {
        self.center = center
        observer = center.addObserver(
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
