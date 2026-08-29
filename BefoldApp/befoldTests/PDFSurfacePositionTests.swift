import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import PDFKit
import Testing

/// PDF の表示位置の記憶（TASK-564.3 / 換算は TASK-567 で連続スクロール前提へ）。
///
/// **PDF 専用の記憶機構は作らない。** 位置は「文書全体に対する 0…1」という
/// web の面と同じ意味の値へ畳み、`WindowPresentationMemory`（窓の生存期間だけの
/// 記憶）の既存の表へそのまま乗せる。
@MainActor
@Suite
struct PDFSurfacePositionTests {
    private func makeView(pageCount: Int) -> ZoomingPDFView {
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
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        return pdfView
    }

    private func index(of pdfView: PDFView) -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page)
    }

    /// **0 が先頭・1 が末尾**。`PDFView` のスクロール座標は下へ行くほど y が
    /// 小さいので、この向きは web の面と揃えるために反転させてある。
    /// これが破れると位置の記憶が上下逆になり、スペースキーの送り方向も逆になる。
    @Test("表示位置は 0 が先頭、1 が末尾を指す")
    func fractionPointsFromTopToBottom() {
        let pdfView = makeView(pageCount: 4)

        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) < 0.01)

        pdfView.goToLastPage(nil)
        pdfView.layoutSubtreeIfNeeded()
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) > 0.99)
    }

    /// 位置は「文書全体の 1 本のスクロール」として測る。web の面と同じ式
    /// (スクロール量 / 余地)で、ページ番号は混ぜない(TASK-567)。
    @Test("表示位置は文書全体に対する 0…1 で表され、往復で同じ位置へ戻る")
    func positionRoundTripsThroughAFraction() {
        let pdfView = makeView(pageCount: 4)
        PDFSurfaceLayout.restore(fraction: 0.5, in: pdfView)
        let saved = PDFSurfaceLayout.documentFraction(of: pdfView)
        let page = pdfView.currentPage

        PDFSurfaceLayout.restore(fraction: 0, in: pdfView)
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) < 0.01)
        PDFSurfaceLayout.restore(fraction: saved, in: pdfView)

        #expect(abs(saved - 0.5) < 0.01)
        #expect(abs(PDFSurfaceLayout.documentFraction(of: pdfView) - saved) < 0.01)
        #expect(pdfView.currentPage === page)
    }

    /// ファイルが更新されてページ数が減っても、余地の割合で復元するので行き先は
    /// 必ず文書の中に収まる（AC #4）。ページ番号で丸める分岐は要らない。
    @Test("ページ数が減っても末尾を超えない")
    func clampsWhenThePageDisappears() {
        let wide = makeView(pageCount: 10)
        PDFSurfaceLayout.restore(fraction: 1, in: wide)
        let saved = PDFSurfaceLayout.documentFraction(of: wide)

        let narrow = makeView(pageCount: 2)
        PDFSurfaceLayout.restore(fraction: saved, in: narrow)

        // 余地の割合で復元するので、行き先は必ず文書の中（末尾）に収まる。
        #expect(abs(PDFSurfaceLayout.documentFraction(of: narrow) - 1) < 0.01)
    }

    @Test("先頭・末尾・範囲外の値でも破綻しない")
    func handlesEdgeFractions() {
        let pdfView = makeView(pageCount: 3)

        for fraction in [-1.0, 0, 0.999, 1, 5] {
            PDFSurfaceLayout.restore(fraction: fraction, in: pdfView)
            let current = index(of: pdfView)
            #expect(current != nil)
            #expect((current ?? -1) >= 0 && (current ?? -1) <= 2)
            let landed = PDFSurfaceLayout.documentFraction(of: pdfView)
            #expect(landed >= 0 && landed <= 1)
        }
    }

    /// PDF の位置は窓の生存期間だけの記憶に乗り、`UserDefaults` へは書かれない（AC #3）。
    /// PDF 専用のストアを新設すると、この規則が PDF だけ破れる形になる。
    @Test("PDF の表示位置は UserDefaults へ書かれない")
    func positionNeverReachesUserDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "PDFSurfacePositionTests")
        let before = defaults.dictionaryRepresentation().keys.sorted()
        let memory = WindowPresentationMemory()
        let pdf = URL(fileURLWithPath: "/files/doc.pdf")

        memory.setScrollPosition(0.5, for: pdf, mode: .rendered)

        #expect(memory.scrollPosition(for: pdf, mode: .rendered) == 0.5)
        #expect(defaults.dictionaryRepresentation().keys.sorted() == before)
        // 窓が閉じれば消える(新しいインスタンスは何も覚えていない)。
        #expect(WindowPresentationMemory().scrollPosition(for: pdf, mode: .rendered) == 0)
    }

    /// 文書が無い面へ復元しても落ちない（切替直後の一瞬）。
    @Test("文書が無ければ復元は何もしない")
    func doesNothingWithoutADocument() {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)

        PDFSurfaceLayout.restore(fraction: 0.5, in: pdfView)

        #expect(pdfView.currentPage == nil)
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) == 0)
    }
}
