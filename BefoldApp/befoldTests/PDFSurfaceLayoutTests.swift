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
    private func makeView(pageSizes: [NSSize] = [NSSize(width: 612, height: 792)]) -> ZoomingPDFView {
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

    /// ピンチを自前で受けるため、内側のスクロールビューの拡大縮小は切ってある
    /// (TASK-568)。既定の true のままだと `PDFScrollView` がジェスチャを消費し、
    /// `ZoomingPDFView.magnify` へ届かない。
    @Test("内側のスクロールビューの拡大縮小は切ってある")
    func innerScrollViewDoesNotHandleMagnification() {
        let pdfView = makeView()

        #expect(PDFSurfaceLayout.scrollView(in: pdfView)?.allowsMagnification == false)
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

/// PDF の回転（TASK-564.5）。
///
/// **作った面はプロセスの終わりまで手放さない。** `PDFPage.rotation` を変えると
/// PDFKit は再レイアウトをメインキューへ積む（`didRotatePageNotification:` の
/// ブロック）。テストが終わって面が解放された後にそれが走ると、解放済みの
/// `PDFDocumentView` を触って落ちる（実測: EXC_BAD_ACCESS at 0x0 /
/// `-[PDFDocumentView layoutDocumentView]`。並列実行で数回に 1 回再現した）。
/// 本番の面は窓と同じ寿命なのでこの順序は起きない。
@MainActor
@Suite
struct PDFSurfaceRotationTests {
    /// 解放を遅らせるためだけの保持箱（上の doc を参照）。
    private static var retained: [ZoomingPDFView] = []

    private func makeView() -> ZoomingPDFView {
        let document = PDFDocument()
        for index in 0 ..< 2 {
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
        Self.retained.append(pdfView)
        return pdfView
    }

    /// 回転は**文書全体**へ効く。ページを送るたびに回し直さずに済ませるための判断
    /// （理由は `PDFSurfaceLayout.rotate(byDegrees:in:)` の doc）。
    @Test("回転は文書のすべてのページへ効く")
    func rotationAppliesToEveryPage() throws {
        let pdfView = makeView()

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)

        let document = try #require(pdfView.document)
        for index in 0 ..< document.pageCount {
            #expect(document.page(at: index)?.rotation == 90)
        }
    }

    @Test("回転は 0/90/180/270 を巡り、4 回で元へ戻る")
    func rotationWrapsAroundFourTurns() {
        let pdfView = makeView()

        var seen: [Int] = []
        for _ in 0 ..< 4 {
            PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)
            seen.append(PDFSurfaceLayout.rotation(of: pdfView))
        }

        #expect(seen == [90, 180, 270, 0])
    }

    /// 左回転（-90）も正規化されて 270 になる。負の値のまま記憶すると、
    /// 記憶した値との比較が同じ向きでも一致しなくなる。
    @Test("左回転は 270 として正規化される")
    func counterClockwiseNormalizes() {
        let pdfView = makeView()

        PDFSurfaceLayout.rotate(byDegrees: -90, in: pdfView)

        #expect(PDFSurfaceLayout.rotation(of: pdfView) == 270)
    }

    /// 記憶した向きへ合わせ直す（差分だけ回す）。往復で同じ向きに戻る。
    @Test("記憶した回転角へ合わせ直せる")
    func restoresARememberedRotation() {
        let pdfView = makeView()
        PDFSurfaceLayout.rotate(byDegrees: 180, in: pdfView)
        let remembered = PDFSurfaceLayout.rotation(of: pdfView)

        let reopened = makeView()
        PDFSurfaceLayout.apply(rotation: remembered, to: reopened)

        #expect(PDFSurfaceLayout.rotation(of: reopened) == 180)
    }

    /// 回転してもフィットで見ている状態は保たれる（AC #2）。
    ///
    /// **`currentZoom == 1` だけを見てはいけない。** 実測では、回転後
    /// `scaleFactorForSizeToFit` と `scaleFactor` がどちらも古いまま比が 1 に
    /// なり、ページが面からはみ出していても通ってしまった（この検証だけを
    /// 持っていたときに見逃した）。**実際に収まっているか**は
    /// `PDFSurfaceRenderingTests` が面の座標で測る。ここでは
    /// 「自動追従の状態が外れていないこと」だけを見る。
    @Test("回転してもフィットの自動追従は外れない")
    func rotationKeepsAutoScaling() async {
        let pdfView = makeView()

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)
        // 再フィットはメインキューへ積まれる（`PDFSurfaceLayout.rotate` の doc）。
        try? await Task.sleep(for: .milliseconds(200))
        pdfView.layoutSubtreeIfNeeded()

        #expect(pdfView.autoScales)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
    }

    /// 回転の記憶は窓の生存期間だけ（位置・表示モードと同じ寿命）。
    @Test("回転は窓の記憶に乗り、新しい窓へは持ち越さない")
    func rotationLivesOnlyInTheWindowMemory() {
        let memory = WindowPresentationMemory()
        let pdf = URL(fileURLWithPath: "/files/doc.pdf")

        memory.setRotation(90, for: pdf)

        #expect(memory.rotation(for: pdf) == 90)
        #expect(WindowPresentationMemory().rotation(for: pdf) == 0)
    }

    /// 文書が無ければ回転は何もしない（切替直後の一瞬）。
    @Test("文書が無ければ回転しても落ちない")
    func rotatingWithoutADocumentIsSafe() {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        Self.retained.append(pdfView)

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)

        #expect(PDFSurfaceLayout.rotation(of: pdfView) == 0)
    }
}
