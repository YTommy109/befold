@testable import befold
import BefoldKit
import BefoldPDFProbe
import BefoldTestSupport
import Foundation
import Testing

/// 読み込みの**開始**がメインアクターの空きに依存しないこと（TASK-571）。
///
/// `@MainActor` の文脈で `Task {}` を作るとアクターを継承するため、切り替えで積まれた
/// 他の仕事（サイドバー同期・ツールバー更新・SwiftUI 再評価）が捌けるまで**読み込みが
/// 開始すらしない**。実測（2026-09-01・窓内でのファイル切り替え）ではこの待ちが
/// 13〜21ms で、読み込みの実処理（1〜4ms）の 4〜15 倍だった。
///
/// **これは書き方の約束なので、テストで固定しないと無言で戻る。**
/// `ViewerStore.startLoad` を `@MainActor` にする、あるいは `Task {}` を `loadContent` の
/// 中へ書き戻すと、このスイートが落ちる。
@Suite
struct ViewerStoreLoadStartTests {
    /// 読み込みが「始まった」ことを、パイプラインが実際に読みに来たかで見る。
    /// メインアクターを塞いだまま待てるよう、隔離を持たない箱で受け渡す。
    private final class StartSignal: @unchecked Sendable {
        private let condition = NSCondition()
        private var started = false

        func markStarted() {
            condition.lock()
            defer { condition.unlock() }
            started = true
            condition.broadcast()
        }

        /// 開始を**呼び出したスレッドを塞いだまま**待つ。期限は回数ではなく時刻で切る。
        func waitUntilStarted(before deadline: Date) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            while !started, condition.wait(until: deadline) {}
            return started
        }
    }

    /// 呼ばれたことだけを記録する `FileReading`。パイプラインは最初に
    /// `fileExists(at:)` を呼ぶので、ここが呼ばれた時点で「読み込みが始まった」と言える。
    private struct SignallingFileReader: FileReading {
        let signal: StartSignal

        func fileExists(at url: URL) -> Bool {
            signal.markStarted()
            // false を返すとパイプラインはそこで `.missing` を返して終わる。
            // 測りたいのは「始まったか」だけなので、以降の I/O は起こさない。
            return false
        }

        func isDirectory(at url: URL) -> Bool {
            false
        }

        func isExistingFile(at url: URL) -> Bool {
            false
        }

        func readString(from url: URL) throws -> String {
            ""
        }

        func readData(from url: URL) throws -> Data {
            Data()
        }

        func isBinary(at url: URL) -> Bool {
            false
        }

        func fileSize(at url: URL) -> Int? {
            nil
        }

        func modificationDate(at url: URL) -> Date? {
            nil
        }
    }

    /// **メインアクターを塞いだまま読み込みが始まる。**
    ///
    /// メインアクターを占有する側から `startLoad` を呼び、占有したまま開始を待つ。
    /// 開始が MainActor の空きを待つ実装だと、ここで永久に始まらず `.timeLimit` で落ちる。
    @Test(testTimeLimit())
    @MainActor
    func loadStartsWhileTheMainActorIsBusy() {
        let signal = StartSignal()
        let task = ViewerLoadStarter.start(
            ViewerLoadPipeline.Inputs(
                resolved: URL(fileURLWithPath: "/mock/does-not-matter.md"),
                fileType: .markdown,
                fileReader: SignallingFileReader(signal: signal),
                contentLoader: ContentLoader(),
                chunkedReaderFactory: ViewerLoadPipeline.defaultChunkedReaderFactory,
                isPDFReadable: PDFDataProbe.isReadable
            ),
            apply: { _ in }
        )
        defer { task.cancel() }

        // **await しない。** メインアクターを手放すと「空きを待つ実装」でも通ってしまい、
        // 守りたい性質を測れなくなる。塞いだまま、開始が届くのを待つ。
        //
        // 期限は時刻で切る（TASK-622）。かつては 20 万回の空ループ（数 ms）で待っており、
        // フル実行で協調プールが混むと開始が届く前にループが尽きて落ちた。空回しは
        // プール側の CPU も奪うので、条件変数で眠って待つ。
        let deadline = Date(timeIntervalSinceNow: testTimeoutSeconds(fallback: 10))
        #expect(
            signal.waitUntilStarted(before: deadline),
            "メインアクターを塞いだままでは読み込みが始まらなかった"
        )
    }
}
