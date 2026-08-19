import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// `withBlockingWork`(BefoldApp/BefoldKit/BlockingWork.swift)自身のテスト。
///
/// ここが `Task.detached` へ戻ると、同期的に塞ぐ処理が Swift 並行の協調スレッド
/// プールを占有する。プール幅はコア数で固定されているため、幅ぶんの同時ブロックで
/// プロセス全体の前進が止まり、全スイートが pass していても «unknown» issue で
/// run 全体が exit 1 で落ちる(TASK-424 / TASK-427 / TASK-516 で 3 度再発した)。
/// 壊れ方がテストの失敗として現れないため、性質をここで直接測る。
@Suite(testTimeLimit())
struct BlockingWorkTests {
    /// 協調スレッドプールの幅(= コア数)を超える数を同時に塞ぐ。`Task.detached`
    /// 実装ならここで前進が止まり、ゲートを開ける側まで到達しない。
    @Test("プール幅を超える数を同時に塞いでも全ての呼び出しが開始される")
    func startsEveryCallEvenWhenMoreThanPoolWidthAreBlocked() async {
        let concurrency = ProcessInfo.processInfo.activeProcessorCount * 4
        let gate = BlockingGate()
        let entered = LockedBox(0)
        let finished = LockedBox(0)

        for _ in 0 ..< concurrency {
            Task {
                await withBlockingWork {
                    entered.update { $0 += 1 }
                    gate.wait("BlockingWorkTests")
                }
                finished.update { $0 += 1 }
            }
        }

        await waitUntil { entered.get() == concurrency }
        gate.open()
        await waitUntil { finished.get() == concurrency }
    }

    @Test("戻り値をそのまま返す")
    func returnsWorkResult() async {
        let result = await withBlockingWork { 42 }

        #expect(result == 42)
    }
}
