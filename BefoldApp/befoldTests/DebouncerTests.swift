@testable import befold
import Foundation
import Testing

@Suite
struct DebouncerTests {
    @Test(.timeLimit(.minutes(1)))
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

    @Test(.timeLimit(.minutes(1)))
    func coalescesRapidCalls() async {
        nonisolated(unsafe) var callCount = 0
        let queue = DispatchQueue(label: "test.debouncer")
        let debouncer = Debouncer(delay: 0.1, queue: queue)

        // 短時間に 5 回連続で呼び出す
        for _ in 0 ..< 5 {
            debouncer.schedule {
                callCount += 1
            }
        }

        // デバウンス後の発火を待つ
        try? await Task.sleep(for: .seconds(0.5))

        // 合一されて 1 回だけ実行されること
        #expect(callCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelPreventsExecution() async {
        nonisolated(unsafe) var fired = false
        let queue = DispatchQueue(label: "test.debouncer")
        let debouncer = Debouncer(delay: 0.1, queue: queue)

        // アクションを登録してすぐキャンセル
        debouncer.schedule {
            fired = true
        }
        debouncer.cancel()

        // 十分待ってもアクションが実行されないこと
        try? await Task.sleep(for: .seconds(0.3))
        #expect(!fired)
    }

    /// cancel 後に再度 schedule しても正常に発火すること
    @Test(.timeLimit(.minutes(1)))
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
