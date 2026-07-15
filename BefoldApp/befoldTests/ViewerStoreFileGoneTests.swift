@testable import befold
import BefoldKit
import Foundation
import Testing

/// open() されるまで待機者をサスペンドさせるゲート。
/// スピン(yield ループ)ではなく continuation で待つため、並列実行中の
/// 他テストから CPU を奪わない。
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// ゲートを開き、待機中の全員を再開する。以後の wait() は即座に戻る。
    func open() {
        lock.lock()
        opened = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending {
            waiter.resume()
        }
    }

    /// ゲートが開くまでサスペンドする。
    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}

/// readNextChunk をゲートが開くまで待たせるモック(遅い読み込み・待機中の競合のシミュレート用)。
/// `entered` で待機開始を観測し、`gate.open()` で読み込みを完了させる。
private final class GatedChunkedReader: ChunkedTextReading, @unchecked Sendable {
    private let chunk: String
    let gate = AsyncGate()
    /// readNextChunk へ到達した(待機中である)ことの観測用。
    let entered = LockedBox(false)

    init(chunk: String) {
        self.chunk = chunk
    }

    func readNextChunk() async throws -> (text: String, isAtEnd: Bool) {
        entered.set(true)
        await gate.wait()
        return (chunk, true)
    }
}

/// 初回チャンクは即座に返し、2 回目の readNextChunk をゲートが開くまで待たせるモック。
private final class GatedSecondChunkReader: ChunkedTextReading, @unchecked Sendable {
    private let first: String
    private let second: String
    private let readCount = LockedBox(0)
    let gate = AsyncGate()
    /// 2 回目の readNextChunk へ到達した(待機中である)ことの観測用。
    let enteredSecondRead = LockedBox(false)

    init(first: String, second: String) {
        self.first = first
        self.second = second
    }

    func readNextChunk() async throws -> (text: String, isAtEnd: Bool) {
        let count = readCount.get() + 1
        readCount.set(count)
        if count == 1 { return (first, false) }
        enteredSecondRead.set(true)
        await gate.wait()
        return (second, true)
    }
}

/// 非同期読み込みの競合(世代交代・セッション交代)まわりのテスト。
@Suite
@MainActor
struct ViewerStoreLoadRaceTests {
    @Test("遅い読み込みが後続の openFile に追い越されたら結果を破棄する")
    func staleLoadIsDiscarded() async {
        let slowFile = URL(fileURLWithPath: "/files/slow.csv")
        let fastFile = URL(fileURLWithPath: "/files/fast.csv")
        let reader = InMemoryFileReader()
        reader.setFile("slow", at: slowFile)
        reader.setFile("fast", at: fastFile)
        let slowReader = GatedChunkedReader(chunk: "slow\n")
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { url, _ in
                if url.path == slowFile.path { return slowReader }
                return MockChunkedReader(chunks: ["fast\n"])
            }
        )
        store.openFile(slowFile)
        let slowTask = store.loadTask
        // 遅い読み込みが readNextChunk の待機に入ったのを確認してから 2 つ目を開く。
        await waitUntilYielding { slowReader.entered.get() }

        await openAndLoad(store, fastFile)
        #expect(store.content == "fast\n")

        // 遅い読み込みが完了しても、追い越された結果は表示へ反映されない。
        slowReader.gate.open()
        await slowTask?.value
        #expect(store.content == "fast\n")
        #expect(store.filePath == fastFile)
        #expect(store.isTruncated == false)

        store.close()
    }

    @Test("readNextChunk 待機中に再読込が走ったら古いセッションの結果を捨てる")
    func loadMoreLinesDropsResultAfterReload() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("old\nstale", at: file)
        let sessionA = GatedSecondChunkReader(first: "old\n", second: "stale\n")
        let isFirstFactoryCall = LockedBox(true)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in
                if isFirstFactoryCall.get() {
                    isFirstFactoryCall.set(false)
                    return sessionA
                }
                return MockChunkedReader(chunks: ["new\n"])
            }
        )
        await openAndLoad(store, file)
        #expect(store.content == "old\n")
        #expect(store.isTruncated == true)

        // 「続きを読み込む」を開始し、readNextChunk の待機に入るまで進める。
        let moreTask = Task { await store.loadMoreLines() }
        await waitUntilYielding { sessionA.enteredSecondRead.get() }

        // 待機中に再読込が走り、セッションが新しいものへ交代する。
        await openAndLoad(store, file)
        #expect(store.content == "new\n")

        // 古いセッションの読み込みが解決しても結果は捨てられ、新しい表示を壊さない。
        sessionA.gate.open()
        let result = await moreTask.value
        #expect(result == nil)
        #expect(store.content == "new\n")
        #expect(store.isTruncated == false)

        store.close()
    }
}

