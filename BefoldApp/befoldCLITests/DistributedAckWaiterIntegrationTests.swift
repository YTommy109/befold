@testable import befold_cli
@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// 実際の DistributedNotificationCenter を通して ACK 待ち受けの取りこぼしを検証する。
/// プロセス間通知の実挙動が結果を左右するため Integration。
/// 配送が来ないまま待ち続ける退行で実行が止まらないよう、待機予算の単一情報源から
/// スイート全体のタイムリミットを与える。
@Suite(testTimeLimit(), .serialized)
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

    /// 「取りこぼしていないから観測しなかった」ことを確かめたいが、否定は固定時間待っても
    /// 「まだ来ていないだけ」と区別が付かない。そこで同一通知が複数 observer に配送される
    /// 性質を使い、別の requestID を持つ番兵 waiter で配送完了を先に肯定確認してから、
    /// 対象 waiter が(配送済みの時点で)未観測であることを wait(timeout: 0) で見る。
    ///
    /// 番兵は 2 段構えにする。CFNotificationCenter は同一 post 内の observer 呼び出し順を
    /// 規定しないため、1 通目(gateA)自身が観測できても「対象 waiter の observer(不一致で
    /// 何もしない)が呼ばれ終えた」保証にはならない。配送は同一プロセスのランループ上で
    /// 直列化される(2 通目の配送は 1 通目の配送パスが完了してから始まる)ため、無関係な
    /// requestID の 2 通目(gateB)まで観測できて初めて「1 通目のパスは確実に完了済み」と
    /// 言える。
    @Test("別の requestID の ACK は観測しない")
    func ackForDifferentRequestIDIsIgnored() async {
        let otherID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: UUID().uuidString)
        defer { waiter.cancel() }

        let gateA = DistributedAckWaiter(requestID: otherID)
        defer { gateA.cancel() }
        CLIRequestWire.sendAck(requestID: otherID)
        await #expect(gateA.wait(timeout: testTimeoutSeconds(fallback: 5)))

        let gateBID = UUID().uuidString
        let gateB = DistributedAckWaiter(requestID: gateBID)
        defer { gateB.cancel() }
        CLIRequestWire.sendAck(requestID: gateBID)
        await #expect(gateB.wait(timeout: testTimeoutSeconds(fallback: 5)))

        await #expect(!waiter.wait(timeout: 0))
    }

    /// 上と同じ理由で番兵方式にする。ただしここでは 2 段番兵は不要: `waiter.cancel()` は
    /// post より前に同期的に observer を除去しており、post 時点で当該 requestID の
    /// observer は sentinel しか登録されていない。同一 post 内の呼び出し順を気にする
    /// 対象がそもそも存在しないため、sentinel の観測 1 回だけで済む。
    @Test("cancel 後に届いた ACK は観測しない")
    func ackAfterCancelIsIgnored() async {
        let requestID = UUID().uuidString
        let waiter = DistributedAckWaiter(requestID: requestID)
        waiter.cancel()
        let sentinel = DistributedAckWaiter(requestID: requestID)
        defer { sentinel.cancel() }

        CLIRequestWire.sendAck(requestID: requestID)

        await #expect(sentinel.wait(timeout: testTimeoutSeconds(fallback: 5)))
        await #expect(!waiter.wait(timeout: 0))
    }
}
