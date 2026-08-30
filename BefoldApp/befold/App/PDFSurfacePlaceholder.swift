import AppKit
import PDFKit

/// 文書を差し替えた直後、**タイルが載るまでのあいだだけ**面の上に見せる静止画。
///
/// PDFKit はページの中身をバックグラウンドのタイルプールで非同期に描く。`PDFView` の
/// 描画はタイルを待たずに戻るため、届くまで面は地の色のままになる。これが切り替え直後に
/// 見える白紙で、実測（TASK-569 / 150 ページ・18 回）では 14〜67ms、**18 回中 3 回は
/// 252〜268ms** 続いた。速さではなくこのばらつきが体感を悪くしていた。
///
/// **タイルが載った瞬間を知る手段は無い。** `PDFPageView` の layer もその sublayer も
/// `contents` は nil のまま（タイルは IOSurface へ直接行く）で、`PDFView.draw(_ page:to:)` の
/// override は `super` が `@MainActor` のため呼べない（どちらも実測済み）。そこで
/// **「いつ載ったか」を知ろうとせず、「載っても困らない絵を先に置く」**形にしてある。
/// 静止画は下に描かれる内容と同じなので、外れるのが遅れても見た目は変わらない。
///
/// 外す条件は面が動く事実だけで決める（時間ではない）。唯一の時間による上限は
/// `expiry` で、これは正しさではなく「万一ずれたときに固まらない」ための保険。
@MainActor
final class PDFSurfacePlaceholder {
    /// 外れないまま残る上限。実測の最悪値 268ms に対する余裕として置く。
    /// **正しさには効かない**（上の doc を参照）。
    static let expiryDelay: TimeInterval = 0.4

    /// いま載せている静止画。**面ごとに 1 枚しか存在しない**（stored property が 1 本で、
    /// `install` が必ず古いものを外してから載せるため）。連続でカーソルキーを送って
    /// `updateNSView` が追い越されても、前のファイルの絵が残らない。
    private var imageView: NSImageView?
    /// 載せた時点の面の寸法。これが変われば絵は合わなくなるので外す。
    private var installedBounds: NSRect = .zero
    private var scrollObserver: NSObjectProtocol?
    private var expiry: Timer?

    /// いま静止画を載せているか。検証から見たいので internal。
    var isShowing: Bool {
        imageView != nil
    }

    /// 面が見せている内容をそのまま焼いて上に載せる。**古いものは必ず先に外す。**
    ///
    /// 呼ぶのは倍率・回転・表示位置が確定した後（`layoutSubtreeIfNeeded()` の後）。
    /// 確定前に呼ぶと、フィット前の倍率で焼いた絵が残る。
    func install(on pdfView: PDFView) {
        dismiss()
        guard pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return }
        guard let (image, area) = render(pdfView) else { return }