/// ファイル削除確定(グレース期間付き onFileGone)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
/// グレース期間の待機は TestClock を注入して仮想時刻で厳密に進めるため、実時間依存はなく
/// 通常どおり並列実行できる。
@Suite
@MainActor
struct ViewerStoreFileGoneTests {
    @Test
    func openNonexistentFileFiresOnFileGoneAfterGrace() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/missing.mmd")
        let store = makeStore(reader: InMemoryFileReader(), clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        // 読み込みタスクの完了(= scheduleFileGone 実行)を待ってから、
        // グレースタスクの sleep 登録を待つ(登録前 advance のレースを防ぐ)。
        await openAndLoad(store, file)
        await clock.waitForPendingSleepers(atLeast: 1)
        // グレース期間中は発火しない
        #expect(firedCount == 0)

        // 0.999 秒では未到達で発火しない
        clock.advance(by: .milliseconds(999))
        await yieldMainActor()
        #expect(firedCount == 0)

        // グレース期間 1 秒到達で発火する
        clock.advance(by: .milliseconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func openNonexistentFileDoesNotFireOnContentReloaded() async {
        let file = URL(fileURLWithPath: "/files/missing.mmd")
        let store = makeStore(reader: InMemoryFileReader())

        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, file)

        // ファイルが存在しない場合は scheduleFileGone() へ抜けるため、
        // 内容は確定せず onContentReloaded は発火しない。
        #expect(firedCount == 0)

        store.close()
    }

    @Test
    func watcherCallbackCancelsFileGoneOnRecreation() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        await openAndLoad(store, file)
        #expect(firedCount == 0)

        // ファイル削除 → コールバック発火でグレース期間開始。
        // 再読込タスクの完了(= scheduleFileGone 実行)を待ってから sleep 登録を待つ。
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        await clock.waitForPendingSleepers(atLeast: 1)

        // グレース期間内に再作成 → 再読込の適用でグレースタスクがキャンセルされ待機が消える
        reader.setFile("graph TD; C-->D", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        #expect(clock.pendingSleepCount == 0)

        // 10 秒進めても発火しない
        clock.advance(by: .seconds(10))
        await yieldMainActor()
        #expect(firedCount == 0)
        #expect(store.content == "graph TD; C-->D")

        store.close()
    }

    @Test
    func watcherCallbackFiresOnFileGoneAfterGracePeriod() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        await openAndLoad(store, file)

        // ファイル削除 → コールバック発火でグレース期間開始。
        // 再読込タスクの完了(= scheduleFileGone 実行)を待ってから sleep 登録を待つ。
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        await clock.waitForPendingSleepers(atLeast: 1)

        // 0.999 秒では未到達で発火しない
        clock.advance(by: .milliseconds(999))
        await yieldMainActor()
        #expect(firedCount == 0)

        // グレース期間 1 秒到達で発火する
        clock.advance(by: .milliseconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func fileGoneDetectionSurvivesRecreateAndRedelete() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        await openAndLoad(store, file)

        // 削除 → グレース期間開始(再読込タスクの完了を待ってから sleep 登録を待つ)
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        await clock.waitForPendingSleepers(atLeast: 1)

        // 監視イベントなしで再作成(発火直前の存在再確認だけで救済されるケース)。
        // グレース期間を過ぎてもファイルが存在するため発火せず、タスクは完了する。
        reader.setFile("graph TD; C-->D", at: file)
        clock.advance(by: .seconds(1))
        await yieldMainActor()
        #expect(firedCount == 0)
        // 完了済み(stale)タスクは待機を残していない
        #expect(clock.pendingSleepCount == 0)

        // 再削除 → 完了済みの stale タスクが検知を塞いでいないこと
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        await clock.waitForPendingSleepers(atLeast: 1)
        clock.advance(by: .seconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }
}
