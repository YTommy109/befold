@testable import befold_cli
@testable import BefoldCLI
import Foundation
import Testing

/// `DistributedAckWaiter` の requestID フィルタと `cancel()` による解除を、注入した
/// ローカル `NotificationCenter` に対して検証する。
///
/// これらは実 `DistributedNotificationCenter`(IPC・メインランループ経由)の挙動ではなく
/// waiter 自身のロジックなので、注入シームで unit 化する対象。`sendAck` にはシームを
/// 設けていない(本番の `deliverImmediately: true` を型判定なしに保つため)。代わりに
/// `CLIRequestWire.ackUserInfo(requestID:)` が公開しているワイヤ表現を使い、
/// 標準の `NotificationCenter.post` でローカル注入した center へ直接投稿する。
///
/// ローカル `NotificationCenter.post` は戻る前に登録済みの全 observer を同期的に
/// 呼び切るため、TASK-249 で必要だった番兵(sentinel)は要らない。ただし `wait(timeout: 0)`
/// 自体は依然として使う: 依存の性質が変わっただけで(post が返った時点で対象 waiter の
/// observer 呼び出しも完了済みであることが保証されているため、即時に結果を読める)、
/// 呼び出し自体は残る。実配送の往復自体は
/// `DistributedAckWaiterIntegrationTests.ackArrivingBeforeWaitIsStillObserved` が担う。
@Suite
struct AckWaitingTests {
    private func post(requestID: String, to center: NotificationCenter) {
        center.post(
            name: CLIRequestWire.ackNotificationName, object: nil,
            userInfo: CLIRequestWire.ackUserInfo(requestID: requestID)
        )
    }

    @Test("別の requestID の ACK は観測しない")
    func ackForDifferentRequestIDIsIgnored() async {
        let center = NotificationCenter()
        let otherID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: UUID().uuidString, center: center)
        defer { waiter.cancel() }

        post(requestID: otherID, to: center)

        #expect(await !(waiter.wait(timeout: 0)))
    }

    @Test("cancel 後に届いた ACK は観測しない")
    func ackAfterCancelIsIgnored() async {
        let center = NotificationCenter()
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID, center: center)
        waiter.cancel()

        post(requestID: requestID, to: center)

        #expect(await !(waiter.wait(timeout: 0)))
    }

    /// 正常系も unit で押さえる: ローカル配送に対して requestID が一致すれば観測される。
    @Test("一致する requestID の ACK は観測される")
    func ackForMatchingRequestIDIsObserved() async {
        let center = NotificationCenter()
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID, center: center)
        defer { waiter.cancel() }

        post(requestID: requestID, to: center)

        #expect(await waiter.wait(timeout: 0))
    }
}
