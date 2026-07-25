import BefoldKit
import WebKit

// MARK: - WKScriptMessageHandler

extension ViewerRenderer {
    private typealias ReferenceKey = ViewerBridge.PayloadKey.ReferenceActivated
    private typealias ScrollKey = ViewerBridge.PayloadKey.ScrollPositionChanged
    private typealias FindKey = ViewerBridge.PayloadKey.FindOptionsChanged

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
                  let href = body[ReferenceKey.href.rawValue] as? String,
                  let newWindow = body[ReferenceKey.newWindow.rawValue] as? Bool
        {
            onOpenReference?(href, newWindow)
        } else if message.name == ViewerBridge.scrollPositionChangedMessageName,
                  let body = message.body as? [String: Any],
                  let position = (body[ScrollKey.position.rawValue] as? NSNumber)?.doubleValue,
                  let modeString = body[ScrollKey.mode.rawValue] as? String,
                  let mode = ViewerBridge.ViewMode(rawValue: modeString)
        {
            onScrollPositionChanged?(position, mode)
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
        }
    }
}
