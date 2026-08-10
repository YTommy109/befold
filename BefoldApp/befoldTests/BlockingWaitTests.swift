import BefoldTestSupport
import Foundation
import Testing

/// 同期ブロッキングのゲート(BefoldTestSupport/BlockingWait.swift)自身のテスト。
///
/// このゲートが「1 回の signal で 1 つだけ通す」実装(DispatchSemaphore)へ戻ると、
/// テスト終了後に走った余分な待機が誰にも解放されないまま上限に達し、
/// どのテストにも紐づかない «unknown» の Issue として記録される。全スイートが
/// pass していても run 全体が exit 1 で落ちるうえ、失敗テスト名も出ない(TASK-427)。
/// 壊れ方がテストの失敗として現れないため、ゲートの性質をここで直接測る。
@Suite(testTimeLimit())
struct BlockingGateTests {
    /// `wait` を **専用スレッド** で `count` 本走らせ、**ゲートが開いて戻った数**だけを
    /// `passed` に数える。上限で戻った分を数えると、1 つずつしか通さない実装でも
    /// 上限到達で数が揃ってしまい、テストが緑のまま «unknown» の Issue だけが残る
    /// （TASK-427 の壊れ方そのもの）。
    ///
    /// `DispatchQueue.global()` で走らせないこと。塞いでいる間そのワーカーが占有され、
    /// コア数の少ない環境では `open()` を出すテスト本体の再開自体が遅れる。実測:
    /// `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（プール幅 1）では 60 秒経っても開けられず
    /// このテスト自身が «unknown» の Issue を出し、CI（3〜4 コア）では 0.2 秒の sleep が
    /// 13.6 秒に伸びてその間ワーカー 3 本を塞いでいた。専用スレッドなら塞いでも
    /// ディスパッチ側の供給に影響しない。
    private func startWaiters(_ count: Int, on gate: BlockingGate, passed: LockedBox<Int>) {
        for _ in 0 ..< count {
            Thread.detachNewThread {
                guard gate.wait("BlockingGateTests") else { return }
                passed.update { $0 += 1 }
            }
        }
    }

    @Test("open() 済みのゲートは後から来た待機を何回でも素通しする")
    func openedGatePassesEveryLaterWaiter() async {
        let gate = BlockingGate()
        gate.open()

        let passed = LockedBox(0)
        startWaiters(3, on: gate, passed: passed)

        await waitUntil { passed.get() == 3 }
    }

    @Test("open() は待機中の全員をまとめて解放する")
    func openReleasesAllPendingWaiters() async {
        let gate = BlockingGate()
        let passed = LockedBox(0)
        startWaiters(3, on: gate, passed: passed)

        // 開ける前に通ってはならない(待機が始まる前なら 0 のままで成立するが、
        // 素通ししてしまう実装なら必ず落ちる)。
        try? await Task.sleep(for: .milliseconds(200))
        #expect(passed.get() == 0)

        gate.open()

        await waitUntil { passed.get() == 3 }
    }

    @Test("最初から開いたゲートは待たせない")
    func gateCreatedOpenDoesNotBlock() async {
        let gate = BlockingGate(isOpen: true)
        let passed = LockedBox(0)
        startWaiters(1, on: gate, passed: passed)

        await waitUntil { passed.get() == 1 }
    }
}
