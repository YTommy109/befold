import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 退場側のスクロール位置の保存は JS のラウンドトリップを挟むため非同期だが、
/// 入場側の提示開始は保存値を同期的に読む。A→B→A の素早い往復では
/// 「A の保存が完了する前に A の提示開始が走る」順序が起きて、古い位置を復元する。
/// 提示開始の契機は 3 つしかないため、遅れて完了した保存が拾い直されることもない(TASK-394)。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowScrollRestoreRaceTests {
    private let fileA = URL(fileURLWithPath: "/mock/a.md")
    private let fileB = URL(fileURLWithPath: "/mock/b.md")

    /// 位置の問い合わせを保留し、テストが任意の時点で完了させられるレンダラ。
    /// 実装は WKWebView の evaluateJavaScript コールバック(非同期)を模す。
    @MainActor
    private final class DeferredScrollRenderer: DocumentRendering {
        /// 未完了の問い合わせ。発行順に積み、テストが flush で完了させる。
        private var pending: [(Double) -> Void] = []
        /// 次に返す位置。問い合わせの発行時点の値を捕捉する(実際の scrollTop に相当)。
        var scrollPosition: Double = 0
        private var capturedPositions: [Double] = []

        var isDirectHTMLMode = false

        func applyZoom(_: Double) {}
        func applyCodeFont(family _: String?, points _: Double?) {}

        func applyCsvNumberFormat(grouping _: Bool, negativeStyle _: CsvNegativeStyle) {}
        func changeZoom(_: ZoomChange) -> Double? {
            nil
        }

        func openFind() {}
        func openJump(kind _: DocumentJumpKind) {}
        func applyJumpAvailability(_: Set<DocumentJumpKind>) {}
        func findNext() {}
        func findPrevious() {}
        func printDocument(over _: NSWindow?) {}
        func noteRename(from _: URL, to _: URL) {}

        var currentRotation: Int {
            0
        }

        func rotate(byDegrees _: Int) {}

        func currentScrollPosition(_ completion: @escaping (Double) -> Void) {
            capturedPositions.append(scrollPosition)
            pending.append(completion)
        }

        /// 保留中の問い合わせを発行順に完了させる。
        func flushPendingSaves() {
            let completions = pending
            let positions = capturedPositions
            pending = []
            capturedPositions = []
            for (completion, position) in zip(completions, positions) {
                completion(position)
            }
        }
    }

    private func makeFixture(
        renderer: DeferredScrollRenderer
    ) -> ViewerWindowControllerFixture {
        ViewerWindowControllerFixture(
            file: fileA, extraFiles: [fileB],
            prefix: "ViewerWindowScrollRestoreRace",
            documentRenderer: renderer
        )
    }

    @Test("A→B→A の往復中に完了した A の保存が、A のライブ復元値へ追いつく")
    func lateSaveCatchesUpLiveRestoreValueAfterRoundTrip() {
        let renderer = DeferredScrollRenderer()
        let fixture = makeFixture(renderer: renderer)
        let controller = fixture.controller
        defer { controller.close() }

        // A を 640 までスクロールした状態で A→B。保存要求は発行されるが完了しない。
        renderer.scrollPosition = 640
        controller.switchFile(to: fileB)
        // B→A。A の保存はまだ届いていないので、提示開始は古い記憶(0)を読む。
        renderer.scrollPosition = 0
        controller.switchFile(to: fileA)
        #expect(controller.fileURL == fileA)
        #expect(controller.store.scrollPositionToRestore == 0)

        // ここで A の保存(640)が完了する。
        renderer.flushPendingSaves()

        #expect(
            controller.documentPresenter.presentationMemory.scrollPosition(for: fileA, mode: .rendered) == 640
        )
        #expect(controller.store.scrollPositionToRestore == 640)
    }

    /// 追いつかせてよいのは「いま提示中の文書」の保存だけ。別文書の保存完了で
    /// ライブ復元値を書き換えると、次の再描画でこの窓が別文書の位置へ飛ぶ。
    @Test("いま提示していない文書の保存が完了しても、ライブ復元値は動かさない")
    func saveForAnotherDocumentDoesNotTouchLiveRestoreValue() {
        let renderer = DeferredScrollRenderer()
        let fixture = makeFixture(renderer: renderer)
        let controller = fixture.controller
        defer { controller.close() }

        // A を 640 までスクロールして A→B。B に居る間に A の保存が完了する。
        renderer.scrollPosition = 640
        controller.switchFile(to: fileB)
        #expect(controller.fileURL == fileB)

        renderer.flushPendingSaves()

        // A のキーへは記録されるが、提示中の B の復元値は動かない。
        #expect(
            controller.documentPresenter.presentationMemory.scrollPosition(for: fileA, mode: .rendered) == 640
        )
        #expect(controller.store.scrollPositionToRestore == 0)
    }
}
