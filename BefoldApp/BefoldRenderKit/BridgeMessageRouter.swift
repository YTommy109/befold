import BefoldKit
import WebKit

/// JS からの postMessage を受け取り、ペイロードを解いて宛先へ配る。
///
/// ViewerRenderer から切り出してあるのは、受信・デコードという関心が
/// 「描画状態の管理」と独立しているため。ViewerRendererDelegate の各メソッドが
/// 第 1 引数に ViewerRenderer を取るため、通知元として renderer を unowned で持つ
/// (renderer がこのルータを所有するので、寿命は必ず renderer が長い)。
@MainActor
final class BridgeMessageRouter: NSObject, WKScriptMessageHandler {
    private typealias ReferenceKey = ViewerBridgeMessage.PayloadKey.ReferenceActivated
    private typealias ZoomKey = ViewerBridgeMessage.PayloadKey.ZoomChanged
    private typealias FindKey = ViewerBridgeMessage.PayloadKey.FindOptionsChanged
    private typealias JumpLevelsKey = ViewerBridgeMessage.PayloadKey.JumpLevelsChanged
    private typealias ContextMenuKey = ViewerBridgeMessage.PayloadKey.ReferenceContextMenu

    private unowned let renderer: ViewerRenderer

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    /// 受信メッセージを BridgeMessage へ写して分岐する。網羅 switch なので、
    /// メッセージを追加してルーティングを書き忘れるとコンパイルエラーになる。
    /// ペイロードの取り出しは各ケース内で行い、不正なら早期 return する
    /// (名前判定と混ぜると、body が不正なだけで次の分岐へ静かに落ちてしまう)。
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let kind = ViewerBridgeMessage(rawValue: message.name) else { return }
        switch kind {
        case .zoomChanged: handleZoomChanged(body: message.body)
        case .referenceActivated: handleReferenceActivated(body: message.body)
        case .referenceContextMenu: handleReferenceContextMenu(body: message.body)
        case .findOptionsChanged: handleFindOptionsChanged(body: message.body)
        case .jumpLevelsChanged: handleJumpLevelsChanged(body: message.body)
        case .loadMoreLines: renderer.handleLoadMoreLines()
        case .resolveReferences: renderer.referenceQueue.handle(body: message.body)
        }
    }

    private func handleZoomChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let zoom = (payload[ZoomKey.zoom.rawValue] as? NSNumber)?.doubleValue
        else { return }
        // キーにする文書は、スクロール位置と同じく JS が payload の path で申告する
        // 「倍率を読んだ時点で DOM に出ていた文書」(理由は ViewerRendererDelegate の doc)。
        let url = (payload[ZoomKey.path.rawValue] as? String).map { URL(fileURLWithPath: $0) }
        renderer.delegate?.renderer(renderer, didChangeZoom: zoom, for: url)
    }

    private func handleReferenceActivated(body: Any) {
        guard let payload = body as? [String: Any],
              let href = payload[ReferenceKey.href.rawValue] as? String,
              let metaKey = payload[ReferenceKey.metaKey.rawValue] as? Bool,
              let shiftKey = payload[ReferenceKey.shiftKey.rawValue] as? Bool
        else { return }
        renderer.delegate?.renderer(
            renderer, didActivateReference: href,
            disposition: OpenDisposition(commandKey: metaKey, shiftKey: shiftKey)
        )
    }

    private func handleReferenceContextMenu(body: Any) {
        guard let payload = body as? [String: Any],
              let href = payload[ContextMenuKey.href.rawValue] as? String
        else { return }
        renderer.delegate?.renderer(renderer, didRequestContextMenuFor: href)
    }

    private func handleFindOptionsChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let caseSensitive = payload[FindKey.caseSensitive.rawValue] as? Bool,
              let wholeWord = payload[FindKey.wholeWord.rawValue] as? Bool,
              let useRegex = payload[FindKey.useRegex.rawValue] as? Bool
        else { return }
        renderer.findOptionsPreference?.caseSensitive = caseSensitive
        renderer.findOptionsPreference?.wholeWord = wholeWord
        renderer.findOptionsPreference?.useRegex = useRegex
    }

    /// 見出しレベルのトグル変更を「次に開く窓の出発点」として記録する。
    /// レンダラが持つのは書き戻し専用のプロトコルだけで、保存値を読み直す経路は無い
    /// (ADR 0002「窓の状態」)。空配列も正当な値なので、空だからと弾かない。
    private func handleJumpLevelsChanged(body: Any) {
        guard let payload = body as? [String: Any],
              let tokens = payload[JumpLevelsKey.levels.rawValue] as? [String]
        else { return }
        renderer.headingJumpLevelRecording?.record(HeadingJumpLevels.stored(tokens))
    }
}
