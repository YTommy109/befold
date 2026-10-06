import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 同期ブロッキングのゲート(BefoldTestSupport/BlockingWait.swift)自身のテスト。
///
/// このゲートが「1 回の signal で 1 つだけ通す」実装(DispatchSemaphore)へ戻ると、
/// テスト終了後に走った余分な待機が誰にも解放されないまま残る(TASK-427 では上限に
/// 達して、どのテストにも紐づかない «unknown» の Issue で run 全体が exit 1 になった。
/// 上限を持たない今は専用スレッドが残り続ける)。どちらも壊れ方がテストの失敗として
/// 現れないため、ゲートの性質をここで直接測る。
@Suite(testTimeLimit())
struct BlockingGateTests {
    /// `waitUntilOpen` を **専用スレッド** で `count` 本走らせ、**ゲートが開いて戻った数**だけを
    /// `passed` に数える（塞ぐのを拒んで戻った分は数えない）。
    ///
    /// `DispatchQueue.global()` で走らせないこと。塞いでいる間そのワーカーが占有され、
    /// コア数の少ない環境では `open()` を出すテスト本体の再開自体が遅れる。実測:
    /// `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（プール幅 1）では 60 秒経っても開けられず
    /// このテスト自身が «unknown» の Issue を出し、CI（3〜4 コア）では 0.2 秒の sleep が
    /// 13.6 秒に伸びてその間ワーカー 3 本を塞いでいた。専用スレッドなら塞いでも
    /// ディスパッチ側の供給に影響しない。
    /// `entered` を渡すと、`wait` を呼ぶ直前に数える（待機に入った数を待てるようにする）。
    private func startWaiters(
        _ count: Int, on gate: BlockingGate, passed: LockedBox<Int>, entered: LockedBox<Int>? = nil
    ) {
        for _ in 0 ..< count {
            Thread.detachNewThread {
                entered?.update { $0 += 1 }
                guard gate.waitUntilOpen() else { return }
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
        let entered = LockedBox(0)
        startWaiters(3, on: gate, passed: passed, entered: entered)

        // 開ける前に通ってはならない。全員が wait の直前まで来てから数える
        // (素通ししてしまう実装なら、ポーリングで入場を観測するまでに通り抜けている)。
        await waitUntil { entered.get() == 3 }
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

    // MARK: - 塞いではいけない場所の検査（ADR 0012）

    // 場所の判定（`blockingHazard`）は待機から切り離して測る。待機そのものでメインスレッドを
    // 測ると、検査が外れた退行でメインスレッドが塞がり、失敗ではなくハングになる。

    @Test("協調スレッドプール上のタスクは塞いではいけない場所と判定する")
    func taskOnCooperativePoolIsHazardous() {
        // このスイートは MainActor に隔離していないので、本体は協調プール上のタスクで走る。
        #expect(BlockingGate.blockingHazard() != nil)
    }

    @Test("タスクの外でもメインスレッドは塞いではいけない場所と判定する")
    func mainThreadOutsideTaskIsHazardous() async {
        // メインキューのコールバックはタスクの上ではない。メインスレッドの判定だけが拾う。
        let hazard: String? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: BlockingGate.blockingHazard()) }
        }
        #expect(hazard != nil)
    }

    @Test("withBlockingWork の専用スレッドは塞いでよい場所と判定する")
    func blockingWorkThreadIsNotHazardous() async {
        #expect(await withBlockingWork { BlockingGate.blockingHazard() } == nil)
    }

    @Test("閉じたゲートをタスクの上で待つと、塞がずに失敗を記録して戻る")
    func closedGateRefusesToBlockInsideTask() async {
        let gate = BlockingGate()
        // 検査が外れた退行では下の Task が協調スレッドを塞ぐ。抜けるときに必ず解放する。
        defer { gate.open() }
        let result = LockedBox<Bool?>(nil)

        await withKnownIssue {
            Task { result.set(gate.waitUntilOpen()) }
            // 誰も開けていないのに戻ることで「塞いでいない」を測る。塞いでいれば
            // ここが予算切れになり、下の比較が nil で落ちる。
            await waitUntil { result.get() != nil }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("BlockingGate") }
        }

        #expect(result.get() == false)
    }

    @Test("開いたゲートはタスクの上でも素通しする")
    func openGatePassesInsideTask() {
        #expect(BlockingGate(isOpen: true).waitUntilOpen())
    }
}
