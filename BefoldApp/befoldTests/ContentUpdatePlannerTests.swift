import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// ContentUpdatePlanner の純粋判定のうち、差分未確定(pending)中の見送り規則を固定する
/// (TASK-407)。未確定の間、モード切替だけの入力は .skip で前の表示を残し、
/// コンテンツ自体が変わる入力(初回描画・ファイル切替・内容更新)は従来どおり描画へ進む。
@Suite(testTimeLimit())
struct ContentUpdatePlannerTests {
    private static let truncation = TruncationState(isTruncated: false, lineCount: 0, failed: false)
    private static let file = URL(fileURLWithPath: "/tmp/task407/doc.md")

    private static func makeInput(
        contentRevision: Int = 1,
        filePath: URL = file,
        isSourceMode: Bool = true,
        diffState: DiffState
    ) -> ContentUpdateInput {
        ContentUpdateInput(
            content: "# doc", contentRevision: contentRevision, fileType: .markdown,
            filePath: filePath, hasDeclaredHTMLCharset: nil, isSourceMode: isSourceMode,
            showLineNumbers: false, truncation: truncation, generation: 1, diffState: diffState
        )
    }

    /// レンダリング表示を描画済みのミラー(差分表示へ切り替える直前の状態)。
    private static func renderedMirror(
        isSourceMode: Bool = false,
        diffState: DiffState = .none
    ) -> RenderedStateMirror {
        RenderedStateMirror(
            contentRevision: 1, fileType: .markdown, filePath: file,
            showLineNumbers: false, isSourceMode: isSourceMode,
            truncation: truncation, diffState: diffState
        )
    }

    private static func plan(
        _ input: ContentUpdateInput, rendered: RenderedStateMirror, isDirectHTMLActive: Bool = false
    ) -> UpdatePlan {
        ContentUpdatePlanner.plan(
            input: input, rendered: rendered, pendingAppend: nil,
            isDirectHTMLActive: isDirectHTMLActive, features: .allEnabled
        )
    }

    @Test("未確定の間、モード切替だけの入力は見送って前の表示を残す")
    func pendingSkipsModeOnlyChange() {
        let plan = Self.plan(
            Self.makeInput(isSourceMode: true, diffState: .pending),
            rendered: Self.renderedMirror(isSourceMode: false)
        )
        #expect(plan == .skip)
    }

    @Test("ソース表示からの切替も未確定の間は見送る")
    func pendingSkipsWhenAlreadyInSourceMode() {
        let plan = Self.plan(
            Self.makeInput(isSourceMode: true, diffState: .pending),
            rendered: Self.renderedMirror(isSourceMode: true)
        )
        #expect(plan == .skip)
    }

    @Test("未確定でも内容が変わった入力は描画へ進む")
    func pendingRendersWhenContentChanged() {
        let plan = Self.plan(
            Self.makeInput(contentRevision: 2, diffState: .pending),
            rendered: Self.renderedMirror()
        )
        #expect(plan.isRender)
    }

    @Test("未確定でもファイルが変わった入力は描画へ進む")
    func pendingRendersWhenFileChanged() {
        let plan = Self.plan(
            Self.makeInput(filePath: URL(fileURLWithPath: "/tmp/task407/other.md"), diffState: .pending),
            rendered: Self.renderedMirror()
        )
        #expect(plan.isRender)
    }

    @Test("未確定でも未描画(空のミラー)なら描画へ進む")
    func pendingRendersOnEmptyMirror() {
        let plan = Self.plan(
            Self.makeInput(diffState: .pending),
            rendered: RenderedStateMirror()
        )
        #expect(plan.isRender)
    }

    /// HTML の .rendered は直接 HTML モードで表示されるため、切替は exitDirectThenRender
    /// 分岐を通る。見送りがその分岐より前に無いと、HTML ファイルだけ中間描画が残る。
    @Test("直接HTMLモード中でも未確定のモード切替は見送る")
    func pendingSkipsWhileDirectHTMLActive() {
        let plan = Self.plan(
            Self.makeInput(isSourceMode: true, diffState: .pending),
            rendered: Self.renderedMirror(isSourceMode: false),
            isDirectHTMLActive: true
        )
        #expect(plan == .skip)
    }

    @Test("差分が確定した入力は一度の描画で反映される")
    func resolvedDiffRenders() {
        let diff = DiffState(text: "@@ -1 +1 @@\n-old\n+new\n", layout: .inline)
        let plan = Self.plan(
            Self.makeInput(isSourceMode: true, diffState: diff),
            rendered: Self.renderedMirror(isSourceMode: false)
        )
        #expect(plan.isRender)
    }

    @Test("差分なしと確定した入力はプレーンなソース表示を描画する")
    func resolvedUnavailableRenders() {
        let plan = Self.plan(
            Self.makeInput(isSourceMode: true, diffState: .none),
            rendered: Self.renderedMirror(isSourceMode: false)
        )
        #expect(plan.isRender)
    }
}

private extension UpdatePlan {
    /// 全文 render かどうか(付随する RenderRequest の中身はここでは問わない)。
    var isRender: Bool {
        if case .render = self { return true }
        return false
    }
}
