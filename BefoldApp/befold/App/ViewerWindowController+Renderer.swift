import BefoldKit
import BefoldRenderKit
import Foundation

// MARK: - ViewerRendererDelegate

/// 描画側(WKWebView 上の `ViewerRenderer`)から上がってくる通知——倍率変更・
/// スクロール位置変更・参照のアクティベーション・追記要求——の受け口。
///
/// 通知はどれも**遅れて届きうる**ため、この層の共通の作法は
/// 「通知が載せてきた URL を保存キーにし、現在の表示対象と一致するときだけライブ値へ反映する」。
/// 現在の `fileURL` を保存キーに使わないこと(TASK-391 / TASK-400)。
@MainActor
extension ViewerWindowController: ViewerRendererDelegate {
    /// 保存キーは現在表示中の fileURL ではなく、通知に載った「その倍率が属する文書」から
    /// 決める(スクロール位置と同じ理由 / TASK-391)。nil の通知は捨てる。
    ///
    /// ライブ値と保存値の両方を更新する。保存値は次にこの文書を開くときの既定値で、
    /// いま画面に出ている倍率を決めるのはライブ値のほう(ADR 0002)。ただしライブ値は
    /// 「いまこの窓が出している文書」の倍率なので、出所が現在の文書と違う遅延通知
    /// (切替直後に届いた切替前の文書の通知)では更新しない。保存だけを出所のキーへ行う。
    func renderer(_: ViewerRenderer, didChangeZoom zoom: Double, for url: URL?) {
        guard let url else { return }
        if url.normalizedPathKey == fileURL.normalizedPathKey {
            store.zoom = zoom
        }
        perFileState.zoom.setZoom(zoom, for: url)
    }

    /// 保存キーは現在表示中の fileURL ではなく、通知に載った「その位置が属する文書」から
    /// 決める(理由は ViewerRendererDelegate の doc / TASK-400)。nil の通知は捨てる。
    func renderer(
        _: ViewerRenderer, didChangeScrollPosition position: Double, for url: URL?, mode: ViewerBridge.ViewMode
    ) {
        guard let url else { return }
        documentPresenter.recordScrollPosition(position, for: url, mode: mode)
    }

    func renderer(_: ViewerRenderer, didActivateReference href: String, disposition: OpenDisposition) {
        handleOpenReference(href: href, disposition: disposition)
    }

    func renderer(_: ViewerRenderer, didRequestContextMenuFor href: String) {
        referenceCoordinator.handleContextMenu(href: href)
    }

    func renderer(_: ViewerRenderer, resolveReferences paths: [String]) async -> [String: String] {
        await resolveReferences(paths)
    }

    func rendererDidRequestMoreLines(_: ViewerRenderer) async -> LoadMoreLinesResult? {
        await store.loadMoreLines()
    }
}
