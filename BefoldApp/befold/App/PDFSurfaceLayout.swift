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
