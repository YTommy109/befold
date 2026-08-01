@testable import befold_cli
@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// 実際の DistributedNotificationCenter を通して ACK 待ち受けの取りこぼしを検証する。
/// プロセス間通知の実挙動が結果を左右するため Integration。
/// 配送が来ないまま待ち続ける退行で実行が止まらないよう、待機予算の単一情報源から
/// スイート全体のタイムリミットを与える。
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

    /// 「取りこぼしていないから観測しなかった」ことを確かめたいが、否定は固定時間待っても
    /// 「まだ来ていないだけ」と区別が付かない。そこで同一通知が複数 observer に配送される
    /// 性質を使い、別の requestID を持つ番兵 waiter で配送完了を先に肯定確認してから、
    /// 対象 waiter が(配送済みの時点で)未観測であることを wait(timeout: 0) で見る。
    ///
    /// 対象 waiter を番兵より先に生成 = 先に登録している。CFNotificationCenter は
    /// 同一 post 内の observer 呼び出し順を規定していないが、実装上は登録順に呼ばれるため、
    /// この順序に依存している。この前提に依存する以上、対象と番兵の生成順を
    /// 入れ替えてはならない。
    @Test("別の requestID の ACK は観測しない")
    func ackForDifferentRequestIDIsIgnored() async {
        let otherID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: UUID().uuidString)
        defer { waiter.cancel() }
        let sentinel = DistributedAckWaiter(requestID: otherID)
        defer { sentinel.cancel() }

        CLIRequestWire.sendAck(requestID: otherID)

        await #expect(sentinel.wait(timeout: testTimeoutSeconds(fallback: 15)))
        await #expect(!waiter.wait(timeout: 0))
    }

    /// 上と同じ理由で番兵方式にする。cancel していない同一 requestID の番兵で配送完了を
    /// 確認してから、cancel 済み側が未観測であることを見る。ここでは呼び出し順への
    /// 依存はない: `waiter.cancel()` は post より前に同期的に observer を除去しており、
    /// post 時点で当該 requestID の observer は sentinel しか登録されていない。
    @Test("cancel 後に届いた ACK は観測しない")
    func ackAfterCancelIsIgnored() async {
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID)
        waiter.cancel()
        let sentinel = DistributedAckWaiter(requestID: requestID)
        defer { sentinel.cancel() }

        CLIRequestWire.sendAck(requestID: requestID)

        await #expect(sentinel.wait(timeout: testTimeoutSeconds(fallback: 15)))
        await #expect(!waiter.wait(timeout: 0))
    }
}
