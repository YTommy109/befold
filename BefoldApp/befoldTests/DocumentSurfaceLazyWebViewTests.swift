import AppKit
@testable import befold
import BefoldKit
import BefoldRenderKit
import BefoldTestSupport
import SwiftUI
import Testing
import WebKit

/// **PDF だけを開いた窓では WKWebView を作らない**（TASK-564.7）。
///
/// 破れても画面は正しいまま（速いか遅いかの差にしかならない）ので、
/// 判定を純関数で固定し、階層へ現れないことを PDF の 1 件で数える。
@MainActor
@Suite
struct DocumentSurfaceLazyWebViewTests {
    private static var retained: [NSView] = []

    private func makeStack(store: ViewerStore, opening: FileType) -> DocumentSurfaceStack {
        let defaults = makeIsolatedDefaults(prefix: "DocumentSurfaceLazyWebViewTests")
        return DocumentSurfaceStack(
            store: store,
            openingFileType: opening,
            isVisible: true,
            findOptionsPreference: FindOptionsPreference(defaults: defaults),
            headingJump: HeadingJumpLevelDefaults(defaults: defaults).binding,
            codeFontFamily: nil,
            codeFontSizePoints: nil,
            csvGrouping: true,
            csvNegativeStyle: .plain,
            rendererDelegate: WeakRendererDelegate(nil),
            webViewProxy: WebViewProxy(),
            pdfFind: PDFFindModel(pdfViewProxy: PDFViewProxy(), caseSensitive: { false }),
            pdfViewProxy: PDFViewProxy(),
            pdfPageIndicator: PDFPageIndicatorModel(pdfViewProxy: PDFViewProxy()),
            pdfActions: PDFSurfaceActions(onZoomChanged: { _ in }, onRotate: { _ in }),
            diffDisplayPreference: DiffDisplayPreference(defaults: defaults)
        )
    }

    private func host(_ stack: DocumentSurfaceStack) -> NSView {
        let view = NSHostingView(rootView: stack)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutSubtreeIfNeeded()
        Self.retained.append(view)
        return view
    }

    private func webViewCount(in view: NSView) -> Int {
        (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + webViewCount(in: $1) }
    }

    private func makeStore() -> ViewerStore {
        ViewerStore(defaults: makeIsolatedDefaults(prefix: "DocumentSurfaceLazyWebViewTests"))
    }

    /// 配線の確認は 1 件だけ実階層で見る。判定そのものは下の純関数テストが持つ
    /// （実 WKWebView を生成して固定時間待っていた旧テストの置き換え。TASK-662.2）。
    @Test("PDF を開く窓では WKWebView が作られない")
    func doesNotBuildTheWebSurfaceForPDF() {
        let store = makeStore()

        let view = host(makeStack(store: store, opening: .pdf))

        #expect(webViewCount(in: view) == 0)
    }

    @Test(
        "面が要るかは、作成済みか・着地した種別（未着地なら開く対象）が PDF 以外かで決まる",
        arguments: [
            // 未着地: 開く対象の種別で判断する。
            (false, FileType?.none, FileType.pdf, false),
            (false, nil, .markdown, true),
            // 着地後は着地した種別が唯一の情報源（開く対象が古くても影響しない）。
            (false, .markdown, .pdf, true),
            (false, .pdf, .markdown, false),
            // 一度作った面は PDF へ戻しても壊さない（TASK-266）。
            (true, .pdf, .pdf, true),
            (true, nil, .pdf, true),
        ]
    )
    func needsWebSurface(hasWebSurface: Bool, landed: FileType?, opening: FileType, expected: Bool) {
        #expect(
            DocumentSurfaceStack.needsWebSurface(
                hasWebSurface: hasWebSurface, landedFileType: landed, openingFileType: opening
            ) == expected
        )
    }
}
