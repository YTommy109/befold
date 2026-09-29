import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// canvas(地)の所有者の判定と適用を検証する。
///
/// 既定では地の色は `ViewerTheme.canvas` が唯一の定義で WKWebView は透過だが、外部の
/// HTML 文書だけは例外でブラウザと同じく文書が canvas ごと所有する。透過のままだと、
/// 明るい背景を前提に文字色だけを指定した HTML がダークキャンバス上に載って読めなくなる
/// (TASK-511)。この対は enter / exit とセットで倒す必要があり、破れても
/// `RenderedStateMirror` の比較には現れないためここで直接押さえる。
@Suite(testTimeLimit())
struct ViewerCanvasOwnershipTests {
    @Test("外部のHTML文書だけがcanvasを所有する")
    func documentOwnsCanvasOnlyForHTMLDocuments() {
        #expect(ViewerWebViewFactory.documentOwnsCanvas(fileType: .html, isSourceMode: false))
        // ソース表示の HTML は befold がコードとして描くので該当しない。
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .html, isSourceMode: true))
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .markdown, isSourceMode: false))
        #expect(!ViewerWebViewFactory.documentOwnsCanvas(fileType: .mmd, isSourceMode: false))
    }

    /// 入る側（文書へ明け渡す）は `RenderSurfaceDispatchTests` が同じスタブ面で見ている。
    /// 実 WebView の `drawsBackground` へ届くことは
    /// `ViewerRendererOneShotIntegrationTests.loadOneShotReportsRejectForBinary` の 1 件で見る(TASK-662.2)。
    @Test("直接HTMLモードから復帰するとcanvasは透過へ戻る")
    @MainActor
    func exitRestoresTransparentCanvas() {
        let renderer = ViewerRenderer()
        let surface = ViewerRendererMessageStubs.Surface()
        renderer.surface = surface

        renderer.directHTML.exit(surface: surface) {}

        #expect(surface.documentOwnsCanvasHistory == [false])
    }
}
