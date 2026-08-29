import AppKit
import PDFKit

/// PDF の面のレイアウト規則。**「倍率 1.0 = ページの幅が画面に収まる状態」は
/// ここだけが知っている。**
///
/// `.singlePage` だった頃は「ページ全体が収まる状態」だった。連続スクロールでは
/// `scaleFactorForSizeToFit` が**幅基準**になるため、1.0 の意味もそちらへ移る
/// (実測: 面 400x500 / Letter で ページ高 517.65pt = 792 × 400/612)。
/// 縦に読み進める表示で高さも収めると、結局 1 ページずつ止まる表示に戻ってしまう
/// ので、幅フィットを既定とする(TASK-567)。
///
/// 換算を面の生成側(`PDFPreviewView`)と操作側(`PDFDocumentRenderer`)へ写すと、
/// 片方だけを直したときに「開いた直後の倍率」と「⌘0 の倍率」が静かにずれる。
/// どちらも同じ 1 つの規則を呼ぶ形にしておく(TASK-564.2)。
@MainActor
enum PDFSurfaceLayout {
    /// 面の基本設定。**全ページを縦に連ねて描く**(`.singlePageContinuous`)。
    ///
    /// 当初は `.singlePage` にして、ホイールをページ送りへ振り替えていた
    /// (TASK-564.2)。「2 ページの端が同時に見える位置で止まらない」ことを
    /// 構造で守れるのが理由だったが、その代償としてスクロールでページが瞬時に
    /// 切り替わり、滑らかに読めなかった。**体感を優先してこの不変条件を捨てる**
    /// (TASK-567)。止め方の仕掛け(スナップ・遷移アニメーション)は足さない。
    /// 不変条件を守るために機構を増やすのは単純化の逆方向であるため。
    static func configure(_ pdfView: PDFView) {
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        // ページ全体が収まる倍率へ自動追従する。ウィンドウをリサイズしても
        // フィットし続け、ユーザーが倍率を変えた時点で下の apply が false にする。
        pdfView.autoScales = true
    }

