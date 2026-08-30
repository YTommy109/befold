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

    // MARK: - 復元待ちの消化（TASK-573）

    /// `PDFPreviewView.updateNSView` と同じ順序で差し替える。
    ///
    /// **文書の代入から始める。** レイアウト済みの面へ後から復元待ちを置いても
    /// `needsLayout` が立たず `layout()` が走らないため、本番と違う経路になる
    /// （文書の差し替えが `PDFViewDocumentChanged` を出して初めてレイアウトが起きる）。
    private func simulateSwitch(pageCount: Int, restore: Double) -> ZoomingPDFView {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = makeView(pageCount: pageCount).document
        PDFSurfaceLayout.apply(rotation: 0, to: pdfView)
        PDFSurfaceLayout.apply(zoom: 1.0, to: pdfView)
        pdfView.pendingRestoreFraction = restore
        pdfView.layoutSubtreeIfNeeded()
        return pdfView
    }

    /// **文書全体が面に収まるときも、復元待ちはそのレイアウトで使い切る。**
    ///
    /// 余地が出るまで待つ形にしていたため、スクロールの余地が生まれない文書
    /// （1 ページで収まる、など）では待ちが永久に残っていた（実測: 余地 −9.47 で
    /// `pendingRestoreFraction` が 3 回のレイアウト後も 0.0 のまま / TASK-573）。
    @Test("余地が無い文書でも復元待ちはレイアウトで消える")
    func consumesPendingRestoreWhenTheDocumentFits() {
        let pdfView = simulateSwitch(pageCount: 1, restore: 0.0)

        #expect(PDFSurfaceLayout.verticalScrollRoom(of: pdfView) <= 0) // 余地が無い文書
        #expect(pdfView.pendingRestoreFraction == nil)
    }

    /// **居残った復元待ちは、後から拡大した瞬間に発火して表示を飛ばす。**
    ///
    /// 余地が無いあいだ待ち続ける形だと、ユーザーが拡大して余地が生まれた
    /// そのレイアウトで、開いたときの記憶が突然適用される（実測: 修正前は
    /// 拡大しただけで表示位置が 0.0 → 1.0（末尾）へ飛んだ / TASK-573）。
    @Test("余地が無い文書を拡大しても、記憶していた位置へ飛ばない")
    func doesNotJumpWhenZoomingCreatesRoom() {
        let pdfView = simulateSwitch(pageCount: 1, restore: 1.0) // 末尾を記憶していた
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) < 0.01)

        PDFSurfaceLayout.apply(zoom: 3.0, to: pdfView) // ユーザーが拡大して余地が生まれる
        pdfView.needsLayout = true
        pdfView.layoutSubtreeIfNeeded()

        #expect(PDFSurfaceLayout.verticalScrollRoom(of: pdfView) > 0)
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) < 0.9)
    }

    /// 上の変更で、余地がある文書の復元が壊れていないこと（回帰の番人）。
    @Test("余地がある文書は同じレイアウトの中で位置まで復元される")
    func restoresPositionWithinTheSameLayout() {
        let pdfView = simulateSwitch(pageCount: 30, restore: 0.5)

        #expect(pdfView.pendingRestoreFraction == nil)
        #expect(abs(PDFSurfaceLayout.documentFraction(of: pdfView) - 0.5) < 0.01)
    }

    /// **面がまだ組み上がっていない間は待つ。** 文書が入る前のレイアウトで
    /// 使い切ってしまうと、記憶していた位置が黙って捨てられる。
    @Test("文書が入る前のレイアウトでは復元待ちを使い切らない")
    func keepsPendingRestoreUntilTheSurfaceIsReady() {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)

        pdfView.pendingRestoreFraction = 0.5
        pdfView.layoutSubtreeIfNeeded()

        #expect(pdfView.pendingRestoreFraction == 0.5)
    }
}
