import PDFKit

/// PDF の面のレイアウト規則。**「倍率 1.0 = ページ全体が画面に収まる状態」は
/// ここだけが知っている。**
///
/// 換算を面の生成側(`PDFPreviewView`)と操作側(`PDFDocumentRenderer`)へ写すと、
/// 片方だけを直したときに「開いた直後の倍率」と「⌘0 の倍率」が静かにずれる。
/// どちらも同じ 1 つの規則を呼ぶ形にしておく(TASK-564.2)。
@MainActor
enum PDFSurfaceLayout {
    /// 面の基本設定。**1 ページずつ描く**(`.singlePage`)。
    ///
    /// 連続スクロール(`.singlePageContinuous`)にすると、2 ページの端が同時に
    /// 見える位置で止まらないようにする仕掛けを別に作ることになる。
    /// `.singlePage` はそもそも 2 ページを同時に描かないので、構造で守れる。
    static func configure(_ pdfView: PDFView) {
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        // ページ全体が収まる倍率へ自動追従する。ウィンドウをリサイズしても
        // フィットし続け、ユーザーが倍率を変えた時点で下の apply が false にする。
        pdfView.autoScales = true
    }

    /// ページ全体が収まる倍率。ページがまだ無い間は 0 が返るので等倍として扱う。
    static func fitScale(of pdfView: PDFView) -> Double {
        let fit = pdfView.scaleFactorForSizeToFit
        return fit > 0 ? fit : 1
    }

    /// いまの倍率(1.0 = フィット)。
    static func currentZoom(of pdfView: PDFView) -> Double {
        pdfView.scaleFactor / fitScale(of: pdfView)
    }

    /// いま表示しているページの中に残っている縦スクロールの余地(文書座標)。
    ///
    /// **スクロールビューの `contentSize` と比べてはならない。** `PDFView` は
    /// 倍率をスクロールビューの magnification で表すため、`documentView.bounds` は
    /// 倍率のかからないページ座標のまま。`contentSize`(ピクセル)と引き算すると、
    /// フィット表示でも余地があるように見える(実測: 811 - 500 = 311)。
    /// 可視領域は clip view の bounds が同じ文書座標で持っている
    /// (実測: フィット時 811 = ページ全体、2 倍時 405.5 = 半分)。
    static func verticalScrollRoom(of pdfView: PDFView) -> Double {
        guard let scrollView = pdfView.documentView?.enclosingScrollView,
              let documentView = scrollView.documentView
        else { return 0 }
        return documentView.bounds.height - scrollView.contentView.bounds.height
    }

    /// 文書全体に対する表示位置(0…1)。
    ///
    /// **web の面と同じ意味の値を返す。** あちらは文書を 1 本のスクロールとして
    /// 0…1 で表すので、PDF も「何ページ目のどこか」を同じ 0…1 に畳む
    /// （`(ページ番号 + ページ内の位置) / 総ページ数`）。こうすると PDF 専用の
    /// 記憶機構が要らず、`WindowPresentationMemory` の既存の表へそのまま乗る
    /// (TASK-564.3 の「PDF 専用の記憶機構を新設しない」)。
    static func documentFraction(of pdfView: PDFView) -> Double {
        guard let document = pdfView.document, document.pageCount > 0,
              let page = pdfView.currentPage
        else { return 0 }
        let index = document.index(for: page)
        return (Double(index) + inPageFraction(of: pdfView)) / Double(document.pageCount)
    }

    /// 文書全体に対する表示位置(0…1)を復元する。
    ///
    /// ページ数が減って記憶した位置が範囲外になったら、**最後のページへ丸める**
    /// (TASK-564.3 の AC #4)。丸めずに `go(to:)` へ渡すと、別文書のページを指す
    /// 行き先になる。
    static func restore(fraction: Double, in pdfView: PDFView) {
        guard let document = pdfView.document, document.pageCount > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let index = min(Int(clamped * Double(document.pageCount)), document.pageCount - 1)
        guard let page = document.page(at: index) else { return }
        pdfView.go(to: page)
        let inPage = clamped * Double(document.pageCount) - Double(index)
        scroll(toInPageFraction: inPage, in: pdfView)
    }

    /// 倍率を適用する。フィット(既定倍率)へ戻すときは `autoScales` を戻し、
    /// 以後のリサイズにも追従させる(⌘0 が「この面での基準状態へ戻す」になる)。
    static func apply(zoom: Double, to pdfView: PDFView) {
        guard zoom != ZoomStore.defaultZoom else {
            pdfView.autoScales = true
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = fitScale(of: pdfView) * zoom
    }
}

// MARK: - ページ内の位置

private extension PDFSurfaceLayout {
    /// いま表示しているページの中での縦位置(0…1)。余地が無ければ 0。
    static func inPageFraction(of pdfView: PDFView) -> Double {
        guard let scrollView = pdfView.documentView?.enclosingScrollView else { return 0 }
        let room = verticalScrollRoom(of: pdfView)
        guard room > 0 else { return 0 }
        return min(max(scrollView.contentView.bounds.origin.y / room, 0), 1)
    }

    /// ページ内の縦位置(0…1)へスクロールする。余地が無ければ何もしない。
    static func scroll(toInPageFraction fraction: Double, in pdfView: PDFView) {
        guard let scrollView = pdfView.documentView?.enclosingScrollView else { return }
        let room = verticalScrollRoom(of: pdfView)
        guard room > 0 else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = room * min(max(fraction, 0), 1)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
