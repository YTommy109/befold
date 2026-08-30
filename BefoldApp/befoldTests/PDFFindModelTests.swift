import AppKit
@testable import befold
import BefoldKit
import PDFKit
import Testing

/// PDF 面の文書内検索（TASK-570）。
///
/// 検索そのものは PDFKit の `beginFindString` が非同期に行い、通知をメインスレッドへ
/// 返す。ここでは「結果の受け取り方」——世代管理・現在位置の巡回・件数表示——を固定する。
@MainActor
@Suite
struct PDFFindModelTests {
    /// 各ページに 1 回ずつ "needle" が出てくる PDF。
    private func makeDocument(pageCount: Int, word: String = "needle") -> PDFDocument {
        let document = PDFDocument()
        for index in 0 ..< pageCount {
            let data = NSMutableData()
            var box = NSRect(x: 0, y: 0, width: 612, height: 792)
            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { continue }
            context.beginPage(mediaBox: &box)
            let text = NSAttributedString(
                string: "page \(index) \(word) tail",
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            context.textPosition = CGPoint(x: 50, y: 700)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: index)
            }
        }
        return document
    }

    /// 面とプロキシを繋いだ状態。proxy は面を弱参照で持つだけなので、
    /// 面の寿命を保つためにここが両方を抱える。
    private struct Fixture {
        let model: PDFFindModel
        let pdfView: ZoomingPDFView
    }

    private func makeFixture(pageCount: Int, caseSensitive: Bool = false) -> Fixture {
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        pdfView.present(
            document: makeDocument(pageCount: pageCount), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView
        return Fixture(
            model: PDFFindModel(pdfViewProxy: proxy, caseSensitive: { caseSensitive }),
            pdfView: pdfView
        )
    }

    /// 図形だけを描いた 1 ページの PDF（テキストレイヤーを持たない）。
    /// **多行の `if let` にしない**——swiftformat が `{` を独立行へ送り、
    /// swiftlint の `opening_brace` が鳴る（.claude/CLAUDE.md の Swift 規約）。
    private static func makeTextlessDocument() -> PDFDocument {
        let document = PDFDocument()
        let data = NSMutableData()
        var box = NSRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data) else { return document }
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return document }
        context.beginPage(mediaBox: &box)
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(CGRect(x: 100, y: 100, width: 200, height: 200)) // 図形だけ、文字なし
        context.endPage()
        context.closePDF()
        if let page = PDFDocument(data: data as Data)?.page(at: 0) { document.insert(page, at: 0) }
        return document
    }

    /// 検索が終わるまで待つ（非同期なので完了を待たないと件数が確定しない）。
    private func waitForSearch(_ model: PDFFindModel) async {
        for _ in 0 ..< 100 {
            if !model.isSearching, !model.matches.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("検索するとヒットが集まり、1 件目が選ばれる")
    func collectsMatchesAndSelectsFirst() async {
        let fixture = makeFixture(pageCount: 5)
        let model = fixture.model
        model.open()

        model.setQuery("needle")
        await waitForSearch(model)

        #expect(model.matches.count == 5)
        #expect(model.currentIndex == 0)
        #expect(model.countText == "1/5")
    }

    /// **末尾から先頭へ、先頭から末尾へ回る**（web 面の `nextMatchIndex` と同じ）。
    @Test("次へ / 前へで巡回する")
    func cyclesThroughMatches() async {
        let fixture = makeFixture(pageCount: 3)
        let model = fixture.model
        model.open()
        model.setQuery("needle")
        await waitForSearch(model)

        model.moveToNext()
        #expect(model.countText == "2/3")
        model.moveToNext()
        #expect(model.countText == "3/3")
        model.moveToNext() // 末尾 → 先頭
        #expect(model.countText == "1/3")
        model.moveToPrevious() // 先頭 → 末尾
        #expect(model.countText == "3/3")
    }

    /// **テキストレイヤーを持たない PDF はヒット 0 件として振る舞う**（AC #5）。
    /// 例外にも無反応にもならず、"0/0" を出す。
    @Test("テキストを持たない PDF ではヒット 0 件になる")
    func scannedPDFYieldsNoMatches() async {
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        pdfView.present(
            document: Self.makeTextlessDocument(), rotation: 0, zoom: 1.0, scrollFraction: 0
        )
        let proxy = PDFViewProxy()
        proxy.pdfView = pdfView
        let model = PDFFindModel(pdfViewProxy: proxy, caseSensitive: { false })
        model.open()

        model.setQuery("anything")
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.matches.isEmpty)
        #expect(model.countText == "0/0")
    }

    /// **前の検索の一致が新しい検索へ混ざらない。**
    ///
    /// `cancelFindString()` は即座には止まらず、通知は**文書ごと**に飛ぶ。同じ文書で
    /// 検索し直すと、前の検索の一致が新しい購読へ届きうる（そのとき世代番号は一致して
    /// しまうので、番号だけでは弾けない）。届いた一致の中身が現在の検索語かを見ている。
    ///
    /// 実際のレースは時間依存で再現できないため、**検索の走行中に**（＝購読が生きて
    /// いる間に）別の検索語の一致を直接投げて、判定だけを固定する。検索が終わった後は
    /// 購読が外れていて何も届かないので、そこで投げても素通りしてしまう。
    @Test("走行中に別の検索語の一致が届いても取り込まない")
    func lateMatchForAnotherQueryIsRejected() throws {
        let fixture = makeFixture(pageCount: 3)
        let model = fixture.model
        let pdfView = fixture.pdfView
        let document = try #require(pdfView.document)
        // 投げる材料を先に用意する（検索を始める前に取る）。
        let stale = try #require(document.findString("page", withOptions: [.caseInsensitive]).first)
        #expect(stale.string?.lowercased() == "page")
        model.open()

        // 検索を始めた直後＝購読が生きている間に、別の検索語の一致を投げる。
        model.setQuery("needle")
        #expect(model.isSearching, "走行中でなければこのテストは何も検証していない")
        let before = model.matches.count
        NotificationCenter.default.post(
            name: .PDFDocumentDidFindMatch, object: document,
            userInfo: ["PDFDocumentFoundSelection": stale]
        )

        #expect(model.matches.count == before, "検索語の違う一致が混ざった")
    }

    /// 空の検索語ではハイライトも件数も出さない（web 面の `updateCount` と同じ）。
    @Test("検索語が空なら件数を出さない")
    func showsNoCountForEmptyQuery() {
        let fixture = makeFixture(pageCount: 3)
        let model = fixture.model
        model.open()

        #expect(model.countText == "")
        #expect(model.matches.isEmpty)
    }

    /// 閉じたら検索語もハイライトも捨てる。残すと、開き直したとき前の結果が出る。
    @Test("閉じると検索語とヒットを捨てる")
    func closingClearsState() async {
        let fixture = makeFixture(pageCount: 3)
        let model = fixture.model
        let pdfView = fixture.pdfView
        model.open()
        model.setQuery("needle")
        await waitForSearch(model)
        #expect(!model.matches.isEmpty)

        model.close()

        #expect(!model.isOpen)
        #expect(model.query.isEmpty)
        #expect(model.matches.isEmpty)
        #expect(pdfView.highlightedSelections == nil)
    }

    /// 文書が差し替わったら前の文書のヒットは無効。残すと、別の文書の位置を指す
    /// `PDFSelection` を抱えたまま次へ送ることになる。
    @Test("文書が差し替わるとヒットを捨てる")
    func documentChangeClearsMatches() async {
        let fixture = makeFixture(pageCount: 3)
        let model = fixture.model
        model.open()
        model.setQuery("needle")
        await waitForSearch(model)

        model.documentChanged()

        #expect(model.matches.isEmpty)
        #expect(model.countText == "0/0")
    }
}