    /// 面の内側のスクロールビュー(`PDFScrollView`)。検証からも見たいので internal。
    static func scrollView(in pdfView: PDFView) -> NSScrollView? {
        if let fromDocument = pdfView.documentView?.enclosingScrollView { return fromDocument }
        var pending = pdfView.subviews
        while let view = pending.first {
            pending.removeFirst()
            if let scrollView = view as? NSScrollView { return scrollView }
            pending.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// ページの幅が収まる倍率(連続スクロールでの `scaleFactorForSizeToFit`)。
    /// ページがまだ無い間は 0 が返るので等倍として扱う。
    static func fitScale(of pdfView: PDFView) -> Double {
        let fit = pdfView.scaleFactorForSizeToFit
        return fit > 0 ? fit : 1
    }

    /// いまの倍率(1.0 = フィット)。
    static func currentZoom(of pdfView: PDFView) -> Double {
        pdfView.scaleFactor / fitScale(of: pdfView)
    }

    /// 文書全体に残っている縦スクロールの余地(文書座標)。
    ///
    /// 連続スクロールでは documentView が全ページ分の高さを持つので、これは
    /// 「いまのページの中の余地」ではなく**文書全体の余地**である(TASK-567)。
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
    /// 0…1 で表す。連続スクロールにした PDF も 1 本のスクロールなので、
    /// **同じ式**(スクロール量 / 余地)で表せる。ページ番号を混ぜる必要は無い
    /// (TASK-567 でページ単位の換算を撤去した。`.singlePage` 時代は
    /// `(ページ番号 + ページ内の位置) / 総ページ数` で畳んでいたが、連続スクロールでは
    /// ページ内の位置が文書全体の割合に化けるため二重計上になる)。
    ///
    /// PDF 専用の記憶機構を作らないという約束(TASK-564.3)はそのまま保たれ、
    /// 値は `WindowPresentationMemory` の既存の表へ乗る。
    static func documentFraction(of pdfView: PDFView) -> Double {
        guard let scrollView = pdfView.documentView?.enclosingScrollView else { return 0 }
        let room = verticalScrollRoom(of: pdfView)
        guard room > 0 else { return 0 }
        return min(max(scrollView.contentView.bounds.origin.y / room, 0), 1)
    }

    /// 文書全体に対する表示位置(0…1)を復元する。
    ///
    /// ページ数が減って記憶した位置が範囲外になっても、**余地の割合で復元する**ので
    /// 行き先は必ず文書の中に収まる(TASK-564.3 の AC #4)。ページ番号で丸めていた
    /// 頃の分岐は要らない。
    static func restore(fraction: Double, in pdfView: PDFView) {
        guard let scrollView = pdfView.documentView?.enclosingScrollView else { return }
        let room = verticalScrollRoom(of: pdfView)
        guard room > 0 else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = room * min(max(fraction, 0), 1)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 表示を 90 度単位で回す。**文書全体を回す**(現在ページだけではない)。
    ///
    /// 横向きにスキャンされた PDF は文書ごと横倒しになっているのが普通で、
    /// ページ単位だとページを送るたびに回し直すことになる。ページごとに向きが
    /// 混在する PDF では一部が正しくならないが、そちらは例外的な形なので、
    /// 「1 回の操作で読める状態になる」ほうを採る(TASK-564.5)。
    ///
    /// 倍率はここで触らない。`autoScales` が有効な間は、縦横比が変わった時点で
    /// `PDFView` がフィットし直す(TASK-564.2 の AC #2)。
    static func rotate(byDegrees degrees: Int, in pdfView: PDFView) {
        guard let document = pdfView.document else { return }
        let zoom = currentZoom(of: pdfView)
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            page.rotation = normalized(page.rotation + degrees)
        }
        // **`autoScales` は回転では効き直さない。** 実測(400x500 の面 / Letter 1 ページ):
        // 回転すると `scaleFactorForSizeToFit` は 0.617 → 0.495 へ更新されるのに
        // `scaleFactor` は 0.617 のまま残り、ページ(488pt 幅)が面(400pt)からはみ出す。
        // 自動追従が働くのは面のリサイズのときだけで、ページの寸法が変わったときではない。
        //
        // 再レイアウトそのものは PDFKit がメインキューへ積む(`PDFPage.rotation` の
        // 変更が didRotatePage の通知を出す)ので、倍率の入れ直しも同じキューへ**後から**
        // 積む。ここで同期に入れ直すと、まだ古い `scaleFactorForSizeToFit` を読む。
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // 回転前の倍率(1.0 = フィット)をそのまま維持する。フィットで見ていた
                // なら回転後もフィット、拡大していたなら同じ拡大率のまま。
                apply(zoom: zoom, to: pdfView, forcingRefit: true)
            }
        }
    }

    /// いまの回転角(0 / 90 / 180 / 270)。文書全体を回すので、先頭ページを代表として読む。
    static func rotation(of pdfView: PDFView) -> Int {
        guard let page = pdfView.document?.page(at: 0) else { return 0 }
        return normalized(page.rotation)
    }

    /// 記憶していた回転角へ合わせる(差分だけ回す)。
    static func apply(rotation: Int, to pdfView: PDFView) {
        let delta = normalized(rotation) - self.rotation(of: pdfView)
        guard delta != 0 else { return }
        rotate(byDegrees: delta, in: pdfView)
    }

    /// 0 / 90 / 180 / 270 へ丸める。`PDFPage.rotation` は負の値も受け付けるが、
    /// 記憶と比較のためにここで正規化しておく。
    static func normalized(_ degrees: Int) -> Int {
        let wrapped = degrees % 360
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// 倍率を適用する。フィット(既定倍率)へ戻すときは `autoScales` を戻し、
    /// 以後のリサイズにも追従させる(⌘0 が「この面での基準状態へ戻す」になる)。
    static func apply(zoom: Double, to pdfView: PDFView, forcingRefit: Bool = false) {
        guard zoom != ZoomStore.defaultZoom else {
            // 既に true のまま入れ直しても再フィットしないため、いったん外して戻す
            // (回転後の入れ直しで必要 / 実測は rotate の doc)。
            if forcingRefit { pdfView.autoScales = false }
            pdfView.autoScales = true
            return
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = fitScale(of: pdfView) * zoom
    }
}
