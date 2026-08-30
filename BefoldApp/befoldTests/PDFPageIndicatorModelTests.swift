import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF のページ位置表示（TASK-578.1）。
///
/// **面は窓へ載せる。** ページ矩形の換算そのものは窓が無くても効くが、スクロールの
/// 余地が生まれないと位置を動かす検証にならない。面と窓はプロセスの終わりまで
/// 手放さない（`PDFSurfaceRotationTests` と同じ理由）。
@MainActor
@Suite
struct PDFPageIndicatorModelTests {
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

    private func makeSurface(pageCount: Int) -> (ZoomingPDFView, PDFViewProxy) {
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
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView
        return (pdfView, proxy)
    }

    /// **面がまだ無いうちは 0。** 表示側はこれを「まだ出せない」として引っ込むので、
    /// `1 / 0` が描かれることがない（TASK-578.1 の縮退の約束）。
    @Test("面が無いあいだは総ページ数が 0")
    func reportsZeroBeforeTheSurfaceExists() {
        let model = PDFPageIndicatorModel(pdfViewProxy: PDFViewProxy())

        model.refresh()

        #expect(model.pageCount == 0)
        #expect(model.currentIndex == 0)
    }

    /// 面が組み上がっていれば総ページ数と現在ページが読める。
    @Test("面から総ページ数と現在ページを読む")
    func readsPageCountAndCurrentPageFromTheSurface() {
        let (_, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)

        model.refresh()

        #expect(model.pageCount == 7)
        #expect(model.currentIndex == 0)
    }