/// 面へ映す色の割り当て（TASK-570）。
///
/// **現在の一致だけが別の色**になっていること、次へ送るとその色が移ることを見る。
/// 実機では「次へ送っても橙の位置が動かない」形で壊れた——同じ配列を
/// `highlightedSelections` へ入れ直しても PDFKit が再描画せず、`PDFSelection.color` の
/// 変更が反映されなかった。色の割り当て自体はここで固定できる。
@MainActor
@Suite
struct PDFFindHighlightTests {
    private func makeView(pageCount: Int) -> ZoomingPDFView {
        let document = PDFDocument()
        for index in 0 ..< pageCount {
            let data = NSMutableData()
            var box = NSRect(x: 0, y: 0, width: 612, height: 792)
            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { continue }
            context.beginPage(mediaBox: &box)
            let text = NSAttributedString(
                string: "page \(index) needle tail",
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            context.textPosition = CGPoint(x: 50, y: 700)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: index)
            }
        }
        let pdfView = ZoomingPDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        pdfView.present(document: document, rotation: 0, zoom: 1.0, scrollFraction: 0)
        return pdfView
    }

    @Test("現在の一致だけが他と違う色で塗られる")
    func onlyCurrentMatchGetsTheCurrentColor() throws {
        let pdfView = makeView(pageCount: 3)
        let document = try #require(pdfView.document)
        let matches = document.findString("needle", withOptions: [.caseInsensitive])
        #expect(matches.count == 3)

        pdfView.showFindMatches(matches, current: matches[1], scroll: false)

        let highlighted = try #require(pdfView.highlightedSelections)
        #expect(highlighted.count == 3)
        // 現在の 1 件だけが他と違う色。どの色かは面の実装が決めるので、
        // 「他と違う」ことだけを見る（色の値を書き写すとテストが実装の写経になる）。
        #expect(matches[1].color != matches[0].color)
        #expect(matches[0].color == matches[2].color)
    }

    /// 次へ送ったときに現在の色が移ること。
    @Test("次へ送ると現在の色が移る")
    func currentColorMovesWithSelection() throws {
        let pdfView = makeView(pageCount: 3)
        let document = try #require(pdfView.document)
        let matches = document.findString("needle", withOptions: [.caseInsensitive])

        pdfView.showFindMatches(matches, current: matches[0], scroll: false)
        let firstColor = matches[0].color
        pdfView.showFindMatches(matches, current: matches[1], scroll: false)

        #expect(matches[0].color != firstColor, "前の現在位置が通常の色へ戻っていない")
        #expect(matches[1].color == firstColor, "新しい現在位置が現在の色になっていない")
    }

    /// 消したらハイライトも消える。
    @Test("消すとハイライトが外れる")
    func clearingRemovesHighlights() throws {
        let pdfView = makeView(pageCount: 2)
        let document = try #require(pdfView.document)
        pdfView.showFindMatches(
            document.findString("needle", withOptions: [.caseInsensitive]), current: nil, scroll: false
        )
        #expect(pdfView.highlightedSelections != nil)

        pdfView.clearFindMatches()

        #expect(pdfView.highlightedSelections == nil)
    }
}
