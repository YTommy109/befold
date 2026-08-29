import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF の面のレイアウト規則(TASK-564.2)。
///
/// `PDFView` は窓が無くても生成でき、`displayMode` / `autoScales` / `scaleFactor` /
/// `currentPage` は実測できる。描画そのものは目視の対象だが、**設定が入っているか**は
/// ここで固定する。
@MainActor
@Suite
struct PDFSurfaceLayoutTests {
    /// ページごとにサイズが違い、横長ページを含む文書。AC #4 の形。
    private func makeView(pageSizes: [NSSize] = [NSSize(width: 612, height: 792)]) -> PagingPDFView {
        let document = PDFDocument()
        for (index, size) in pageSizes.enumerated() {
            let data = NSMutableData()
            var box = NSRect(origin: .zero, size: size)
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
        let pdfView = PagingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        return pdfView
    }

    /// 2 ページの端が同時に見える位置で止まらないことは、止め方ではなく
    /// **1 ページずつしか描かない**という構造で守る。
    @Test("面は 1 ページずつ描く設定になっている")
    func surfaceShowsASinglePage() {
        let pdfView = makeView()

        #expect(pdfView.displayMode == .singlePage)
    }

    /// 開いた直後はページ全体が収まって見える(AC #1)。
    @Test("開いた直後はページ全体が収まる倍率になる")
    func opensFittedToThePage() {
        let pdfView = makeView()

        #expect(pdfView.autoScales)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
    }

    /// 倍率 1.0 の意味が面の生成側と操作側で 1 つであること。
    /// 拡大したら追従をやめ、既定倍率へ戻したら追従を再開する(⌘0 = フィットへ戻す)。
    @Test("拡大で自動追従を外し、既定倍率へ戻すと追従が戻る")
    func zoomingLeavesAndRestoresAutoScaling() {
        let pdfView = makeView()
        let fit = PDFSurfaceLayout.fitScale(of: pdfView)

        PDFSurfaceLayout.apply(zoom: 2, to: pdfView)
        #expect(!pdfView.autoScales)
        #expect(abs(pdfView.scaleFactor - fit * 2) < 0.0001)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 2) < 0.0001)

        PDFSurfaceLayout.apply(zoom: ZoomStore.defaultZoom, to: pdfView)
        #expect(pdfView.autoScales)
    }

    /// ページごとにサイズが違う PDF・横長ページを含む PDF でも、
    /// 各ページで全体が収まる(AC #4)。`autoScales` が表示中のページに追従する。
    @Test("ページサイズが混在していても各ページが収まる")
    func fitsEveryPageWhenSizesDiffer() {
        let pdfView = makeView(pageSizes: [
            NSSize(width: 612, height: 792), // 縦長
            NSSize(width: 792, height: 612), // 横長
            NSSize(width: 300, height: 300), // 小さい正方形
        ])

        for _ in 0 ..< 3 {
            #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
            pdfView.goToNextPage(nil)
            pdfView.layoutSubtreeIfNeeded()
        }
    }

    /// ページが 1 枚だけの PDF でページを送っても破綻しない(AC #4)。
    /// `PDFView` が端で止めるので、こちらで枚数を数える必要は無い。
    @Test("1 ページだけの PDF でページ送りしても破綻しない")
    func singlePageDocumentStaysOnItsOnlyPage() {
        let pdfView = makeView()
        let only = pdfView.currentPage

        pdfView.goToNextPage(nil)
        pdfView.goToPreviousPage(nil)

        #expect(pdfView.currentPage === only)
    }

    /// ページ全体が見えている間はスクロールの余地が無く、ホイールはページ送りへ
    /// 振り替わる。余地の有無で分けるのがその判定(TASK-564.2 の B2)。
    @Test("フィット表示ではページ内スクロールの余地が無い")
    func hasNoScrollRoomWhileFitted() {
        let pdfView = makeView()

        #expect(!pdfView.hasScrollRoom)
    }

    /// 拡大するとページ内に余地が生まれ、ホイールは通常のスクロールへ戻る。
    /// ページ内を見終わる前に次ページへ飛ばさないための分かれ目。
    @Test("拡大するとページ内スクロールの余地が生まれる")
    func gainsScrollRoomWhenZoomedIn() {
        let pdfView = makeView()

        PDFSurfaceLayout.apply(zoom: 2, to: pdfView)
        pdfView.layoutSubtreeIfNeeded()

        #expect(pdfView.hasScrollRoom)
        // 余地はページ座標で測る。ピクセル寸法(contentSize)と比べると
        // フィット表示でも余地があるように見える(倍率が magnification に乗るため)。
        #expect(PDFSurfaceLayout.verticalScrollRoom(of: pdfView) > 1)
    }
}
