import PDFKit

/// ホイール操作をページ送りへ振り替える `PDFView`。
///
/// `.singlePage` ではページ全体が収まっている間スクロールの余地が無く、
/// **ホイールを回しても何も起きない**。「ページ単位のスクロール」を成立させる
/// ため、余地が無いときだけ次ページ / 前ページへ送る(TASK-564.2)。
///
/// 拡大してページ内にスクロールの余地があるときは、通常のスクロールを優先する
/// (ページ内を見終わる前に次ページへ飛ばさない)。
final class PagingPDFView: PDFView {
    /// ピンチ・Ctrl+ホイールで倍率が変わったことを窓へ伝える。メニュー経由の
    /// ⌘+ / ⌘- / ⌘0 は `WebViewCommandController` が返り値で伝えるので、ここは
    /// **面の中で完結する操作だけ**の通知口(TASK-564.4)。
    var onZoomChanged: ((Double) -> Void)?
    /// 倍率の上下限。`ZoomStore` と同じ値を使い、面ごとに範囲が違う状態を作らない。
    private let minZoom = ZoomStore.minZoom
    private let maxZoom = ZoomStore.maxZoom

    /// 1 回のジェスチャで送るページ数を 1 に抑えるための積算。
    private var accumulatedDelta: CGFloat = 0
    /// これを超えたら 1 ページ送る。トラックパッドの微小な揺れで送らないための閾値。
    private static let pageTurnThreshold: CGFloat = 20

    /// トラックパッドのピンチ。`PDFView` の既定実装は `scaleFactor` を直接動かすため、
    /// そのままだと窓のライブ値・保存値と食い違う。ここで受けて倍率の意味
    /// (1.0 = フィット)へ通し、変化を窓へ伝える。
    override func magnify(with event: NSEvent) {
        applyZoom(scaledBy: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ctrl+ホイールは拡大縮小(viewer.js の _mmdWheelZoom と同じ約束)。
        if event.modifierFlags.contains(.control) {
            applyZoom(scaledBy: 1 + event.scrollingDeltaY / 100)
            return
        }
        guard !hasScrollRoom else {
            accumulatedDelta = 0
            super.scrollWheel(with: event)
            return
        }
        // 慣性(指を離した後に届く残りのイベント)では送らない。送ると 1 回の
        // フリックで何ページも飛ぶ。
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) { accumulatedDelta = 0 }
        accumulatedDelta += event.scrollingDeltaY
        guard abs(accumulatedDelta) >= Self.pageTurnThreshold else { return }
        // 下へスクロール(deltaY が負)で次ページ。
        if accumulatedDelta < 0 { goToNextPage(nil) } else { goToPreviousPage(nil) }
        accumulatedDelta = 0
    }

    /// いまの倍率へ係数を掛けて適用し、窓へ伝える。上下限は `ZoomStore` と共有する。
    /// ピンチと Ctrl+ホイールの入口が両方ここへ収斂する(倍率の意味と上下限を
    /// 入口ごとに書かないため)。`NSEvent` を作らずに検証できるよう internal。
    func applyZoom(scaledBy factor: Double) {
        let zoom = min(max(PDFSurfaceLayout.currentZoom(of: self) * factor, minZoom), maxZoom)
        PDFSurfaceLayout.apply(zoom: zoom, to: self)
        onZoomChanged?(zoom)
    }

    /// いま表示しているページの中にスクロールの余地があるか。
    /// 余地があるならページ送りではなく通常のスクロールを行う。
    /// 余地の測り方は `PDFSurfaceLayout` が持つ(スクロール位置の取得と同じ規則)。
    var hasScrollRoom: Bool {
        PDFSurfaceLayout.verticalScrollRoom(of: self) > 1
    }
}