    /// **スクロールで現在ページが追随する（AC #2）。**
    ///
    /// 位置を動かして `NSClipView` の bounds 変更を届け、購読が繋がっていることごと見る。
    /// `model.refresh()` を直接呼ぶ形だと、購読が切れていても通ってしまう。
    @Test("スクロールすると現在ページが追随して更新される")
    func followsScrolling() {
        let (pdfView, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.refresh()

        pdfView.restore(fraction: 1.0)
        pdfView.layoutSubtreeIfNeeded()

        #expect(model.currentIndex == 6)
    }

    /// 文書を差し替えたら総ページ数も現在ページも新しい文書のものになる（AC #3）。
    /// 前の文書の値が残ると、開いた直後だけ「248 ページ中 12 ページ目」のような
    /// 別ファイルの位置が出る。
    @Test("文書を差し替えると新しい文書の値になる")
    func followsDocumentReplacement() {
        let (pdfView, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        pdfView.restore(fraction: 1.0)
        pdfView.layoutSubtreeIfNeeded()
        #expect(model.currentIndex == 6)

        pdfView.present(
            document: makeDocument(pageCount: 2), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        pdfView.layoutSubtreeIfNeeded()

        #expect(model.pageCount == 2)
        #expect(model.currentIndex == 0)
    }

    /// PDF 以外を見ている間は面から文書が外れる（`present(document: nil)`）。
    /// そのとき 0 に戻ることで、表示側が引っ込む（AC #5 の土台）。
    @Test("文書が外れたら総ページ数が 0 に戻る")
    func fallsBackToZeroWhenTheDocumentIsRemoved() {
        let (pdfView, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.refresh()
        #expect(model.pageCount == 7)

        pdfView.present(document: nil, rotation: 0, zoom: 1.0, scrollFraction: 0)

        #expect(model.pageCount == 0)
    }

    /// 回転しても値が壊れない（AC #3）。回転は `present(...)` を通って面を組み直すので、
    /// その経路でページ数が失われたり範囲外になったりしないことを見る。
    @Test("回転しても総ページ数と現在ページが保たれる")
    func survivesRotation() {
        let (pdfView, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.refresh()

        pdfView.rotate(byDegrees: 90)
        pdfView.layoutSubtreeIfNeeded()

        #expect(model.pageCount == 7)
        #expect(model.currentIndex >= 0)
        #expect(model.currentIndex < 7)
    }

    // MARK: - ページ番号を指定してジャンプする（TASK-578.2）

    /// 入力の受け付け方を表で固定する。**判定は入力の形ではなく、パース結果と
    /// 実際の総ページ数で行う**ので、総ページ数が変われば同じ文字列の可否も変わる。
    @Test("受け付ける入力と受け付けない入力")
    func parsesOnlyPageNumbersInRange() {
        let accepted: [String: Int] = [
            "1": 0, "7": 6, " 3 ": 2, "03": 2,
        ]
        let rejected = ["", " ", "0", "8", "-1", "1.5", "１", "abc", "3a", "9999"]

        for (text, expected) in accepted {
            #expect(PDFPageIndicatorModel.pageJumpTarget(from: text, pageCount: 7) == expected)
        }
        for text in rejected {
            #expect(PDFPageIndicatorModel.pageJumpTarget(from: text, pageCount: 7) == nil)
        }
    }

    /// クリックで編集に入ると、いま見ているページが初期値になる（打ち直しの手間を省く）。
    @Test("編集を始めると現在ページが初期値になる")
    func startsEditingWithTheCurrentPage() {
        let (pdfView, proxy) = makeSurface(pageCount: 7)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        pdfView.restore(fraction: 1.0)
        pdfView.layoutSubtreeIfNeeded()

        model.beginEditing()

        #expect(model.isEditing)
        #expect(model.draft == "7")
    }

    /// **確定すると実際に飛ぶ（AC #2・#5）。** 面の位置が動いた結果として
    /// 現在ページ表示も一致する。
    @Test("確定すると当該ページへ飛び、表示も一致する")
    func commitJumpsToThePage() {
        let (pdfView, proxy) = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.beginEditing()
        model.draft = "8"

        model.commit()
        pdfView.layoutSubtreeIfNeeded()

        #expect(!model.isEditing)
        #expect(model.currentIndex == 7)
        #expect(PDFSurfaceLayout.currentPageIndex(of: pdfView) == 7)
    }

    /// **範囲外・非数値ではジャンプしない（AC #3）。** 表示は元へ戻るだけで、
    /// 位置も現在ページ表示も動かない。
    @Test("受け付けない入力ではジャンプせず表示も壊れない")
    func rejectedInputDoesNotJump() {
        let (pdfView, proxy) = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        pdfView.restore(fraction: 0.5)
        pdfView.layoutSubtreeIfNeeded()
        let before = model.currentIndex

        for text in ["0", "11", "abc", ""] {
            model.beginEditing()
            model.draft = text
            model.commit()
            pdfView.layoutSubtreeIfNeeded()
            #expect(!model.isEditing)
            #expect(model.currentIndex == before)
        }
    }

    /// 取り消すと入力を捨てて元の表示へ戻る（AC #4）。位置は動かない。
    @Test("取り消すと入力を捨てて元へ戻る")
    func cancelDiscardsTheDraft() {
        let (pdfView, proxy) = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        pdfView.restore(fraction: 0.5)
        pdfView.layoutSubtreeIfNeeded()
        let before = model.currentIndex
        model.beginEditing()
        model.draft = "9"

        model.cancel()
        pdfView.layoutSubtreeIfNeeded()

        #expect(!model.isEditing)
        #expect(model.currentIndex == before)
    }

    /// **文書が差し替わったら編集を閉じる。** PDF から別の PDF へ切り替えても View は
    /// 消えないので、編集中の値が残ると古い番号で飛びうる。
    @Test("文書が差し替わると編集が閉じる")
    func documentReplacementClosesEditing() {
        let (pdfView, proxy) = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.beginEditing()
        model.draft = "9"

        pdfView.present(
            document: makeDocument(pageCount: 3), rotation: 0, zoom: 1.0, scrollFraction: 0
        )

        #expect(!model.isEditing)
    }
}
