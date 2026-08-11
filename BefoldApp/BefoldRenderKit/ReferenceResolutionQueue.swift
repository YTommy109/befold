import BefoldKit
import WebKit

/// JS が要求したパス参照の解決を、要求順のまま応答へ直列化する。
///
/// JS 側は応答を要求へ FIFO で対応づける(_mmdApplyResolvedReferences が最も古い
/// 未応答バッチを取り出す)。そのため resolveReferences を受け取ったら、内容に
/// かかわらず必ず 1 回だけ適用スクリプトを評価しなければならない。評価せずに
/// return するとキューが恒久的にずれ、以後すべての応答が 1 つ前のバッチへ適用されて、
/// 実在するパスまで解決失敗表示になる。
@MainActor
final class ReferenceResolutionQueue {
    private typealias ResolveKey = ViewerBridge.PayloadKey.ResolveReferences

    /// 応答は 2 つの suspension point(直前の要求の完了待ち・参照解決)をまたぐため、
    /// renderer は weak で持つ。応答 Task が強く保持するのはこのキューだけで、
    /// キューを保持しても renderer は生き続けない。unowned のままだと、解決を待つ間に
    /// ウィンドウが閉じられて ViewerRenderer が解放された場合、再開時の参照でトラップする
    /// (TASK-448)。
    private weak var renderer: ViewerRenderer?

    /// 解決応答(applyResolvedReferences 評価)の直列チェーン。解決が非同期になっても
    /// 評価順が要求順とずれてはならないため、各要求は直前の要求の完了を待つ。
    private(set) var responseChain: Task<Void, Never>?

    /// JS コンテキストの世代。ページを読み直すと JS 側の状態は捨てられ、参照解決の
    /// FIFO キュー(_mmdPendingRefBatches)も空になる。世代をまたいだ応答をそのまま
    /// 評価すると、新しいページが積んだ別のバッチへ古いマップが当たり、実在する
    /// パスまで解決失敗表示になる(TASK-421)。飛行中の応答はこの値で捨てる。
    ///
    /// 増やせるのは `invalidate()` だけで、呼ぶのは viewer.html を読み直す
    /// `reloadViewerHTML` の 1 箇所。setter をこの型に閉じることで、増分点が
    /// 増えないことを構造で担保する。
    ///
    /// `contentUpdateGeneration` を流用してはならない。通常の再描画では JS 側が
    /// `_mmdInvalidatePendingRefs()` でバッチの中身だけを空にし、**キューの長さ
    /// (未応答の要求数)は保つ**。つまり再描画をまたぐ応答は捨てずに評価し続ける必要が
    /// あり、捨てるとキューが恒久的にずれて以後すべての参照が解決失敗表示になる。
    /// 捨ててよいのは、キューごと消える読み直しの場合だけ。
    private(set) var generation = 0

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    /// viewer.html を読み直したことを通知し、飛行中の応答を無効化する。
    func invalidate() {
        generation += 1
    }

    /// 解決要求を受け付け、直前の要求の完了を待ってから解決・評価する(要求順 = 評価順)。
    /// ペイロードが不正な場合は空の解決結果で応答する(アプリ層へは渡さない)。
    func handle(body: Any) {
        var requestedPaths: [String]?
        if let payload = body as? [String: Any],
           let paths = payload[ResolveKey.paths.rawValue] as? [String],
           !paths.isEmpty
        {
            requestedPaths = paths
        }
        let previous = responseChain
        // 要求を受けた時点のページ世代。解決を待つ間にページが差し替わったら、JS 側の
        // キューは空になっているため、この応答を評価してはならない(TASK-421)。
        let requestGeneration = generation
        responseChain = Task { @MainActor [weak self] in
            await previous?.value
            // renderer は weak。ここまでの待ちの間にウィンドウが閉じられていれば、
            // 応答先そのものが無いので何もしない。
            guard let self, let renderer else { return }
            var resolutions: [String: String] = [:]
            if let requestedPaths {
                resolutions = await renderer.delegate?.renderer(
                    renderer, resolveReferences: requestedPaths
                ) ?? [:]
            }
            // 判定はここ 1 箇所。解決(git subprocess を伴いうる)を待つ間にもページは
            // 差し替わるため、要求受付時ではなく評価の直前に見る必要がある。
            guard generation == requestGeneration else { return }
            // async 文脈では completionHandler 版を明示しないと throwing/async の
            // オーバーロードが選ばれてしまうため、nil を明示して同期版へ固定する。
            renderer.webView?.evaluateJavaScript(
                ViewerBridge.applyResolvedReferencesScript(resolutions), completionHandler: nil
            )
        }
    }
}
