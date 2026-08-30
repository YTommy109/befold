import AppKit
@testable import befold
import PDFKit
import SwiftUI
import Testing

/// ページ位置表示の見え方を、オフスクリーン描画で確かめる（TASK-578.1 の AC #4・#5）。
///
/// 画面キャプチャではなく `NSHostingView.cacheDisplay(in:to:)` なので TCC の許可は
/// 要らない（`UnsupportedFileViewSnapshotTests` と同じ手）。
///
/// **配色そのものの良し悪しは測れない。** ここで塞げるのは「ライト / ダークの
/// どちらでも地に沈まず何かが描かれている」ことと、「出さないと決めた条件で
/// 本当に何も描かれない」ことの 2 つ。実際の見え方はリリース前の目視で見る
/// （このリポジトリのテスト規約が GUI 層を手動チェックに置いているのと同じ理由）。
@MainActor
@Suite
struct PDFPageIndicatorSnapshotTests {
    private nonisolated(unsafe) static var retained: [NSView] = []

    /// 面に依らず値を作れるよう、文書を入れた面と proxy を組んで模した状態を作る。
    private func makeModel(pageCount: Int) -> PDFPageIndicatorModel {
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
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = pdfView
        Self.retained.append(pdfView)
        pdfView.present(
            document: pageCount > 0 ? document : nil, rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        pdfView.layoutSubtreeIfNeeded()
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView
        let model = PDFPageIndicatorModel(pdfViewProxy: proxy)
        model.refresh()
        return model
    }

    private func render(_ model: PDFPageIndicatorModel, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let view = NSHostingView(rootView: PDFPageIndicator(model: model))
        view.appearance = NSAppearance(named: appearance)
        view.frame = NSRect(x: 0, y: 0, width: 160, height: 60)
        view.layoutSubtreeIfNeeded()
        Self.retained.append(view)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 画に含まれる色の種類数。地一色なら 1 で、文字が乗っていれば増える。
    /// **明暗の閾値では数えない**（外観で地と文字の明るさが入れ替わるため）。
    private func distinctColorCount(in rep: NSBitmapImageRep) -> Int {
        var colors: Set<String> = []
        for column in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for row in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                colors.insert(color.description)
            }
        }
        return colors.count
    }

    /// ライトでもダークでも地に沈まない（AC #4）。色はセマンティック指定に任せて
    /// いるので、片方でだけ消えるとしたらここで分かる。
    @Test("ライトでもダークでも描かれる")
    func drawsInBothAppearances() throws {
        let model = makeModel(pageCount: 12)

        let light = try render(model, appearance: .aqua)
        let dark = try render(model, appearance: .darkAqua)

        #expect(distinctColorCount(in: light) > 1)
        #expect(distinctColorCount(in: dark) > 1)
    }

    /// **総ページ数が 0 のときは何も描かない**（AC #5 の受け皿）。
    /// 文書が無い・面がまだ組み上がっていないのどちらでも 0 になるので、
    /// ここで引っ込まないと `1 / 0` が出る。
    @Test("総ページ数が 0 なら何も描かない")
    func drawsNothingWithoutPages() throws {
        let model = PDFPageIndicatorModel(pdfViewProxy: PDFViewProxy())
        model.refresh()

        let rendered = try render(model, appearance: .aqua)

        // 地一色 = 何も乗っていない。
        #expect(distinctColorCount(in: rendered) == 1)
    }
}
