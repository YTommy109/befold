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

/// PDF の表示位置の記憶（TASK-564.3）。
///
/// **PDF 専用の記憶機構は作らない。** 位置は「文書全体に対する 0…1」という
/// web の面と同じ意味の値へ畳み、`WindowPresentationMemory`（窓の生存期間だけの
/// 記憶）の既存の表へそのまま乗せる。
@MainActor
@Suite
struct PDFSurfacePositionTests {
    private func makeView(pageCount: Int) -> PagingPDFView {
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
        let pdfView = PagingPDFView()
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

    @Test("表示位置は文書全体に対する 0…1 で表され、往復で同じページへ戻る")
    func positionRoundTripsThroughAFraction() {
        let pdfView = makeView(pageCount: 4)
        pdfView.goToNextPage(nil)
        pdfView.goToNextPage(nil)
        #expect(index(of: pdfView) == 2)

        let saved = PDFSurfaceLayout.documentFraction(of: pdfView)
        pdfView.goToFirstPage(nil)
        PDFSurfaceLayout.restore(fraction: saved, in: pdfView)

        #expect(abs(saved - 0.5) < 0.0001)
        #expect(index(of: pdfView) == 2)
    }

    /// ファイルが更新されてページ数が減っても、範囲内へ丸めてクラッシュしない（AC #4）。
    @Test("ページ数が減ったら最後のページへ丸める")
    func clampsWhenThePageDisappears() {
        let wide = makeView(pageCount: 10)
        wide.goToLastPage(nil)
        let saved = PDFSurfaceLayout.documentFraction(of: wide)

        let narrow = makeView(pageCount: 2)
        PDFSurfaceLayout.restore(fraction: saved, in: narrow)

        #expect(index(of: narrow) == 1)
    }

    @Test("先頭・末尾・範囲外の値でも破綻しない")
    func handlesEdgeFractions() {
        let pdfView = makeView(pageCount: 3)

        for fraction in [-1.0, 0, 0.999, 1, 5] {
            PDFSurfaceLayout.restore(fraction: fraction, in: pdfView)
            let current = index(of: pdfView)
            #expect(current != nil)
            #expect((current ?? -1) >= 0 && (current ?? -1) <= 2)
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
        let pdfView = PagingPDFView()
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
    private static var retained: [PagingPDFView] = []

    private func makeView() -> PagingPDFView {
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
        let pdfView = PagingPDFView()
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

    /// 回転しても倍率の自動追従は外れない（AC #2: 回転後もフィットが保たれる）。
    /// 倍率は回転の中で触らず、`autoScales` が縦横比の変化に追従する。
    @Test("回転してもフィットの自動追従は外れない")
    func rotationKeepsAutoScaling() {
        let pdfView = makeView()

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)
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
        let pdfView = PagingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        Self.retained.append(pdfView)

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)

        #expect(PDFSurfaceLayout.rotation(of: pdfView) == 0)
    }
}
