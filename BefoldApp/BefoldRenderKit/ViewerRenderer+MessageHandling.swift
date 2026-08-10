import BefoldKit
import WebKit

// MARK: - WKScriptMessageHandler

extension ViewerRenderer {
    private typealias ReferenceKey = ViewerBridge.PayloadKey.ReferenceActivated
    private typealias ScrollKey = ViewerBridge.PayloadKey.ScrollPositionChanged
    private typealias ZoomKey = ViewerBridge.PayloadKey.ZoomChanged
    private typealias FindKey = ViewerBridge.PayloadKey.FindOptionsChanged
    private typealias ResolveKey = ViewerBridge.PayloadKey.ResolveReferences
    private typealias ContextMenuKey = ViewerBridge.PayloadKey.ReferenceContextMenu

    /// WKUserContentController はハンドラを強参照するため、ViewerRenderer への参照を弱めて
    /// dismantle の呼び出しに依存せずリークを防ぐプロキシ。
    /// type_body_length 対策で ViewerRenderer 本体の外の extension に分離している。
    final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var delegate: WKScriptMessageHandler?

        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        @MainActor
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    /// 受信メッセージを BridgeMessage へ写して分岐する。網羅 switch なので、
    /// メッセージを追加してルーティングを書き忘れるとコンパイルエラーになる。
    /// ペイロードの取り出しは各ケース内で行い、不正なら早期 return する
    /// (名前判定と混ぜると、body が不正なだけで次の分岐へ静かに落ちてしまう)。
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let kind = ViewerBridge.BridgeMessage(rawValue: message.name) else { return }
        switch kind {
        case .zoomChanged: handleZoomChanged(body: message.body)
        case .referenceActivated: handleReferenceActivated(body: message.body)
        case .referenceContextMenu: handleReferenceContextMenu(body: message.body)
        case .scrollPositionChanged: handleScrollPositionChanged(body: message.body)
        case .findOptionsChanged: handleFindOptionsChanged(body: message.body)
        case .loadMoreLines: handleLoadMoreLines()
        case .resolveReferences: handleResolveReferences(body: message.body)
        }
    }

    private func handleZoomChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let zoom = (payload[ZoomKey.zoom.rawValue] as? NSNumber)?.doubleValue
        else { return }
        // キーにする文書は、スクロール位置と同じく JS が payload の path で申告する
        // 「倍率を読んだ時点で DOM に出ていた文書」(理由は ViewerRendererDelegate の doc)。
        let url = (payload[ZoomKey.path.rawValue] as? String).map { URL(fileURLWithPath: $0) }
        delegate?.renderer(self, didChangeZoom: zoom, for: url)
    }

    private func handleReferenceActivated(body: Any) {
        guard let payload = body as? [String: Any],
              let href = payload[ReferenceKey.href.rawValue] as? String,
              let metaKey = payload[ReferenceKey.metaKey.rawValue] as? Bool,
              let shiftKey = payload[ReferenceKey.shiftKey.rawValue] as? Bool
        else { return }
        delegate?.renderer(
            self, didActivateReference: href,
            disposition: OpenDisposition(commandKey: metaKey, shiftKey: shiftKey)
        )
    }

    private func handleReferenceContextMenu(body: Any) {
        guard let payload = body as? [String: Any],
              let href = payload[ContextMenuKey.href.rawValue] as? String
        else { return }
        delegate?.renderer(self, didRequestContextMenuFor: href)
    }

    private func handleScrollPositionChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let position = (payload[ScrollKey.position.rawValue] as? NSNumber)?.doubleValue,
              let modeString = payload[ScrollKey.mode.rawValue] as? String,
              let mode = ViewerBridge.ViewMode(rawValue: modeString)
        else { return }
        // キーにする文書は、JS が payload の path で申告する「位置を読んだ時点で DOM に
        // 出ていた文書」。ホスト側の現在 URL(TASK-400)からも、Swift 側の描画済みミラー
        // (キューや配達の遅延で実 DOM とずれる = TASK-393)からも推定しない。
        let url = (payload[ScrollKey.path.rawValue] as? String).map { URL(fileURLWithPath: $0) }
        delegate?.renderer(self, didChangeScrollPosition: position, for: url, mode: mode)
    }

    private func handleFindOptionsChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let caseSensitive = payload[FindKey.caseSensitive.rawValue] as? Bool,
              let wholeWord = payload[FindKey.wholeWord.rawValue] as? Bool,
              let useRegex = payload[FindKey.useRegex.rawValue] as? Bool
        else { return }
        findOptionsPreference?.caseSensitive = caseSensitive
        findOptionsPreference?.wholeWord = wholeWord
        findOptionsPreference?.useRegex = useRegex
    }

    /// JS 側は応答を要求へ FIFO で対応づける(_mmdApplyResolvedReferences が最も古い
    /// 未応答バッチを取り出す)。そのため resolveReferences を受け取ったら、内容に
    /// かかわらず必ず 1 回だけ適用スクリプトを評価しなければならない。
    /// ここで評価せずに return するとキューが恒久的にずれ、以後すべての応答が
    /// 1 つ前のバッチへ適用されて、実在するパスまで解決失敗表示になる。
    /// ペイロードが不正な場合は空の解決結果で応答する(アプリ層へは渡さない)。
    ///
    /// 解決 (onResolveReferences) は git subprocess を伴いうるため非同期であり、
    /// 要求ごとに所要時間が異なる。完了順にそのまま応答すると FIFO の対応づけが崩れて
    /// 上記と同じずれが起きるため、各要求は resolveResponseChain で直前の要求の完了を
    /// 待ってから解決・評価する(要求順 = 評価順)。
    func handleResolveReferences(body: Any) {
        var requestedPaths: [String]?
        if let payload = body as? [String: Any],
           let paths = payload[ResolveKey.paths.rawValue] as? [String],
           !paths.isEmpty
        {
            requestedPaths = paths
        }
        let previous = resolveResponseChain
        // 要求を受けた時点のページ世代。解決を待つ間にページが差し替わったら、JS 側の
        // キューは空になっているため、この応答を評価してはならない(TASK-421)。
        let generation = pageGeneration
        resolveResponseChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            var resolutions: [String: String] = [:]
            if let requestedPaths {
                resolutions = await delegate?.renderer(self, resolveReferences: requestedPaths) ?? [:]
            }
            // 判定はここ 1 箇所。解決(git subprocess を伴いうる)を待つ間にもページは
            // 差し替わるため、要求受付時ではなく評価の直前に見る必要がある。
            guard pageGeneration == generation else { return }
            // async 文脈では completionHandler 版を明示しないと throwing/async の
            // オーバーロードが選ばれてしまうため、nil を明示して同期版へ固定する。
            webView?.evaluateJavaScript(
                ViewerBridge.applyResolvedReferencesScript(resolutions), completionHandler: nil
            )
        }
    }
}
