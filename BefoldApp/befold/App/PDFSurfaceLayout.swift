import AppKit
import PDFKit

/// PDF の面のレイアウト規則。**「倍率 1.0 = ページ全体が画面に収まる状態」は
/// ここだけが知っている。**
///
/// **ここには面を変更する操作を置かない（TASK-574.1）。** 換算（面を読んで値を返す）
/// だけを持ち、面への書き込みは `ZoomingPDFView` のメソッドが担う。かつては両方を
/// 抱えており、倍率を書き込む口が複数に割れて順序バグの温床になった（TASK-572）。
/// WebView 面が「実行する `ViewerRenderer` + 純関数の `ContentUpdatePlanner`」に
/// 分かれているのと同じ分業で、こちらが planner 側にあたる。
///
/// `PDFView` 任せにはできない。連続スクロールでの `scaleFactorForSizeToFit` は
/// **幅基準**で、ページの下端が画面外に出る(実測: 面 400x500 / Letter で
/// ページ高 517.65pt = 792 × 400/612)。`scaleFactorForSizeToFit` を override しても
/// `autoScales` はその値を読まない(実測: 回転後に幅基準へ戻る)。そのため
/// `autoScales` を使わず、`fitScale` が縦にも収まる側を返す(TASK-567)。
///
/// 換算を面の生成側(`PDFPreviewView`)と操作側(`PDFDocumentRenderer`)へ写すと、
/// 片方だけを直したときに「開いた直後の倍率」と「⌘0 の倍率」が静かにずれる。
/// どちらも同じ 1 つの規則を呼ぶ形にしておく(TASK-564.2)。
@MainActor
enum PDFSurfaceLayout {
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

    /// **ページ全体が面に収まる倍率。** フィットの定義はここだけが持つ。
    ///
    /// `PDFView` 任せにしない。連続スクロールでの `scaleFactorForSizeToFit` は
    /// 幅基準で、縦は画面外へ続いてしまう。縦にも収まる側（幅と高さの小さいほう）を
    /// 採る(TASK-567 / ユーザーの期待は縦フィット)。
    /// ページも面もまだ無い間は等倍として扱う。
    static func fitScale(of pdfView: PDFView) -> Double {
        let pageSize = largestPageSize(in: pdfView)
        let available = NSSize(
            width: pdfView.bounds.width - pageMargin, height: pdfView.bounds.height - pageMargin
        )
        guard pageSize.width > 0, pageSize.height > 0, available.width > 0, available.height > 0
        else { return 1 }
        return min(available.width / pageSize.width, available.height / pageSize.height)
    }

    /// 文書の中でいちばん大きいページの寸法（回転後）。
    ///
    /// **現在のページではなく文書全体で決める。** 連続スクロールでページごとに
    /// フィットし直すと、スクロールしている最中に倍率が動く。いちばん大きい
    /// ページに合わせておけば、どのページも収まったまま倍率が変わらない。
    static func largestPageSize(in pdfView: PDFView) -> NSSize {
        guard let document = pdfView.document else { return .zero }
        var largest = NSSize.zero
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: pdfView.displayBox).size
            // `bounds(for:)` は回転を反映しない。90 / 270 度では縦横が入れ替わる。
            let rotated = normalized(page.rotation) % 180 == 0
                ? box : NSSize(width: box.height, height: box.width)
            largest.width = max(largest.width, rotated.width)
            largest.height = max(largest.height, rotated.height)
        }
        return largest
    }

    /// ページの周りに `PDFView` が描く余白と枠の分（実測で 5pt 前後）。
    /// これを引かないと、フィットのはずのページが 1〜2pt はみ出す。
    private static let pageMargin: Double = 12

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
        return min(max(1 - scrollView.contentView.bounds.origin.y / room, 0), 1)
    }

    /// **`PDFView` のスクロール座標は下へ行くほど y が小さい**（実測:
    /// `documentView.isFlipped == false`。開いた直後 y = 2394.5 = 余地いっぱい、
    /// 最終ページで y ≈ 0）。web の面は 0 = 先頭なので、ここで向きを合わせる。
    /// 合わせないと表示位置の記憶が上下反転し、スペースキーの送り方向も逆になる。
    static func scrollOffset(forFraction fraction: Double, room: Double) -> Double {
        room * (1 - min(max(fraction, 0), 1))
    }

    /// いま見えている高さ(文書座標)。
    static func visibleHeight(of pdfView: PDFView) -> Double {
        guard let scrollView = scrollView(in: pdfView) else { return pdfView.bounds.height }
        return scrollView.contentView.bounds.height
    }

    /// キーボードで 1 回に送る割合。少し重ねて送ると読んでいた行が画面に残る。
    static let keyboardScrollOverlap: Double = 0.9

    /// いまの回転角(0 / 90 / 180 / 270)。文書全体を回すので、先頭ページを代表として読む。
    static func rotation(of pdfView: PDFView) -> Int {
        guard let page = pdfView.document?.page(at: 0) else { return 0 }
        return normalized(page.rotation)
    }

    /// 0 / 90 / 180 / 270 へ丸める。`PDFPage.rotation` は負の値も受け付けるが、
    /// 記憶と比較のためにここで正規化しておく。
    static func normalized(_ degrees: Int) -> Int {
        let wrapped = degrees % 360
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// その倍率のときに `PDFView` へ入るべき絶対倍率。**換算式はここだけ。**
    /// 適用側(`ZoomingPDFView.apply(zoom:)`)とレイアウトでの入れ直し
    /// (`ZoomingPDFView.layout`)が別々に掛け算を書くと、片方だけ直したときに静かにずれる。
    static func expectedScaleFactor(of pdfView: PDFView, zoom: Double) -> Double {
        fitScale(of: pdfView) * zoom
    }
}
