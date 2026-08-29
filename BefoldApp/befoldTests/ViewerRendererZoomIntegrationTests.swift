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
    private static let truncation = ViewerRenderer.TruncationState(
        isTruncated: false, lineCount: 1, failed: false
    )

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
        #expect(renderer.pageZoom.applied == 1.5)
    }

    /// **倍率は代入では当たらず、その文書が描かれるときに当たる。**
    ///
    /// ホストはファイルを切り替えた時点で新しいファイルの倍率を流し込むが、その瞬間に
    /// 画面へ出ているのはまだ前のファイル（面の宛先は描画が確定した種別で切り替わる）。
    /// 代入で即座に当てると、切り替わる前のファイルの倍率が変わってから新しい
    /// ファイルが出る、というちらつきになる（TASK-567 の実測）。
    @Test("倍率は代入では当たらず、次に描かれるときに当たる")
    func appliesZoomWhenTheDocumentIsRendered() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        renderer.isVisible = true
        await waitUntilReady(renderer)
        #expect(renderer.pageZoom.applied == 1.0)

        // 切り替え先の倍率が流し込まれた直後。まだ前の文書が出ているので当てない。
        renderer.initialPageZoom = 0.75
        #expect(renderer.pageZoom.applied == 1.0)

        // 新しい内容が描かれると、内容と同じ区間で当たる。
        renderer.updateContent(
            "# hello", contentRevision: 1, fileType: .markdown,
            filePath: URL(fileURLWithPath: "/files/a.md"), hasDeclaredHTMLCharset: nil,
            isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        for _ in 0 ..< 200 where renderer.pageZoom.applied != 0.75 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(renderer.pageZoom.applied == 0.75)
    }

    /// **切り替え直後の `updateContent` は前のファイルに対する `.skip` である。**
    /// そこで当てると、まだ画面に出ている前のファイルの倍率が変わる（TASK-567 の実測。
    /// PDF へ切り替えるときに「Markdown の倍率が変わってから PDF が出る」形で見えた）。
    @Test("内容に差が無い更新では倍率を当てない")
    func doesNotApplyZoomWhenNothingIsRedrawn() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        renderer.isVisible = true
        await waitUntilReady(renderer)
        let file = URL(fileURLWithPath: "/files/a.md")

        renderer.updateContent(
            "# hello", contentRevision: 1, fileType: .markdown, filePath: file,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        for _ in 0 ..< 200 where renderer.rendered.contentRevision != 1 {
            try? await Task.sleep(for: .milliseconds(25))
        }

        // 切り替え先の倍率が流し込まれ、同じ内容でもう一度呼ばれた状態を模す。
        renderer.initialPageZoom = 0.5
        renderer.updateContent(
            "# hello", contentRevision: 1, fileType: .markdown, filePath: file,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        try? await Task.sleep(for: .milliseconds(100))

        #expect(renderer.pageZoom.applied == 1.0)
    }

    @Test("同じ倍率を流し込んでも再適用はしない")
    func doesNotReapplyIdenticalZoom() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.25, findOptionsPreference: nil)
        await waitUntilReady(renderer)
        #expect(renderer.pageZoom.applied == 1.25)

        renderer.pageZoom.invalidateApplied()
        renderer.initialPageZoom = 1.25
        // 代入では当たらないので、記録は捨てたまま。
        #expect(renderer.pageZoom.applied == nil)
    }
}
