import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF の面に重なる入力欄が、キーボードのフォーカスをちゃんと取り、閉じたら面へ返すこと。
///
/// **同じ穴が 2 回開いたので、構造で塞いだ側を押さえる（TASK-579）。** 1 回目はページ番号の
/// 入力欄（TASK-578.2）、2 回目は検索バーで、どちらも「SwiftUI の `TextField` +
/// `@FocusState` を置いた」という同じ書き方から生まれた。この面ではそれで first responder が
/// 移らない。両方を `FocusClaimingTextField` へ寄せたので、ここでは**寄せたことが外れて
/// いないか**と、**閉じたときの戻し先**を見る。
@MainActor
@Suite
struct PDFSurfaceTextFieldTests {
    private nonisolated(unsafe) static var hosted: [(ZoomingPDFView, NSWindow)] = []

    private final class SpyWindow: NSWindow {
        private(set) var requestedFirstResponder: NSResponder?

        func forgetRequests() {
            requestedFirstResponder = nil
        }

        override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
            requestedFirstResponder = responder
            return super.makeFirstResponder(responder)
        }
    }

    private struct Surface {
        let pdfView: ZoomingPDFView
        let window: SpyWindow
        let proxy: PDFViewProxy
    }

    private func makeDocument(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0 ..< pageCount {
            let data = NSMutableData()
            var box = NSRect(x: 0, y: 0, width: 612, height: 792)
            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { continue }
            context.beginPage(mediaBox: &box)
            context.endPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: index)
            }
        }
        return document
    }

    private func makeSurface() -> Surface {
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = pdfView
        Self.hosted.append((pdfView, window))
        pdfView.present(document: makeDocument(pageCount: 5), rotation: 0, zoom: 1.0, scrollFraction: 0)
        pdfView.layoutSubtreeIfNeeded()
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView
        return Surface(pdfView: pdfView, window: window, proxy: proxy)
    }

    /// フォーカス移動は `DispatchQueue.main.async` で 1 周遅れて走る。同じキューへ後から
    /// 積んだマーカーを待つことで、その 1 周が終わったことを決定的に判定する（FIFO）。
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - 閉じたら面へ戻す

    /// 検索バーを閉じたら面へ戻す。戻さないと、閉じた直後にスペースや矢印で
    /// PDF を送れない（入力欄が消えて first responder が宙に浮く / TASK-579）。
    @Test("検索バーを閉じるとフォーカスが面へ戻る")
    func closingTheFindBarFocusesTheSurface() async {
        let surface = makeSurface()
        let model = PDFFindModel(pdfViewProxy: surface.proxy, caseSensitive: { false })
        model.open()
        surface.window.forgetRequests()

        model.close()
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder === surface.pdfView)
    }

    /// **文書の差し替えではフォーカスを動かさない。** サイドバーを矢印で流し読みして
    /// いる最中に奪うと、次の矢印が一覧へ届かなくなる（TASK-581 で実際に起きた回帰）。
    /// 検索バー側の経路が同じ穴を開けないことを押さえる。
    @Test("文書が差し替わってもフォーカスは動かない")
    func documentChangeDoesNotFocusTheSurface() async {
        let surface = makeSurface()
        let model = PDFFindModel(pdfViewProxy: surface.proxy, caseSensitive: { false })
        model.open()
        surface.window.forgetRequests()

        model.documentChanged()
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder == nil)
    }

    // MARK: - 面へ戻す口が 1 つであること

    /// 戻し先の実体は `PDFViewProxy.focusSurface()` に 1 つだけ置く。ページ番号側も
    /// 検索側もここを通るので、面が消えているときの扱いが 2 通りに割れない。
    @Test("面がまだ無いときに呼んでも落ちない")
    func focusingWithoutASurfaceIsSafe() async {
        let proxy = PDFViewProxy()

        proxy.focusSurface()
        await drainMainQueue()

        #expect(proxy.pdfView == nil)
    }

    @Test("focusSurface は面へフォーカスを要求する")
    func focusSurfaceRequestsThePDFView() async {
        let surface = makeSurface()
        surface.window.forgetRequests()

        surface.proxy.focusSurface()
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder === surface.pdfView)
    }
}
