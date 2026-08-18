@testable import BefoldRenderKit
import Testing
import WebKit

/// ナビゲーション delegate は `webView.navigationDelegate` から weak で参照されるため、
/// コーディネータだけが生き残った状態でコールバックが届きうる。ViewerRenderer を
/// unowned で持っているとその時点でトラップしてプロセスごと落ちる(TASK-448 と同型。
/// CI の ThreadSanitizer ジョブが `swift_unownedRetainStrong` で signal 6 になった)。
@MainActor
struct ViewerNavigationCoordinatorLifetimeTests {
    /// コーディネータだけを残して renderer を解放し、各コールバックがトラップせず
    /// 素通りすることを確かめる。`renderer` を weak から unowned へ戻すと落ちる。
    @Test("ViewerRenderer が解放済みでも、ナビゲーション通知はトラップせず無視される")
    func navigationCallbacksStopWhenRendererIsReleased() {
        let webView = WKWebView(frame: .zero)
        let coordinator: ViewerNavigationCoordinator
        weak var releasedRenderer: ViewerRenderer?
        do {
            let renderer = ViewerRenderer()
            coordinator = renderer.navigationCoordinator
            releasedRenderer = renderer
        }
        #expect(releasedRenderer == nil, "renderer が解放されておらず、前提が成り立っていない")

        coordinator.webView(webView, didFinish: nil)
        coordinator.webView(webView, didFail: nil, withError: CancellationError())
        coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: CancellationError())
    }

    /// 表示先が無い以上、遷移は通さない。
    @Test("ViewerRenderer が解放済みなら、遷移の可否は .cancel を返す")
    func decidePolicyCancelsWhenRendererIsReleased() {
        let webView = WKWebView(frame: .zero)
        let coordinator: ViewerNavigationCoordinator
        do {
            let renderer = ViewerRenderer()
            coordinator = renderer.navigationCoordinator
        }

        var decided: WKNavigationActionPolicy?
        coordinator.webView(
            webView, decidePolicyFor: WKNavigationAction()
        ) { decided = $0 }
        #expect(decided == .cancel)
    }
}
