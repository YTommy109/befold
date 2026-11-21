@testable import befold
import BefoldKit
import BefoldRenderKit
import Testing

/// レンダラへ渡す差分の状態(`DocumentSurfaceStack.rendererDiffState`)。
///
/// viewer は「レンダリング表示 + 差分あり」をレンダリング差分として描く(TASK-483)。
/// そのため差分は差分モードのときだけ渡り、通常のレンダリング表示には漏れてはならない。
@MainActor
struct DocumentSurfaceDiffStateTests {
    private let diff = ViewerDiffContent.diff("@@ -1 +1 @@\n-a\n+b\n")

    @Test("レンダリング表示とソース表示には差分を渡さない", arguments: [ViewerDisplayMode.rendered, .source])
    func noDiffOutsideDiffModes(mode: ViewerDisplayMode) {
        #expect(DocumentSurfaceStack.rendererDiffState(mode: mode, content: diff, layout: .inline) == .none)
    }

    /// レンダリング差分は isSourceMode が false のまま差分を受け取る(viewer はこの組み合わせを
    /// レンダリング差分として描く)。
    @Test("レンダリング差分ではソース表示にせず差分を渡す")
    func renderedDiffPassesDiffWithoutSourceMode() {
        let state = DocumentSurfaceStack.rendererDiffState(mode: .renderedDiff, content: diff, layout: .inline)
        #expect(state != .none)
        #expect(!ViewerDisplayMode.renderedDiff.isSourceMode)
    }

    @Test("ソース差分では差分を渡す")
    func sourceDiffPassesDiff() {
        #expect(DocumentSurfaceStack.rendererDiffState(mode: .diff, content: diff, layout: .inline) != .none)
    }
}
