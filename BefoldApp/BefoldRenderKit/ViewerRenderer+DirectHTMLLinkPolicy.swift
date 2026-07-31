import AppKit
import BefoldKit
import WebKit

// MARK: - Direct HTML link policy

extension ViewerRenderer {
    /// decidePolicyFor の実装本体。type_body_length 対策で ViewerRenderer 本体の外の
    /// extension に分離している。初回の HTML ロード（loadFileURL）は常に許可する。
    /// viewer.html モードではそれ以外のナビゲーションを全てキャンセルする(JS 側がリンクを
    /// 処理する)。直接 HTML モードではリンククリック(.linkActivated)のみ
    /// directHTMLLinkPolicy で分類して処理する。
    func decidePolicyForDirectHTMLAware(
        webView: WKWebView,
        navigationAction: WKNavigationAction
    ) -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .other {
            return .allow
        }

        guard isDirectHTMLMode else {
            return .cancel
        }

        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            return .cancel
        }

        let action = Self.directHTMLLinkPolicy(
            url: url,
            currentURL: webView.url,
            modifierFlags: navigationAction.modifierFlags
        )

        switch action {
        case .allowNativeNavigation:
            return .allow
        case let .openLocalFile(fileURL, disposition):
            delegate?.renderer(self, didActivateReference: fileURL.path, disposition: disposition)
            return .cancel
        case let .openExternal(externalURL):
            NSWorkspace.shared.open(externalURL)
            return .cancel
        case .ignore:
            return .cancel
        }
    }
}

public extension ViewerRenderer {
    /// 直接 HTML モードでのリンククリックに対する挙動分類。
    enum DirectHTMLLinkAction: Equatable {
        case allowNativeNavigation
        case openLocalFile(url: URL, disposition: OpenDisposition)
        case openExternal(url: URL)
        case ignore
    }

    /// クリックされたリンク URL を分類する純関数。
    /// 同一文書内フラグメントはネイティブのスクロールに任せ、それ以外のローカルファイルは
    /// フラグメントを除去する。修飾キーの解釈は OpenDisposition に委ねる。
    nonisolated static func directHTMLLinkPolicy(
        url: URL,
        currentURL: URL?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> DirectHTMLLinkAction {
        // ctrl はコンテキストメニュー扱い(OpenDisposition のドキュメント参照)であり、
        // このメソッドの呼び出し元(decidePolicyFor)にはコンテキストメニュー経路が無いため、
        // ここでは遷移させず無視する。
        if modifierFlags.contains(.control) {
            return .ignore
        }

        if let fragment = url.fragment, !fragment.isEmpty,
           let currentURL,
           url.deletingFragment() == currentURL.deletingFragment()
        {
            return .allowNativeNavigation
        }

        let scheme = url.scheme ?? ""
        if scheme == "http" || scheme == "https" {
            return .openExternal(url: url)
        }

        if url.isFileURL {
            let cleanURL = url.fragment != nil ? url.deletingFragment() : url
            return .openLocalFile(url: cleanURL, disposition: OpenDisposition(modifiers: modifierFlags))
        }

        return .ignore
    }
}

private extension URL {
    /// フラグメント(`#...`)を除去した URL を返す。
    func deletingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
