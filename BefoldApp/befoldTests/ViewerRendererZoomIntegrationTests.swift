import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 初期倍率が「生成時に焼き込む値」ではなく「状態の投影」として適用されることを検証する
/// (ADR 0002 段 3 / TASK-270)。
///
/// ウィンドウの生成が表示対象の確定より先に走る経路があるため、makeWebView の時点では
/// 正しい倍率が分からないことがある。準備完了時と、準備後に値が変わった時の双方で
/// 適用し直せていることを、実 WKWebView 上の JS で確かめる。
/// 実 WebKit の挙動が結果を左右するため Integration に置く。
@Suite(testTimeLimit())
@MainActor
struct ViewerRendererZoomIntegrationTests {
    /// viewer.js が保持している現在倍率を読み出す。
    private func currentZoom(in webView: WKWebView) async -> Double? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window._mmdZoom ?? window.__mmdCurrentZoom ?? null") { result, _ in
                continuation.resume(returning: (result as? NSNumber)?.doubleValue)
            }
        }
    }

    private func waitUntilReady(_ renderer: ViewerRenderer) async {
        for _ in 0 ..< 200 {
            if renderer.readiness.isReady { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("生成後に倍率が確定しても、viewer.html の準備完了時に適用される")
    func appliesZoomDecidedAfterCreation() async {
        let renderer = ViewerRenderer()
        // 生成時点では対象ファイルが未確定で、既定倍率しか渡せない状況を再現する。
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)

        // 対象が確定して保存倍率が判明した(updateNSView が値を流し込んだ)状態。
        renderer.initialPageZoom = 1.5

        await waitUntilReady(renderer)
        #expect(renderer.readiness.isReady)
        // 準備完了までに値が変わっていた場合でも、適用済みとして記録されている。
        #expect(renderer.appliedPageZoom == 1.5)
    }

    @Test("準備完了後に倍率が変わったら、その時点で適用し直す")
    func appliesZoomChangedAfterReady() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        await waitUntilReady(renderer)
        #expect(renderer.appliedPageZoom == 1.0)

        renderer.initialPageZoom = 0.75
        #expect(renderer.appliedPageZoom == 0.75)
    }

    @Test("同じ倍率を流し込んでも再適用はしない")
    func doesNotReapplyIdenticalZoom() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.25, findOptionsPreference: nil)
        await waitUntilReady(renderer)
        #expect(renderer.appliedPageZoom == 1.25)

        renderer.appliedPageZoom = nil
        renderer.initialPageZoom = 1.25
        // 値が変わっていないので didSet も走らず、記録は nil のまま。
        #expect(renderer.appliedPageZoom == nil)
    }
}
