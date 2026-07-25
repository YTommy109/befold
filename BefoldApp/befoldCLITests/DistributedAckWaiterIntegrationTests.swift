@testable import befold_cli
@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// 実際の DistributedNotificationCenter を通して ACK 待ち受けの取りこぼしを検証する。
/// プロセス間通知の実挙動が結果を左右するため Integration。
@Suite
struct DistributedAckWaiterIntegrationTests {
    /// 旧実装は post の後に observer を登録していたため、この窓に返った ACK を取りこぼしていた。
    /// 待ち受けを生成した時点から観測が始まっていることを、wait より前に ACK を投げて確かめる。
    @Test("待ち受け開始後・wait 呼び出し前に届いた ACK も観測される")
    func ackArrivingBeforeWaitIsStillObserved() async {
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID)
        defer { waiter.cancel() }

        CLIRequestWire.sendAck(requestID: requestID)

        // プロセス間通知の配送待ちは負荷で伸びるため、待機予算は他のポーリング待機と
        // 同じ単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。固定 5 秒では
        // 並行実行で負荷が上がったときに取りこぼしと区別が付かず散発的に赤くなる。
        #expect(await waiter.wait(timeout: testTimeoutSeconds(fallback: 5)))
    }

    @Test("別の requestID の ACK は観測しない")
    func ackForDifferentRequestIDIsIgnored() async {
        let waiter = DistributedAckWaiter(requestID: UUID().uuidString)
        defer { waiter.cancel() }

        CLIRequestWire.sendAck(requestID: UUID().uuidString)

        let acked = await waiter.wait(timeout: 0.5)
        #expect(!acked)
    }

    @Test("cancel 後に届いた ACK は観測しない")
    func ackAfterCancelIsIgnored() async {
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID)
        waiter.cancel()

        CLIRequestWire.sendAck(requestID: requestID)

        let acked = await waiter.wait(timeout: 0.5)
        #expect(!acked)
    }
}
