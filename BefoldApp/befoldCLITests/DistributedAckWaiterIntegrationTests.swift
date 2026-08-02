@testable import befold_cli
@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// 実際の DistributedNotificationCenter を通した ACK の往復を検証する。
/// プロセス間通知の実挙動が結果を左右するため Integration。
///
/// requestID フィルタや cancel() による解除といった waiter 自身のロジックは、
/// `AckWaitingTests`(unit)がローカル `NotificationCenter` 注入で検証する。
/// ここに残すのは「実配送(IPC・メインランループ経由)が成立する」ことだけ。
///
/// この経路の配送はメインランループ経由(`AckWaiting.swift` の `wait` の doc を参照)。
/// full suite 実行時、スイートレベルの `@MainActor` を持つ他スイートがメインアクターを
/// 長時間占有していると、その間 ACK は配送されず秒オーダーで止まりうることを実測で
/// 確認している(単独実行では約 0.02 秒、full suite 実行時は 1〜3 秒台)。そのため
/// 待機予算は共有ヘルパーの既定値(`testTimeoutSeconds(fallback: 15)`)を使う。
@Suite(testTimeLimit())
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
        // 同じ単一情報源(`BEFOLD_TEST_TIMEOUT_SECONDS`)から採る。プロジェクト標準の
        // 既定値(waitUntil 系と同じ 15 秒)に揃え、負荷時の余裕を確保する。
        #expect(await waiter.wait(timeout: testTimeoutSeconds(fallback: 15)))
    }
}