        let view = NSImageView(frame: area)
        view.image = image
        view.imageScaling = .scaleNone
        // 触れないようにする。静止画は見せるためだけのもので、選択もリンクも下が受ける。
        view.isEnabled = false
        pdfView.addSubview(view, positioned: .above, relativeTo: nil)
        imageView = view
        installedBounds = pdfView.bounds
        observeScroll(of: pdfView)
        expiry = Timer.scheduledTimer(withTimeInterval: Self.expiryDelay, repeats: false) { _ in
            MainActor.assumeIsolated { self.dismiss() }
        }
    }

    /// 静止画を外す。**何度呼んでもよい。**
    func dismiss() {
        imageView?.removeFromSuperview()
        imageView = nil
        installedBounds = .zero
        expiry?.invalidate()
        expiry = nil
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
    }

    /// 面のレイアウトが走ったことを伝える。**寸法が変わったときだけ**外す。
    ///
    /// 「次の `layout()` で外す」にはできない。載せた直後にもう一度レイアウトが
    /// 走ることがあり、それで外すと白紙が戻る（TASK-569 の設計レビュー項目 5）。
    func noteLayout(of pdfView: PDFView) {
        guard let imageView else { return }
        guard pdfView.bounds == installedBounds else {
            dismiss()
            return
        }
        // **毎回いちばん上へ上げ直す。** PDFKit はレイアウトのたびに自分の
        // サブビューを積み直すので、載せたときだけ最前面にしても下へ潜る
        // （実測: 18 回中 2 回だけ静止画が見えず 222〜238ms の白紙が残った / TASK-569）。
        pdfView.addSubview(imageView, positioned: .above, relativeTo: nil)
    }

    // MARK: - Private

    /// 面が見せている可視ページを、面の座標系のまま焼く。
    ///
    /// **位置・倍率・回転は PDFKit から取る**（`pdfView.convert(_:from:)`）。こちらで
    /// 計算し直すと `PDFSurfaceLayout` のレイアウト規則が二重化する。
    ///
    /// 焼くのは**ページが占める矩形だけ**で、面全体ではない。面全体だと 1047x897 の
    /// 2 倍解像度で 15MB を確保することになり、実測で install が 15.6ms かかった
    /// （切り替え全体の中央値がその分だけ悪化する）。
    private func render(_ pdfView: PDFView) -> (NSImage, NSRect)? {
        let pages = visiblePages(of: pdfView)
        guard !pages.isEmpty else { return nil }
        let rects = pages.map { (page: $0, rect: pdfView.convert($0.bounds(for: pdfView.displayBox), from: $0)) }
        let area = rects.reduce(NSRect.null) { $0.union($1.rect) }.intersection(pdfView.bounds)
        guard area.width > 1, area.height > 1 else { return nil }

        let scale = pdfView.window?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(area.width * scale), pixelsHigh: Int(area.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = area.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.translateBy(x: -area.minX, y: -area.minY)
        for entry in rects {
            draw(entry.page, rect: entry.rect, box: pdfView.displayBox, to: context)
        }

        let image = NSImage(size: area.size)
        image.addRepresentation(rep)
        return (image, area)
    }

    /// 1 ページを、面の座標系での矩形へ直接描く。
    ///
    /// **中間の `NSImage` を挟まない。** `thumbnail(of:for:)` はポイント寸法で
    /// ラスタライズするため、2 倍解像度のビットマップへ描くと拡大されてぼやける。
    private func draw(_ page: PDFPage, rect: NSRect, box: PDFDisplayBox, to context: CGContext) {
        let pageBounds = page.bounds(for: box)
        guard rect.width > 0, rect.height > 0, pageBounds.width > 0, pageBounds.height > 0
        else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // ページの地は白。`PDFPage.draw` は中身しか描かない。
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / pageBounds.width, y: rect.height / pageBounds.height)
        // ページ座標の原点は 0 とは限らない。ここを忘れると中身が矩形の外へ出て
        // 白紙のままになる（実測 / TASK-569）。
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: box, to: context)
    }

    /// いま面に見えているページ。
    ///
    /// **`PDFView.visiblePages` は使えない。** 文書を入れて `layoutSubtreeIfNeeded()` を
    /// 済ませた直後でもまだ空を返す（実測: 常に 0 件 / TASK-569）。面の上の点から
    /// PDFKit 自身に引かせる `page(for:nearest:)` なら、この時点でも答えが返る。
    private func visiblePages(of pdfView: PDFView) -> [PDFPage] {
        var pages: [PDFPage] = []
        let bounds = pdfView.bounds
        // 縦に等間隔で当てる。連続スクロールで同時に見えるのはせいぜい数ページなので、
        // 5 点あれば取りこぼさない（境目のページも中央の点で拾える）。
        for step in 0 ... 4 {
            let point = NSPoint(x: bounds.midX, y: bounds.minY + bounds.height * Double(step) / 4)
            guard let page = pdfView.page(for: point, nearest: true) else { continue }
            if !pages.contains(page) { pages.append(page) }
        }
        return pages
    }

    private func draw(_ page: PDFPage, in pdfView: PDFView, to context: CGContext) {
        let box = pdfView.displayBox
        let pageBounds = page.bounds(for: box)
        let rect = pdfView.convert(pageBounds, from: page)
        guard rect.width > 0, rect.height > 0, pageBounds.width > 0, pageBounds.height > 0
        else { return }
        // ページの地は白。`thumbnail` は余白を透明にすることがあるので先に敷く。
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        // **`PDFPage.draw(with:to:)` は使わない。** ページの座標原点が 0 でない文書で
        // 位置がずれ、中身が矩形の外へ出た（実測: 白紙のまま / TASK-569）。
        // `thumbnail` は回転も原点も PDFKit 側で解決してくれる。
        let thumbnail = page.thumbnail(of: rect.size, for: box)
        thumbnail.draw(in: rect)
    }

    /// スクロールしたら外す。静止画は止まっているので、動いた瞬間からずれる。
    private func observeScroll(of pdfView: PDFView) {
        guard let clipView = PDFSurfaceLayout.scrollView(in: pdfView)?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }
}
