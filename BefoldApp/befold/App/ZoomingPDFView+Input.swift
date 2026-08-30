import PDFKit

/// `ZoomingPDFView` の入力(ピンチ・Ctrl+ホイール・キーボード)。
///
/// **面へ書くのは従来どおり `apply(zoom:)` と `scrollSmoothly(by:)` を通す**。
/// ここが直接 `scaleFactor` や `bounds` を触ることはない。
///
/// ピンチの受け皿そのものは別の型が持つ(`PDFMagnificationGesture` / TASK-577)。
/// こちらに残るのは、その増分と Ctrl+ホイールが合流する `applyZoom(scaledBy:)` と、
/// AppKit のオーバーライドとして面に居るしかない `magnify` / `scrollWheel` / `keyDown`。
extension ZoomingPDFView {
    /// トラックパッドのピンチ。
    ///
    /// **こちらは補助の経路。** 主経路は上の認識器で、`magnify` が呼ばれるには
    /// 内側のスクロールビューの `allowsMagnification` が切れている必要がある
    /// (切るのは `layout`)。既定のままだと `PDFScrollView` がジェスチャを
    /// 消費してここへ届かない(TASK-568 の実測)。
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

    /// キーボードのスクロールを**滑らかな**スクロールにする。
    ///
    /// `PDFView` の既定はページ単位のジャンプで、連続スクロールにした後も
    /// キー操作だけ非連続なまま残る(TASK-567 のユーザー報告)。アニメーションで
    /// 送ると、トラックパッドの操作感と揃う。
    ///
    /// **キーと送り量の対応は `PDFSurfaceLayout` が持つ**(web 面と同じ割り当て /
    /// TASK-577)。ここは Cmd を `super` へ逃がすことと、解決できたら送ることだけを行う。
    /// Cmd を渡すのはメニューのキーエクイバレントを奪わないため。
    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers ?? ""
        guard !event.modifierFlags.contains(.command),
              let scroll = PDFSurfaceLayout.keyboardScroll(
                  forKey: key, shift: event.modifierFlags.contains(.shift)
              )
        else {
            super.keyDown(with: event)
            return
        }
        scrollSmoothly(by: PDFSurfaceLayout.scrollAmount(for: scroll, in: self))
    }

    /// いまの倍率へ係数を掛けて適用し、窓へ伝える。上下限は `ZoomStore` と共有する。
    /// ピンチと Ctrl+ホイールの入口が両方ここへ収斂する(倍率の意味と上下限を
    /// 入口ごとに書かないため)。`NSEvent` を作らずに検証できるよう internal。
    func applyZoom(scaledBy factor: Double) {
        let scaled = min(max(PDFSurfaceLayout.currentZoom(of: self) * factor, minZoom), maxZoom)
        apply(zoom: scaled)
        onZoomChanged?(scaled)
    }
}
