@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct DebouncerTests {
    @Test(testTimeLimit())
    func firesAfterDelay() async {
        await confirmation { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: 0.1, queue: queue)

            // デバウンサーにアクションを登録
            debouncer.schedule {
                confirm()
            }

            // アクション発火を待つ
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    @Test(testTimeLimit())
    func coalescesRapidCalls() async {
        // 合一されて 1 回だけ実行されること
        await confirmation(expectedCount: 1) { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: 0.1, queue: queue)

            // 短時間に 5 回連続で呼び出す
            for _ in 0 ..< 5 {
                debouncer.schedule {
                    confirm()
                }
            }

            // デバウンス後の発火を待つ
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    @Test(testTimeLimit())
    func cancelPreventsExecution() async {
        // 十分待ってもアクションが実行されないこと
        await confirmation(expectedCount: 0) { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: 0.1, queue: queue)

            // アクションを登録してすぐキャンセル
            debouncer.schedule {
                confirm()
            }
            debouncer.cancel()

            try? await Task.sleep(for: .seconds(0.3))
        }
    }

    /// cancel 後に再度 schedule しても正常に発火すること
    @Test(testTimeLimit())
    func reschedulesAfterCancel() async {
        await confirmation { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: 0.1, queue: queue)

            // 一度スケジュールしてキャンセル
            debouncer.schedule {}
            debouncer.cancel()

            // 再度スケジュールして発火を確認
            debouncer.schedule {
                confirm()
            }

            // アクション発火を待つ
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
