@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct DebouncerTests {
    /// テスト用のデバウンス遅延。プロダクト既定より短くして所要時間を抑える。
    private static let delay: TimeInterval = 0.1

    /// 「発火しない」ことを検証するための目印。同じ直列キューへ、既に積まれたどの
    /// 予約よりも遅い期限で積むので、これが走った時点で先行の予約は発火済みか取り消し済み。
    /// 固定時間の静穏待ちで「十分待ったつもり」にならずに済む。
    private static func passPendingDeadlines(on queue: DispatchQueue) async {
        let passed = LockedBox(false)
        queue.asyncAfter(deadline: .now() + delay) { passed.set(true) }
        await waitUntil { passed.get() }
    }

    @Test(testTimeLimit())
    func firesAfterDelay() async {
        await confirmation { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: Self.delay, queue: queue)
            let fired = LockedBox(false)

            debouncer.schedule {
                fired.set(true)
                confirm()
            }

            // 固定 sleep ではなく発火を条件待ちする。
            // 発火しなければ waitUntil 自身が失敗を記録する。
            await waitUntil { fired.get() }
        }
    }

    @Test(testTimeLimit())
    func coalescesRapidCalls() async {
        // 合一されて 1 回だけ実行されること
        await confirmation(expectedCount: 1) { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: Self.delay, queue: queue)
            let fireCount = LockedBox(0)

            // 短時間に 5 回連続で呼び出す
            for _ in 0 ..< 5 {
                debouncer.schedule {
                    fireCount.update { $0 += 1 }
                    confirm()
                }
            }

            // まず 1 回目の発火を待ち、そのあと追加発火が無いことを確かめる
            // (合一の検証は「1 回で止まる」ことまで見ないと成立しないため)。
            await waitUntil { fireCount.get() >= 1 }
            await Self.passPendingDeadlines(on: queue)
            #expect(fireCount.get() == 1)
        }
    }

    @Test(testTimeLimit())
    func cancelPreventsExecution() async {
        // 十分待ってもアクションが実行されないこと
        await confirmation(expectedCount: 0) { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: Self.delay, queue: queue)

            // アクションを登録してすぐキャンセル
            debouncer.schedule {
                confirm()
            }
            debouncer.cancel()

            // 否定的検証のため発火は待てない。発火するはずの時刻を過ぎたことを目印で確かめる。
            await Self.passPendingDeadlines(on: queue)
        }
    }

    /// cancel 後に再度 schedule しても正常に発火すること
    @Test(testTimeLimit())
    func reschedulesAfterCancel() async {
        await confirmation { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: Self.delay, queue: queue)
            let fired = LockedBox(false)

            // 一度スケジュールしてキャンセル
            debouncer.schedule {}
            debouncer.cancel()

            // 再度スケジュールして発火を確認
            debouncer.schedule {
                fired.set(true)
                confirm()
            }

            await waitUntil { fired.get() }
        }
    }
}
