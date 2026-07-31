import BefoldKit
import WebKit

// MARK: - WKScriptMessageHandler

extension ViewerRenderer {
    private typealias ReferenceKey = ViewerBridge.PayloadKey.ReferenceActivated
    private typealias ScrollKey = ViewerBridge.PayloadKey.ScrollPositionChanged
    private typealias FindKey = ViewerBridge.PayloadKey.FindOptionsChanged
    private typealias ResolveKey = ViewerBridge.PayloadKey.ResolveReferences

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

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == ViewerBridge.zoomChangedMessageName,
           let zoom = (message.body as? NSNumber)?.doubleValue
        {
            delegate?.renderer(self, didChangeZoom: zoom)
        } else if message.name == ViewerBridge.referenceActivatedMessageName,
                  let body = message.body as? [String: Any],
                  let href = body[ReferenceKey.href.rawValue] as? String,
                  let metaKey = body[ReferenceKey.metaKey.rawValue] as? Bool,
                  let shiftKey = body[ReferenceKey.shiftKey.rawValue] as? Bool
        {
            delegate?.renderer(
                self, didActivateReference: href,
                disposition: OpenDisposition(commandKey: metaKey, shiftKey: shiftKey)
            )
        } else if message.name == ViewerBridge.scrollPositionChangedMessageName,
                  let body = message.body as? [String: Any],
                  let position = (body[ScrollKey.position.rawValue] as? NSNumber)?.doubleValue,
                  let modeString = body[ScrollKey.mode.rawValue] as? String,
                  let mode = ViewerBridge.ViewMode(rawValue: modeString)
        {
            delegate?.renderer(self, didChangeScrollPosition: position, mode: mode)
        } else if message.name == ViewerBridge.findOptionsChangedMessageName,
                  let body = message.body as? [String: Any],
                  let caseSensitive = body[FindKey.caseSensitive.rawValue] as? Bool,
                  let wholeWord = body[FindKey.wholeWord.rawValue] as? Bool,
                  let useRegex = body[FindKey.useRegex.rawValue] as? Bool
        {
            findOptionsPreference?.caseSensitive = caseSensitive
            findOptionsPreference?.wholeWord = wholeWord
            findOptionsPreference?.useRegex = useRegex
        } else if message.name == ViewerBridge.loadMoreLinesMessageName {
            handleLoadMoreLines()
        } else if message.name == ViewerBridge.resolveReferencesMessageName {
            handleResolveReferences(body: message.body)
        }
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
        resolveResponseChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            var resolutions: [String: String] = [:]
            if let requestedPaths {
                resolutions = await delegate?.renderer(self, resolveReferences: requestedPaths) ?? [:]
            }
            // async 文脈では completionHandler 版を明示しないと throwing/async の
            // オーバーロードが選ばれてしまうため、nil を明示して同期版へ固定する。
            webView?.evaluateJavaScript(
                ViewerBridge.applyResolvedReferencesScript(resolutions), completionHandler: nil
            )
        }
    }
}
