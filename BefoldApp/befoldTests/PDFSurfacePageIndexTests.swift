import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF の現在ページの決め方（TASK-578.1）。
///
/// `PDFSurfaceLayoutTests` から分けてあるのは、型グループの行数（400 行）を超えたため。
/// 分ける単位としても素直で、あちらは倍率とスクロール余地、こちらはページの索引を見る。
///
/// **面は窓へ載せる。** ページ矩形の換算は窓が無くても効くが、スクロールの余地が
/// 生まれないと位置を動かす検証にならない。面と窓はプロセスの終わりまで手放さない
/// （`PDFSurfaceRotationTests` と同じ理由）。
@MainActor
@Suite
struct PDFSurfacePageIndexTests {
    private nonisolated(unsafe) static var hosted: [(ZoomingPDFView, NSWindow)] = []

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

    private func makeHostedView(pageCount: Int) -> ZoomingPDFView {
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = pdfView
        Self.hosted.append((pdfView, window))
        pdfView.present(
            document: makeDocument(pageCount: pageCount), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        pdfView.layoutSubtreeIfNeeded()
        return pdfView
    }

    /// 総ページ数は文書から読む。**文書が無ければ 0** で、呼び出し側はそれを
    /// 「まだ出せない」として扱う（`1 / 0` を描かないため）。
    @Test("総ページ数は文書から読み、文書が無ければ 0")
    func pageCountComesFromTheDocument() {
        let pdfView = makeHostedView(pageCount: 5)
        #expect(PDFSurfaceLayout.pageCount(of: pdfView) == 5)

        pdfView.present(document: nil, rotation: 0, zoom: 1.0, scrollFraction: 0)

        #expect(PDFSurfaceLayout.pageCount(of: pdfView) == 0)
    }

    /// **スクロールに応じてページ番号が単調に進む。** 先頭では 1 ページ目、
    /// 末尾では最終ページになる（実測でこの並びになることを確認済み / TASK-578.1）。
    @Test("スクロールに応じて現在ページが単調に進む")
    func currentPageAdvancesMonotonicallyWithScroll() {
        let pdfView = makeHostedView(pageCount: 5)
        var seen: [Int] = []

        for step in 0 ... 10 {
            pdfView.restore(fraction: Double(step) / 10)
            pdfView.layoutSubtreeIfNeeded()
            seen.append(PDFSurfaceLayout.currentPageIndex(of: pdfView))
        }

        #expect(seen.first == 0)
        #expect(seen.last == 4)
        #expect(seen == seen.sorted())
    }

    /// **ページ間の余白へ中心が落ちても 1 ページに決まる。**
    ///
    /// 「中心を含むページ」で判定すると該当が 0 件になる（実測: 500 ページを
    /// fraction 0.5 で表示し全ページへ含有判定を当てて該当なし。ページ間には
    /// 約 14.5pt の余白がある / TASK-577・TASK-578.1）。
    ///
    /// **文書座標で 1pt ずつ動かす。** 割合を等分して回す形では余白（ページピッチの
    /// 約 1.8%）を跨いでしまい、含有判定のままでも通ってしまう（実測: 5 ページ /
    /// 101 分割では一度も余白へ落ちなかった）。
    @Test("ページ間の余白へ中心が落ちても現在ページが範囲内に決まる")
    func currentPageStaysInRangeBetweenPages() {
        let pdfView = makeHostedView(pageCount: 5)
        guard let clipView = PDFSurfaceLayout.scrollView(in: pdfView)?.contentView else {
            Issue.record("スクロールビューが取れない")
            return
        }
        let room = PDFSurfaceLayout.verticalScrollRoom(of: pdfView)
        // 1 ページぶんの送りを 1pt 刻みで舐める。余白を跨がないので必ず中に入る。
        let span = min(Int(room), 900)
        var seen: Set<Int> = []

        for offset in 0 ... span {
            var origin = clipView.bounds.origin
            origin.y = room - Double(offset)
            clipView.scroll(to: origin)
            pdfView.layoutSubtreeIfNeeded()
            let index = PDFSurfaceLayout.currentPageIndex(of: pdfView)
            seen.insert(index)
            #expect(index >= 0)
            #expect(index < 5)
        }

        // 1 ページぶん送ったので、少なくとも 2 ページを見ているはず（境目を跨いだ証拠）。
        #expect(seen.count >= 2)
    }

    /// 文書が無いときは 0 を返す。表示を出さない判断は総ページ数側で行うので、
    /// ここが例外で落ちたり負の値を返したりしないことだけを固定する。
    @Test("文書が無くても現在ページの問い合わせは壊れない")
    func currentPageIsSafeWithoutADocument() {
        let pdfView = makeHostedView(pageCount: 3)

        pdfView.present(document: nil, rotation: 0, zoom: 1.0, scrollFraction: 0)

        #expect(PDFSurfaceLayout.currentPageIndex(of: pdfView) == 0)
    }

    /// 回転しても番号は保たれる。回転は `present(...)` を通って面を組み直すので、
    /// ページ矩形の向きが変わってもページの並び自体は変わらない（TASK-578.1 の AC #3）。
    @Test("回転しても現在ページは範囲内に保たれる")
    func currentPageSurvivesRotation() {
        let pdfView = makeHostedView(pageCount: 5)
        pdfView.restore(fraction: 0.5)
        pdfView.layoutSubtreeIfNeeded()
        let before = PDFSurfaceLayout.currentPageIndex(of: pdfView)

        pdfView.rotate(byDegrees: 90)
        pdfView.layoutSubtreeIfNeeded()

        let after = PDFSurfaceLayout.currentPageIndex(of: pdfView)
        #expect(before > 0)
        #expect(after >= 0)
        #expect(after < 5)
    }
}
