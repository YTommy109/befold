@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 準備完了ゲートの保留スロットを検証する(TASK-446)。
///
/// 保留を 1 スロットで持つと、直接 HTML ロードの失敗で走る viewer.html 読み直しが、
/// その間に積まれた別ファイルの描画要求を上書きして消してしまう。以後 SwiftUI 側の値は
/// 変わらず updateContent を呼び直す契機が無いため、空の viewer.html のまま残る。
@Suite(testTimeLimit())
@MainActor
struct ViewerReadinessGateTests {
    @Test("保留が複数積まれても、準備完了で積まれた順に全て実行される")
    func runsAllPendingWorkInOrder() {
        let gate = ViewerReadinessGate()
        var log: [String] = []

        gate.markNotReady()
        gate.run { log.append("first") }
        gate.run { log.append("second") }
        #expect(log.isEmpty)

        gate.markReady()

        #expect(log == ["first", "second"])
    }

    @Test("実行中に積み直された保留は、この場では流さず次の準備完了まで持ち越す")
    func requeuedWorkIsDeferredToNextReady() {
        let gate = ViewerReadinessGate()
        var log: [String] = []

        gate.markNotReady()
        gate.run {
            log.append("first")
            // 保留の実行中に viewer.html を読み直す(exit → reloadViewerHTML)形。
            gate.markNotReady()
            gate.run { log.append("requeued") }
        }
        gate.markReady()
        #expect(log == ["first"])

        gate.markReady()

        #expect(log == ["first", "requeued"])
    }

    /// 直接 HTML ロード中に別ファイルへ切り替え、元のナビゲーションが失敗する経路。
    /// 失敗時の viewer.html 読み直しが保留中の描画要求を消してはならない。
    @Test("直接HTMLロードの失敗で読み直しても、保留中の描画要求は失われない")
    func navigationFailureKeepsPendingRender() {
        let renderer = ViewerRenderer()
        let webView = WKWebView()
        renderer.webView = webView
        renderer.directHTML.simulateForTesting(
            active: true, lastPath: URL(fileURLWithPath: "/tmp/task446-direct.html")
        )
        renderer.readiness.markNotReady()

        // 直接ロードの完了を待つ間に別ファイルへ切り替わり、描画要求が保留される。
        var didRender = false
        renderer.runWhenReady { didRender = true }

        // 直接ロードが失敗する(ファイル削除・policy cancel 由来の中断など)。
        renderer.webView(webView, didFail: nil, withError: URLError(.cancelled))
        #expect(didRender == false)

        // 読み直した viewer.html のロードが完了した。
        renderer.readiness.markReady()

        #expect(didRender)
    }
}
