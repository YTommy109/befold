import AppKit
@testable import befold
import PDFKit
import Testing

/// PDF 面がキーボードのフォーカスを奪う契機を固定する。
///
/// **文書の差し替えでフォーカスを動かさない。** サイドバーはカーソルキーで選択を
/// 動かした時点でそのファイルを開くので（`FileListView+Keyboard.move(to:)` が
/// `model.selection` の更新に続けて `openIfFile` を呼ぶ）、PDF が開くたびに面が
/// first responder を取ると、**次のカーソルキーがサイドバーへ届かなくなる**。
/// 一覧を矢印で流し読みできなくなる形の回帰で、実際に起きた（TASK-581）。
///
/// フォーカスを面へ移してよいのは**ユーザーがページ番号入力を閉じたとき**だけ。
/// そちらは飛んだ先を読み続けられるようにするための意図した移動（TASK-578.2）。
@MainActor
@Suite
struct PDFPageIndicatorFocusTests {
    /// 面と窓はプロセスの終わりまで手放さない（`PDFPageIndicatorModelTests` と同じ理由）。
    private nonisolated(unsafe) static var hosted: [(ZoomingPDFView, NSWindow)] = []

    /// `makeFirstResponder` の要求先を記録するスパイ。空の面は実描画前だと
    /// first responder を受理しないことがあるため、遷移の結果ではなく
    /// **どのビューへ要求したか**を見る（`FileListModelFocusTests` と同じ形）。
    private final class SpyWindow: NSWindow {
        private(set) var requestedFirstResponder: NSResponder?

        func forgetRequests() {
            requestedFirstResponder = nil
        }

        override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
            requestedFirstResponder = responder
            return super.makeFirstResponder(responder)
        }
    }

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

    /// 面・窓・プロキシの 3 点セット。タプルで返すと `large_tuple` に触れるので型にする。
    private struct Surface {
        let pdfView: ZoomingPDFView
        let window: SpyWindow
        let proxy: PDFViewProxy
    }

    private func makeSurface(pageCount: Int) -> Surface {
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let window = SpyWindow(
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
        return Surface(pdfView: pdfView, window: window, proxy: proxy)
    }

    /// フォーカス移動は `DispatchQueue.main.async` で 1 周遅れて走る。**同じキューへ
    /// 後から積んだマーカーを待つ**ことで、その 1 周が終わったことを決定的に判定する
    /// （FIFO なので、マーカーが走った時点で先行ブロックは実行済み）。時間で待たない。
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// 本体の回帰。サイドバーを矢印で流し読みしている最中に PDF の行へ来ると、
    /// その場で PDF が開く。ここで面がフォーカスを取ると次の矢印が効かなくなる。
    @Test("PDF を開いてもフォーカスを奪わない")
    func openingADocumentDoesNotStealFocus() async {
        let surface = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: surface.proxy)
        // 面を組む過程での要求は対象外。ここから先の要求だけを見る。
        surface.window.forgetRequests()

        surface.pdfView.present(
            document: makeDocument(pageCount: 3), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder == nil)
        // 文書が変わったら編集を閉じること自体は保つ（TASK-578.2）。
        #expect(!model.isEditing)
    }

    /// 面を差し替えても編集中の値が残らないことは保つ。閉じる動作とフォーカス移動を
    /// 分けたあとも、こちらが落ちないことを見る。
    @Test("編集中に文書が差し替わると、編集は閉じるがフォーカスは動かない")
    func documentReplacementClosesEditingWithoutFocusing() async {
        let surface = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: surface.proxy)
        model.beginEditing()
        model.draft = "9"
        surface.window.forgetRequests()

        surface.pdfView.present(
            document: makeDocument(pageCount: 3), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        await drainMainQueue()

        #expect(!model.isEditing)
        #expect(model.draft.isEmpty)
        #expect(surface.window.requestedFirstResponder == nil)
    }

    /// ユーザーが Esc で入力を閉じたときは、意図どおり面へ移す（TASK-578.2）。
    /// これが落ちると「飛んだ直後の ↓ で別のファイルが開く」旧不具合へ戻る。
    @Test("Esc で入力を閉じたときは面へフォーカスを移す")
    func cancellingTheEditorFocusesTheSurface() async {
        let surface = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: surface.proxy)
        model.beginEditing()
        surface.window.forgetRequests()

        model.cancel()
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder === surface.pdfView)
    }

    /// Enter による確定も同じ（飛んだ先を読み続けられるようにするため）。
    @Test("Enter で確定したときは面へフォーカスを移す")
    func committingTheEditorFocusesTheSurface() async {
        let surface = makeSurface(pageCount: 10)
        let model = PDFPageIndicatorModel(pdfViewProxy: surface.proxy)
        model.beginEditing()
        model.draft = "5"
        surface.window.forgetRequests()

        model.commit()
        await drainMainQueue()

        #expect(surface.window.requestedFirstResponder === surface.pdfView)
    }
}
