@testable import befold_cli
@testable import BefoldCLI
import Foundation

/// 実 DistributedNotificationCenter を使わずに forward() の ACK 待ちを差し替えるスタブ。
///
/// `ackOnWait` 回目の `wait` で ACK 観測済みを返す。0 を渡すと一度も ACK しない。
/// `onEvent` には "wait" / "cancel" が発生順に渡るため、post との前後関係を検証できる。
final class StubAckWaiter: AckWaiting {
    private let ackOnWait: Int
    private let onEvent: (String) -> Void
    private(set) var waitCount = 0
    private(set) var cancelCount = 0

    init(ackOnWait: Int = 1, onEvent: @escaping (String) -> Void = { _ in }) {
        self.ackOnWait = ackOnWait
        self.onEvent = onEvent
    }

    func wait(timeout _: TimeInterval) async -> Bool {
        waitCount += 1
        onEvent("wait")
        return ackOnWait > 0 && waitCount >= ackOnWait
    }

    func cancel() {
        cancelCount += 1
        onEvent("cancel")
    }
}
