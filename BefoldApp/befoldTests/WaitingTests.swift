import BefoldTestSupport
import Foundation
import Testing

/// ポーリング待機ヘルパー(BefoldTestSupport/Waiting.swift)自身のテスト。
///
/// 待機ヘルパーが戻らない・回り続けるという壊れ方は、テスト側の失敗としては
/// 現れない(失敗テスト名も出ないまま CI のジョブタイムアウトまで走る)ため、
/// ここで直接測る。
@Suite
struct WaitingTests {
    /// `.timeLimit` がテストタスクをキャンセルした後は、待機を続けずに戻る。
    /// キャンセルを見ないと `try? await Task.sleep` が即時 throw を繰り返し、
    /// 壁時計予算を持たない `waitForMainActorDelivery` はホットスピンしたまま
    /// `action` を永久に実行し続ける(TASK-340)。
    @Test("キャンセルされたら待機から抜け、action を回し続けない", testTimeLimit())
    func waitForMainActorDeliveryReturnsOnCancellation() async {
        let actionCount = LockedBox(0)
        let finished = LockedBox(false)
        // 修正を戻したときに待機タスクが残り続けてプロセス内で回り続けないよう、
        // テスト終了時に条件を成立させて必ず終わらせる。
        let stopSpinning = LockedBox(false)
        defer { stopSpinning.set(true) }
        let task = Task {
            await waitForMainActorDelivery(interval: 0.01, action: {
                actionCount.set(actionCount.get() + 1)
            }, until: {
                stopSpinning.get()
            })
            finished.set(true)
        }
        // 待機が始まっている(= action が動いている)ことを確かめてから止める。
        await waitForMainActorDelivery { actionCount.get() > 0 }

        task.cancel()

        // 修正前はここで戻ってこず、キャンセル後も action が回り続ける。
        // 壁時計予算のポーリングで待たない(理由は下の注記)。上限は `.timeLimit` が担う。
        await task.value
        #expect(finished.get())
        let afterReturn = actionCount.get()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(actionCount.get() == afterReturn)
    }

    /// `@MainActor` 版も同じ性質を持つ。こちらも壁時計予算を持たないため、キャンセルを
    /// 見なければ `.timeLimit` の打ち切り後もメインアクター上で回り続ける(TASK-354)。
    ///
    /// 「戻ってきたこと」の確認に壁時計予算のポーリングを使わないこと。full suite では
    /// 待機タスクがメインアクターの順番待ちに積まれるため、予算は操作にかかった時間では
    /// なく順番待ちの時間を測ることになり、正しく戻ってくる実装でも落ちる(実測: 予算 5 秒の
    /// `waitUntil` で書いたところ TSan 付き全体実行 10 回中 1 回落ちた)。タスクを直接
    /// `await` すれば混雑は遅延になるだけで、戻らない回帰はスイートの `.timeLimit` が捕まえる。
    @Test("MainActor 版の予算なし待機もキャンセルで抜ける", testTimeLimit())
    @MainActor
    func waitForDeliveryOnMainActorReturnsOnCancellation() async {
        let finished = LockedBox(false)
        let stopSpinning = LockedBox(false)
        defer { stopSpinning.set(true) }
        let task = Task { @MainActor in
            await waitForDeliveryOnMainActor { stopSpinning.get() }
            finished.set(true)
        }
        // 待機が始まるのを待ってから止める(即キャンセルだと開始前に抜けうる)。
        try? await Task.sleep(for: .milliseconds(50))

        task.cancel()

        await task.value
        #expect(finished.get())
    }

    /// 期限付きの待機もキャンセルで抜ける(共通ループを通るため同じ性質を持つ)。
    /// 予算を使い切るまで回り続けると、キャンセル済みのテストが所定秒数ぶん
    /// CPU を占有してから終わる。
    @Test("期限付きの待機もキャンセルで抜ける", testTimeLimit())
    func waitUntilWithRetryReturnsOnCancellation() async {
        let finished = LockedBox(false)
        let stopSpinning = LockedBox(false)
        defer { stopSpinning.set(true) }
        let task = Task {
            _ = await waitUntilWithRetry(
                timeout: 300, interval: 0.01, action: {}, until: { stopSpinning.get() }
            )
            finished.set(true)
        }
        // 待機が始まるのを待ってから止める(即キャンセルだと開始前に抜けうる)。
        try? await Task.sleep(for: .milliseconds(50))

        task.cancel()

        await task.value
        #expect(finished.get())
    }
}
