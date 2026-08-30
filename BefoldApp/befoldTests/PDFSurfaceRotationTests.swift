import AppKit
@testable import befold
import PDFKit
import Testing

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

    /// Letter 縦 2 ページの文書。
    private func makeDocument() -> PDFDocument {
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
        return document
    }

    private func makeView() -> ZoomingPDFView {
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        pdfView.document = makeDocument()
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
    /// 「倍率の意味が 1.0 のままであること」だけを見る。
    @Test("回転してもフィット倍率のままでいる")
    func rotationKeepsTheFittedZoom() {
        let pdfView = makeView()

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)
        pdfView.layoutSubtreeIfNeeded()

        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 1) < 0.0001)
    }

    /// 回転オーバーレイの経路。拡大して見ていたなら回転後も同じ倍率のまま、
    /// **同期で**決まる。フィット倍率は `largestPageSize` が `page.rotation` を
    /// 織り込んで同期に出せるので、メインキューを待つ理由が無い（TASK-572 の実測:
    /// 同期で入れた倍率は PDFKit の遅延再レイアウトの後も変わらない）。
    @Test("拡大して見ていても回転後に同じ倍率のまま、同期で決まる")
    func rotationKeepsTheZoomSynchronously() {
        let pdfView = makeView()
        PDFSurfaceLayout.apply(zoom: 2.0, to: pdfView)

        PDFSurfaceLayout.rotate(byDegrees: 90, in: pdfView)

        let expected = PDFSurfaceLayout.expectedScaleFactor(of: pdfView, zoom: 2.0)
        #expect(abs(PDFSurfaceLayout.currentZoom(of: pdfView) - 2.0) < 0.0001)
        #expect(abs(pdfView.scaleFactor - expected) < 0.0001)
    }

    /// 回転を記憶したファイルへ切り替える経路（`PDFPreviewView.updateNSView` と同じ順序）。
    ///
    /// **回転が後から倍率を書き戻してはならない。** かつて `rotate` は回転前の倍率を
    /// 捕捉してメインキューで入れ直しており、呼び出し側が続けて入れた `initialZoom` を
    /// **前のファイルの倍率**で上書きし、倍率が変わるので静止画まで外していた
    /// （TASK-572 / 実測: 同期区間の終わりで 1.0・静止画あり → 1 周後に 3.0・静止画なし）。
    @Test("回転を記憶したファイルへ切り替えても initialZoom が後から上書きされない")
    func switchingToRotatedFileKeepsInitialZoom() async {
        let pdfView = makeView()
        // 前のファイルは倍率 3.0 で見ていた。
        PDFSurfaceLayout.apply(zoom: 3.0, to: pdfView)
        pdfView.layoutSubtreeIfNeeded()

        // 次のファイル: 回転 90 の記憶あり、initialZoom は 1.0。
        pdfView.document = makeDocument()
        PDFSurfaceLayout.apply(rotation: 90, to: pdfView)
        PDFSurfaceLayout.apply(zoom: 1.0, to: pdfView)
        pdfView.layoutSubtreeIfNeeded()
        pdfView.placeholder.install(on: pdfView)
        let scaleAfterSwitch = pdfView.scaleFactor
        #expect(abs(pdfView.zoom - 1.0) < 0.0001)
        #expect(pdfView.placeholder.isShowing)

        // メインキューを 1 周させても（`MainQueueDrainTests` の前提）倍率は変わらない。
        // 静止画が外れないことは、ここでは倍率が動かないことで担保する
        // （倍率が動けば外れることは `PDFSurfacePlaceholderTests` が固定している）。
        // `isShowing` を直接見ないのは、並列実行で待ちが伸びると 0.4 秒の保険タイマが
        // 先に外すため（実測: 全件並列で 7.7 秒かかり落ちた）。
        try? await Task.sleep(for: .milliseconds(200))
        #expect(abs(pdfView.zoom - 1.0) < 0.0001)
        #expect(abs(pdfView.scaleFactor - scaleAfterSwitch) < 0.0001)
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
