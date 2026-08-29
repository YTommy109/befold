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
    /// 1 回のジェスチャで送るページ数を 1 に抑えるための積算。
    private var accumulatedDelta: CGFloat = 0
    /// これを超えたら 1 ページ送る。トラックパッドの微小な揺れで送らないための閾値。
    private static let pageTurnThreshold: CGFloat = 20

    override func scrollWheel(with event: NSEvent) {
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

    /// いま表示しているページの中にスクロールの余地があるか。
    /// 余地があるならページ送りではなく通常のスクロールを行う。
    /// 余地の測り方は `PDFSurfaceLayout` が持つ(スクロール位置の取得と同じ規則)。
    var hasScrollRoom: Bool {
        PDFSurfaceLayout.verticalScrollRoom(of: self) > 1
    }
}
