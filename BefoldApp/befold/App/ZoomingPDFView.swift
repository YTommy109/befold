import PDFKit

/// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)を受け取る `PDFView`。
///
/// スクロールそのものは `PDFView` に任せる。かつてはホイールをページ送りへ
/// 振り替えていたが(`PagingPDFView` / TASK-564.2)、連続スクロールへ改めた時点で
/// 不要になった(TASK-567)。
final class ZoomingPDFView: PDFView {
    /// ピンチ・Ctrl+ホイールで倍率が変わったことを窓へ伝える。メニュー経由の
    /// ⌘+ / ⌘- / ⌘0 は `WebViewCommandController` が返り値で伝えるので、ここは
    /// **面の中で完結する操作だけ**の通知口(TASK-564.4)。
    var onZoomChanged: ((Double) -> Void)?
    /// 倍率の上下限。`ZoomStore` と同じ値を使い、面ごとに範囲が違う状態を作らない。
    private let minZoom = ZoomStore.minZoom
    private let maxZoom = ZoomStore.maxZoom

    /// **内側のスクロールビューの拡大縮小をここで切る。** 切らないと
    /// `PDFScrollView` がピンチを消費し、下の `magnify` へ届かない(TASK-568)。
    ///
    /// 設定の入れ場所を `PDFSurfaceLayout.configure` にはしない。`configure` は
    /// 文書を入れる前に呼ばれ、そのときスクロールビューはまだ無い。文書の
    /// 差し替えで作り直されることもある。**レイアウトのたびに入れ直す**のが、
    /// 呼ぶ順番に依存しない唯一の形(実測: configure だけだと true のまま残る)。
    override func layout() {
        super.layout()
        PDFSurfaceLayout.scrollView(in: self)?.allowsMagnification = false
    }

    /// トラックパッドのピンチ。
    ///
    /// **これが呼ばれるには、内側のスクロールビューの `allowsMagnification` を
    /// 切っておく必要がある**(`PDFSurfaceLayout.configure`)。既定のままだと
    /// `PDFScrollView` がジェスチャを消費してここへ届かない(TASK-568 の実測)。
    override func magnify(with event: NSEvent) {
        applyZoom(scaledBy: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ctrl+ホイールは拡大縮小(viewer.js の _mmdWheelZoom と同じ約束)。
        guard event.modifierFlags.contains(.control) else {
            super.scrollWheel(with: event)
            return
        }
        applyZoom(scaledBy: 1 + event.scrollingDeltaY / 100)
    }

    /// いまの倍率へ係数を掛けて適用し、窓へ伝える。上下限は `ZoomStore` と共有する。
    /// ピンチと Ctrl+ホイールの入口が両方ここへ収斂する(倍率の意味と上下限を
    /// 入口ごとに書かないため)。`NSEvent` を作らずに検証できるよう internal。
    func applyZoom(scaledBy factor: Double) {
        let zoom = min(max(PDFSurfaceLayout.currentZoom(of: self) * factor, minZoom), maxZoom)
        PDFSurfaceLayout.apply(zoom: zoom, to: self)
        onZoomChanged?(zoom)
    }
}
