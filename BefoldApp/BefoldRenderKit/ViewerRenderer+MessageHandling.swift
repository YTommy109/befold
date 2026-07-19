import BefoldKit
import WebKit

// MARK: - WKScriptMessageHandler

extension ViewerRenderer {
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
            onZoomChanged?(zoom)
        } else if message.name == ViewerBridge.referenceActivatedMessageName,
                  let body = message.body as? [String: Any],
                  let href = body["href"] as? String,
                  let newWindow = body["newWindow"] as? Bool
        {
            onOpenReference?(href, newWindow)
        } else if message.name == ViewerBridge.scrollPositionChangedMessageName,
                  let body = message.body as? [String: Any],
                  let position = (body["position"] as? NSNumber)?.doubleValue,
                  let modeString = body["mode"] as? String,
                  let mode = ViewerBridge.ViewMode(rawValue: modeString)
        {
            onScrollPositionChanged?(position, mode)
        } else if message.name == ViewerBridge.findOptionsChangedMessageName,
                  let body = message.body as? [String: Any],
                  let caseSensitive = body["caseSensitive"] as? Bool,
                  let wholeWord = body["wholeWord"] as? Bool,
                  let useRegex = body["useRegex"] as? Bool
        {
            findOptionsPreference?.caseSensitive = caseSensitive
            findOptionsPreference?.wholeWord = wholeWord
            findOptionsPreference?.useRegex = useRegex
        } else if message.name == ViewerBridge.loadMoreLinesMessageName {
            handleLoadMoreLines()
        }
    }
}
