import AppKit
import BefoldKit
import Foundation

/// 直接 HTML モードでのリンククリックに対する挙動分類。
public enum DirectHTMLLinkAction: Equatable {
    case allowNativeNavigation
    case openLocalFile(url: URL, disposition: OpenDisposition)
    case openExternal(url: URL)
    case ignore
}

/// クリックされたリンク URL を分類する純粋ロジック。
public enum DirectHTMLLinkPolicy {
    /// 同一文書内フラグメントはネイティブのスクロールに任せ、それ以外のローカルファイルは
    /// フラグメントを除去する。修飾キーの解釈は OpenDisposition に委ねる。
    public nonisolated static func classify(
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
