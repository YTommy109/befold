import AppKit
@testable import befold
import PDFKit
import Testing

/// 切り替え直後に載せる静止画（`PDFSurfacePlaceholder`）の寿命を固定する。
///
/// **「白紙が見えない」ことはここでは測れない**（それは画面のピクセルを高頻度で
/// 撮って初めて分かる / TASK-569 の実測）。ここで守るのは寿命の規則だけ——
/// 1 枚しか存在しないこと、面が動いたら外れること、動いていないうちは外れないこと。
///
/// 面の保持は `PDFSurfaceRenderingTests` と同じ理由（PDFKit がバックグラウンドから
/// 面を触るため、テストの途中で解放させない）。
@MainActor
@Suite
struct PDFSurfacePlaceholderTests {
    private static var retained: [ZoomingPDFView] = []

    /// 黒い矩形を 1 つ描いた 1 ページの PDF。中身があるページなら何でもよい。
    private func makePageData() -> Data {
        let data = NSMutableData()
        var box = NSRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data) else { return data as Data }
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return data as Data }
        context.beginPage(mediaBox: &box)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 20, y: 20, width: 500, height: 700))
        context.endPage()
        context.closePDF()
        return data as Data
    }

    private func makeView() -> ZoomingPDFView {
        let document = PDFDocument()
        if let page = PDFDocument(data: makePageData())?.page(at: 0) {
            document.insert(page, at: 0)
        }
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = document
        pdfView.layoutSubtreeIfNeeded()
        Self.retained.append(pdfView)
        return pdfView
    }

    @Test("文書が入っていれば静止画を載せられる")
    func installsOnLoadedSurface() {
        let pdfView = makeView()
        pdfView.placeholder.install(on: pdfView)
        #expect(pdfView.placeholder.isShowing)
    }

    @Test("連続して載せても面の上には 1 枚しか残らない")
    func installReplacesPreviousImage() {
        let pdfView = makeView()
        let before = pdfView.subviews.count
        pdfView.placeholder.install(on: pdfView)
        pdfView.placeholder.install(on: pdfView)
        pdfView.placeholder.install(on: pdfView)
        // 3 回載せても増えるのは 1 枚。前のファイルの絵が重なって残らないこと。
        #expect(pdfView.subviews.count == before + 1)
    }

    @Test("外すと面から消える")
    func dismissRemovesImage() {
        let pdfView = makeView()
        let before = pdfView.subviews.count
        pdfView.placeholder.install(on: pdfView)
        pdfView.placeholder.dismiss()
        #expect(!pdfView.placeholder.isShowing)
        #expect(pdfView.subviews.count == before)
    }

    @Test("面の寸法が変わらないレイアウトでは外れない")
    func layoutWithoutResizeKeepsImage() {
        let pdfView = makeView()
        pdfView.placeholder.install(on: pdfView)
        pdfView.placeholder.noteLayout(of: pdfView)
        // 載せた直後にもう一度レイアウトが走ることがある。そこで外すと白紙が戻る。
        #expect(pdfView.placeholder.isShowing)
    }

    @Test("面の寸法が変わったら外れる")
    func resizeDismissesImage() {
        let pdfView = makeView()
        pdfView.placeholder.install(on: pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        pdfView.placeholder.noteLayout(of: pdfView)
        #expect(!pdfView.placeholder.isShowing)
    }

    @Test("倍率が変わったら外れる")
    func zoomDismissesImage() {
        let pdfView = makeView()
        pdfView.placeholder.install(on: pdfView)
        PDFSurfaceLayout.apply(zoom: 2.0, to: pdfView)
        #expect(!pdfView.placeholder.isShowing)
    }

    @Test("回転したら外れる")
    func rotationDismissesImage() {
        let pdfView = makeView()
        pdfView.placeholder.install(on: pdfView)
        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)
        #expect(!pdfView.placeholder.isShowing)
    }

    @Test("文書が入っていない面には載せない")
    func doesNotInstallWithoutDocument() {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        Self.retained.append(pdfView)
        pdfView.placeholder.install(on: pdfView)
        #expect(!pdfView.placeholder.isShowing)
    }
}
