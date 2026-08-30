import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF の面が**実際にどう描かれるか**をオフスクリーンのビットマップで確かめる。
///
/// GUI は自動テストの対象外というのがこのプロジェクトの規約だが、それは
/// 「窓を出して人が見る」ことを指す。`NSView.cacheDisplay(in:to:)` は画面収録の
/// 権限も窓も要らずにビューを描かせられるので、**描かれたかどうか**と
/// **どこに描かれたか**はここで測れる（TASK-564）。
///
/// 面の保持については `PDFSurfaceRotationTests` の doc と同じ理由で、
/// 作った面をプロセスの終わりまで手放さない。
@MainActor
@Suite
struct PDFSurfaceRenderingTests {
    private static var retained: [ZoomingPDFView] = []

    /// 各ページの上端と下端に黒帯を描いた PDF。帯が両方見えていれば
    /// 「ページ全体が画面に収まっている」ことが画素で確かめられる。
    private func makeView(pageCount: Int = 2, size: NSSize = NSSize(width: 612, height: 792)) -> ZoomingPDFView {
        let document = PDFDocument()
        for index in 0 ..< pageCount {
            let data = NSMutableData()
            var box = NSRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { continue }
            context.beginPage(mediaBox: &box)
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 20, y: 10, width: size.width - 40, height: 30))
            context.fill(CGRect(x: 20, y: size.height - 40, width: size.width - 40, height: 30))
            context.endPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: index)
            }
        }
        let pdfView = ZoomingPDFView(frame: .zero)
        // 地を明示的に黒く塗る。連続スクロールでは文書を外した面が
        // `underPageBackgroundColor` を描かなくなり、地の色を指定していないと
        // 「文書が外れている」ことを画素で測れない(実測: 外した直後も明るい画素 100%)。
        // アプリ側も `PDFPreviewView` が地の色を明示している。
        pdfView.backgroundColor = .black
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        Self.retained.append(pdfView)
        return pdfView
    }

    /// 描かれた明るい画素の割合。`PDFView` の地は暗い(`underPageBackgroundColor`)ので、
    /// **白いページが出ているか**はこれで測れる。文書を外せばほぼ 0 になる。
    ///
    /// 地を白に塗り替えて「暗い画素」で測る形にはしない。実測では
    /// `backgroundColor = .white` にすると `cacheDisplay` にページが写らなくなる
    /// (PDFKit が別の描画経路へ行く)。既定の地のまま測ること。
    private func lightPixelRatio(of view: NSView) -> Double {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var dark = 0
        var total = 0
        for column in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for row in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                total += 1
                if color.brightnessComponent > 0.7 { dark += 1 }
            }
        }
        return total > 0 ? Double(dark) / Double(total) : 0
    }

    /// PDFKit がメインキューへ積んだ再レイアウト（`didRotatePage` のブロック）を
    /// 走らせる。倍率の入れ直しは `PDFSurfaceLayout.rotate` が同期で済ませる（TASK-572）ので
    /// ここで待つのは PDFKit 側だけ。`RunLoop.run(until:)` では走らない
    /// (下の `MainQueueDrainTests` の実測)。
    private func settleLayout() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// 面の座標系での、いま表示しているページの矩形。
    private func pageRect(in pdfView: PDFView) -> NSRect? {
        guard let page = pdfView.currentPage else { return nil }
        return pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
    }

    /// 開いた直後、**ページの上端も下端も画面の中にある**（564.2 AC #1）。
    /// 連続スクロールでも縦フィットを保つ（`PDFView` 任せの幅フィットでは
    /// 下端が画面外に出る / TASK-567）。
    @Test("開いた直後はページ全体が面の中に収まって描かれる")
    func drawsTheWholePageOnOpen() throws {
        let pdfView = makeView()

        let rect = try #require(pageRect(in: pdfView))
        #expect(rect.width <= pdfView.bounds.width + 1)
        #expect(rect.height <= pdfView.bounds.height + 1)
        #expect(rect.minY >= -1)
        #expect(rect.maxY <= pdfView.bounds.height + 1)
        // ページ(白地)が描かれている。地と黒帯の分だけ 100% には満たない。
        let drawn = lightPixelRatio(of: pdfView)
        #expect(drawn > 0.3)
        #expect(drawn < 1)
    }

    /// ページ境界で分断されず、次のページが続けて見えている（TASK-567）。
    /// かつては「同時に見えるのは常に 1 枚」を固定していたが、連続スクロールへ
    /// 改めた時点でその不変条件は捨てた。守るものが逆になる。
    @Test("スクロールするとページが連続して現れる")
    func showsPagesContinuously() {
        let pdfView = makeView(pageCount: 3)

        // ページ送りの操作を挟まず、スクロールだけで文書の途中まで進める。
        pdfView.restore(fraction: 0.5)
        pdfView.layoutSubtreeIfNeeded()

        // 3 ページ分が 1 本に連なっているので、半分まで来ても白いページが見えている
        // （`.singlePage` なら 1 ページ内に半分という位置は存在しない）。
        #expect(PDFSurfaceLayout.documentFraction(of: pdfView) > 0.4)
        #expect(lightPixelRatio(of: pdfView) > 0.3)
    }

    /// ページサイズが混在していても、どのページでも全体が収まる（564.2 AC #4）。
    @Test("横長ページでも全体が面の中に収まる")
    func fitsLandscapePages() throws {
        let pdfView = makeView(pageCount: 1, size: NSSize(width: 792, height: 612))

        let rect = try #require(pageRect(in: pdfView))
        #expect(rect.width <= pdfView.bounds.width + 1)
        #expect(rect.height <= pdfView.bounds.height + 1)
        #expect(lightPixelRatio(of: pdfView) > 0.3)
    }

    /// 回転しても全体が収まったまま、縦横比だけが入れ替わる（564.5 AC #2）。
    @Test("回転後もページ全体が収まり、縦横比が入れ替わる")
    func keepsFitAfterRotation() async throws {
        let pdfView = makeView(pageCount: 1)
        let before = try #require(pageRect(in: pdfView))

        pdfView.rotate(byDegrees: 90)
        await settleLayout()
        pdfView.layoutSubtreeIfNeeded()

        let after = try #require(pageRect(in: pdfView))
        #expect(before.width < before.height) // 縦長だった
        #expect(after.width > after.height) // 横長になった
        #expect(after.width <= pdfView.bounds.width + 1)
        #expect(after.height <= pdfView.bounds.height + 1)
        #expect(lightPixelRatio(of: pdfView) > 0.3)
    }

    /// **PDF → 別種別 → PDF の往復で残留が無い**（564.1 AC #6）。
    ///
    /// `PDFPreviewView` は PDF 以外を表示している間 `data` に nil を渡し、面から
    /// 文書を外す。外していなければ、別種別を見ている間も PDF が描かれたままになる
    /// （重ね順で隠れていても、印刷は前のファイルを刷る）。
    @Test("別種別へ移ると面から文書が外れ、戻すと再び描かれる")
    func clearsAndRestoresTheDocumentOnRoundTrip() {
        let pdfView = makeView()
        let document = pdfView.document
        let drawn = lightPixelRatio(of: pdfView)
        #expect(drawn > 0.3)

        // PDF 以外を表示している状態（PDFPreviewView が data: nil で通る経路）。
        pdfView.document = nil
        pdfView.layoutSubtreeIfNeeded()
        #expect(pdfView.currentPage == nil)
        // ページが残っていない = 白い画素がほぼ無い。
        #expect(lightPixelRatio(of: pdfView) < 0.01)

        // PDF へ戻る。
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        #expect(lightPixelRatio(of: pdfView) > 0.3)
    }
}

/// テストの前提そのものの確認。回転後の PDFKit の再レイアウトはメインキューへ積まれるので、
/// **テストがメインキューを明け渡さない限り観測できない**。
/// 実測: `RunLoop.current.run(until:)` では走らず（Swift Testing の @MainActor テストは
/// メインキューを自分で回さない）、`await Task.sleep` なら走る。
@MainActor
@Suite
struct MainQueueDrainTests {
    @Test("await で待てばメインキューのブロックが走る")
    func drainsTheMainQueue() async {
        final class Box { var ran = false }
        let box = Box()

        DispatchQueue.main.async { box.ran = true }
        // `RunLoop.run(until:)` では走らない。Swift Testing の @MainActor テストは
        // メインキューを自分で回さないため、待つなら await で明け渡す必要がある。
        try? await Task.sleep(for: .milliseconds(200))

        #expect(box.ran)
    }
}
