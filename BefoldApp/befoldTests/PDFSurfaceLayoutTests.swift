import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
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
    private func makeDocument(pageSizes: [NSSize]) -> PDFDocument {
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
        return document
    }

    private func makeView(pageSizes: [NSSize] = [NSSize(width: 612, height: 792)]) -> ZoomingPDFView {
        let document = makeDocument(pageSizes: pageSizes)
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        return pdfView
    }

    /// 全ページを縦に連ねて描く。ページ境界で止まらず滑らかにスクロールできる
    /// ことの土台(TASK-567)。
    @Test("面は全ページを連続で描く設定になっている")
    func surfaceScrollsContinuously() {
        let pdfView = makeView()

        #expect(pdfView.displayMode == .singlePageContinuous)
        #expect(pdfView.displayDirection == .vertical)
    }

    /// **`PDFView` のプロパティを `@MainActor` 隔離された override で覆わない。**
    ///
    /// PDFKit は `visiblePagesChanged:` からバックグラウンドキューで `document` を
    /// 読む。隔離付きの override を置くと、そこで隔離チェックが `SIGTRAP` を投げて
    /// アプリごと落ちる（実測: `PDFPageAnalyzerV2` の経路で再現。
    /// クラッシュレポート befold-2026-08-30-060318）。
    ///
    /// ここでは PDFKit と同じく **ObjC のセレクタ経由・主スレッド外**から読み、
    /// 落ちないことを固定する。Swift の型では表現できない呼び方なので
    /// `perform` を使う（この経路こそが実際に落ちた経路）。
    @Test("PDF の面はバックグラウンドから document を読まれても落ちない")
    func survivesDocumentAccessOffTheMainThread() async {
        let pdfView = makeView()
        let selector = NSSelectorFromString("document")

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = pdfView.perform(selector)
                continuation.resume()
            }
        }

        #expect(pdfView.document != nil)
    }

    /// **倍率は最初の描画より前に決まる。** レイアウトを待つと、切り替え直後の
    /// 1 フレームがフィット前の倍率で描かれ、縮む過程が見える（TASK-567）。
    @Test("文書を入れた直後、レイアウトを待たずにフィット倍率が入る")
    func zoomIsSettledBeforeTheFirstDraw() {
        let document = makeDocument(pageSizes: [NSSize(width: 612, height: 792)])
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)

        pdfView.document = document
        PDFSurfaceLayout.apply(zoom: ZoomStore.defaultZoom, to: pdfView)

        // layoutSubtreeIfNeeded を挟まずに、もう倍率が入っている。
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
        #expect(pdfView.scaleFactor > 0)
    }

    /// 影を描かないこと。連続スクロールでは全ページ分の影が乗り、描画コストの
    /// 大半を占める（実測: 231 ページで 36.5ms → 4.3ms / TASK-567）。
    @Test("ページの影は描かない")
    func doesNotDrawPageShadows() {
        let pdfView = makeView()

        #expect(!pdfView.pageShadowsEnabled)
    }

    /// ピンチを自前で受けるため、内側のスクロールビューの拡大縮小は切ってある
    /// (TASK-568)。既定の true のままだと `PDFScrollView` がジェスチャを消費し、
    /// `ZoomingPDFView.magnify` へ届かない。
    @Test("内側のスクロールビューの拡大縮小は切ってある")
    func innerScrollViewDoesNotHandleMagnification() {
        let pdfView = makeView()

        #expect(PDFSurfaceLayout.scrollView(in: pdfView)?.allowsMagnification == false)
    }

    /// 開いた直後はページ全体が収まって見える(AC #1)。連続スクロールでも
    /// **縦にも収める**（`PDFView` 任せの幅フィットは採らない / TASK-567）。
    @Test("開いた直後はページ全体が収まる倍率になる")
    func opensFittedToThePage() throws {
        let pdfView = makeView()

        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
        let page = try #require(pdfView.currentPage)
        let drawn = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        #expect(drawn.width <= pdfView.bounds.width)
        #expect(drawn.height <= pdfView.bounds.height)
    }

    /// 倍率 1.0 の意味が面の生成側と操作側で 1 つであること。
    /// **倍率は面が覚える**ので、面の大きさが変わっても意味が保たれる
    /// (`autoScales` の代わり / TASK-567)。
    @Test("倍率は面の大きさが変わっても意味を保つ")
    func zoomKeepsItsMeaningAcrossResize() {
        let pdfView = makeView()
        let fit = PDFSurfaceLayout.fitScale(of: pdfView)

        PDFSurfaceLayout.apply(zoom: 2, to: pdfView)
        #expect(abs(pdfView.scaleFactor - fit * 2) < 0.0001)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 2) < 0.0001)

        // 面を広げると、絶対倍率は変わるが「フィットの 2 倍」であり続ける。
        pdfView.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        pdfView.layoutSubtreeIfNeeded()
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 2) < 0.0001)
        #expect(pdfView.scaleFactor > fit * 2)

        // ⌘0 でフィットへ戻る。
        PDFSurfaceLayout.apply(zoom: ZoomStore.defaultZoom, to: pdfView)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
    }

    /// ページごとにサイズが違う PDF・横長ページを含む PDF でも、
    /// 各ページで全体が収まる(AC #4)。連続スクロールでは**いちばん大きいページ**に
    /// 合わせるので、スクロール中に倍率が動かない(TASK-567)。
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

    /// **ピンチの入口が `applyZoom` へ繋がっている。**
    ///
    /// 倍率の計算そのものは下の 2 つが見ているが、それらは `applyZoom` を直接
    /// 呼ぶので、**入口の配線が切れても気づけない**（実測: プローブのログを外す
    /// 作業で `applyZoom` の呼び出しごと消えたが、全件通ってしまった / TASK-568）。
    /// ここは認識器のハンドラを通して、配線そのものを見る。
    @Test("ピンチの認識器が倍率へ繋がっている")
    func magnificationRecognizerReachesTheZoom() {
        let pdfView = makeView()
        var reported: [Double] = []
        pdfView.onZoomChanged = { reported.append($0) }
        let recognizer = NSMagnificationGestureRecognizer(target: nil, action: nil)
        recognizer.magnification = 0.5

        pdfView.handleMagnification(recognizer)

        #expect(reported.count == 1)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1.5) < 0.0001)
    }

    /// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)が上下限を守り、
    /// 変化を窓へ伝えること(TASK-564.4)。上下限は `ZoomStore` と共有する。
    @Test("ピンチの拡大は上限で止まり、倍率の変化が窓へ伝わる")
    func pinchZoomClampsAndReports() {
        let pdfView = makeView()
        var reported: [Double] = []
        pdfView.onZoomChanged = { reported.append($0) }

        // ピンチと Ctrl+ホイールはどちらもこの入口へ収斂する。
        for _ in 0 ..< 20 {
            pdfView.applyZoom(scaledBy: 1.5)
        }

        #expect(reported.last == ZoomStore.maxZoom)
        #expect(reported.allSatisfy { $0 <= ZoomStore.maxZoom && $0 >= ZoomStore.minZoom })
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - ZoomStore.maxZoom) < 0.0001)
    }

    @Test("ピンチの縮小は下限で止まる")
    func pinchZoomClampsAtTheMinimum() {
        let pdfView = makeView()
        var reported: [Double] = []
        pdfView.onZoomChanged = { reported.append($0) }

        for _ in 0 ..< 20 {
            pdfView.applyZoom(scaledBy: 0.5)
        }

        #expect(reported.last == ZoomStore.minZoom)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - ZoomStore.minZoom) < 0.0001)
    }

    /// 拡大すると余地が生まれる。位置の記憶はこの余地を基準に測る。
    @Test("拡大するとスクロールの余地が生まれる")
    func gainsScrollRoomWhenZoomedIn() {
        let pdfView = makeView()

        PDFSurfaceLayout.apply(zoom: 2, to: pdfView)
        pdfView.layoutSubtreeIfNeeded()

        // 余地はページ座標で測る。ピクセル寸法(contentSize)と比べると
        // フィット表示でも余地があるように見える(倍率が magnification に乗るため)。
        #expect(PDFSurfaceLayout.verticalScrollRoom(of: pdfView) > 1)
    }
}
