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
/// 実際に階層へ現れるかどうかを数えて固定する。
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
            pdfViewProxy: PDFViewProxy(),
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

    private func displayState(fileType: FileType) -> ViewerContentState.DisplayState {
        ViewerContentState.DisplayState(
            fileType: fileType, contentHash: 1, chunkSession: nil, rejectReason: nil,
            isTruncated: false, content: fileType == .pdf ? "" : "# hi",
            data: fileType == .pdf ? Data("%PDF-".utf8) : nil,
            tracksLineCount: false, hasDeclaredHTMLCharset: nil
        )
    }

    @Test("PDF を開く窓では WKWebView が作られない")
    func doesNotBuildTheWebSurfaceForPDF() {
        let store = makeStore()

        let view = host(makeStack(store: store, opening: .pdf))

        #expect(webViewCount(in: view) == 0)
    }

    /// PDF 以外は従来どおり最初から面を持つ（遅延で描画が遅れないこと）。
    @Test("PDF 以外を開く窓では従来どおり WKWebView が作られる")
    func buildsTheWebSurfaceForOtherTypes() {
        let store = makeStore()

        let view = host(makeStack(store: store, opening: .markdown))

        #expect(webViewCount(in: view) == 1)
    }

    /// PDF → 他種別へ切り替えたら面が作られ、**PDF へ戻しても壊さない**
    /// （TASK-266 の「行を通過するたびに作り直さない」を保つ）。
    @Test("PDF から他種別へ移ると面が作られ、PDF へ戻しても残る")
    func createsTheSurfaceOnSwitchAndKeepsIt() async {
        let store = makeStore()
        let view = host(makeStack(store: store, opening: .pdf))
        #expect(webViewCount(in: view) == 0)

        store.contentState.finishLoading(url: URL(fileURLWithPath: "/files/a.md"))
        _ = store.contentState.applyDisplayState(displayState(fileType: .markdown))
        try? await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        #expect(webViewCount(in: view) == 1)

        store.contentState.finishLoading(url: URL(fileURLWithPath: "/files/b.pdf"))
        _ = store.contentState.applyDisplayState(displayState(fileType: .pdf))
        try? await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        #expect(webViewCount(in: view) == 1)
    }
}
