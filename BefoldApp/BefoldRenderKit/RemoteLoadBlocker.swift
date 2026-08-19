import Foundation
import WebKit

/// WKWebView がリモートホストへリクエストを出さないようにするネットワーク層の遮断ポリシー。
///
/// **なぜ CSP では足りないか。** viewer.html は `img-src 'self' data:` を meta で宣言して
/// いるが、`file://` で読み込んだ文書では WebKit がこの取得を検査しない。実測(TASK-526):
/// shields.io のバッジが `naturalWidth = 78` でデコードでき、`securitypolicyviolation` は
/// 1 件も発火しなかった。`script-src` や `frame-src` は同じ宣言で効いているため、
/// 「CSP が読まれていない」のではなく `img-src` だけがこの経路で素通りする。
///
/// **二層で塞ぐ。** マークダウン経路は viewer 側の `replaceRemoteImages()` が挿入前に
/// 代替表示へ置き換えるため、そもそもリクエストが出ない。この型はその外側——JS を
/// 通らない直接 HTML モード(外部 .html の `loadFileURL`)と、サニタイザをすり抜けた
/// 参照——を塞ぐ。
///
/// 遮断は `WKContentRuleList` で行う。これは WebKit のネットワーク層で効くため、
/// `<img>` に限らず CSS の `url()`・`<video>`・XHR まで一様に止まる。
enum RemoteLoadBlocker {
    /// コンパイル済みルールリストの識別子。`WKContentRuleListStore` がディスクへ
    /// キャッシュするため、2 回目以降の起動では `lookUpContentRuleList` が即座に返す。
    private static let identifier = "befold.block-remote-loads"

    /// リモートスキームを一律 block する。`url-filter` の正規表現は選択(`|`)を
    /// 受け付けない(実測: `^(file|data)://` は "Disjunctions are not supported yet" で
    /// コンパイルに失敗する)ため、**許可を列挙して残りを block する形にはできない**。
    /// 逆に、止めたいスキームを列挙する。`file:` / `data:` / `blob:` / `about:` は
    /// どのルールにも一致しないのでそのまま通る(PDF 表示の blob URL と、
    /// 埋め込み画像の data URI がこれに当たる)。
    private static let ruleListJSON = """
    [
      {"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}}
    ]
    """

    /// 一度取得したルールリスト。窓を開くたびに store へ問い合わせないためのキャッシュ。
    @MainActor private static var cached: WKContentRuleList?

    /// ルールリストを WebView へ適用し、完了後に `completion` を呼ぶ。
    ///
    /// **fail-open で呼ぶ。** ルールリストを用意できなかった場合でも `completion` は
    /// 必ず呼ぶ。ここで握りつぶすとビューアが空のまま何も表示されない状態になり、
    /// 「外部画像が出る」より重い故障になる。マークダウン経路は viewer 側の
    /// `replaceRemoteImages()` が独立に守っているため、この層の失敗は多層防御の
    /// 1 枚が欠けることを意味する(全部が外れるわけではない)。
    @MainActor
    static func apply(to webView: WKWebView, then completion: @escaping () -> Void) {
        let controller = webView.configuration.userContentController
        if let cached {
            // 同じリストを重ねて足さない(読み直しのたびに呼ばれる経路がある)。
            controller.removeAllContentRuleLists()
            controller.add(cached)
            completion()
            return
        }
        obtainRuleList { list in
            if let list {
                cached = list
                controller.removeAllContentRuleLists()
                controller.add(list)
            }
            completion()
        }
    }

    /// ディスクキャッシュを引き、無ければコンパイルする。どちらも失敗したら nil。
    @MainActor
    private static func obtainRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        let store = WKContentRuleListStore.default()
        // store 自体が使えないホスト(サンドボックスの構成次第)では nil が返る。
        guard let store else {
            completion(nil)
            return
        }
        store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
            if let list {
                completion(list)
                return
            }
            store.compileContentRuleList(
                forIdentifier: identifier, encodedContentRuleList: ruleListJSON
            ) { compiled, _ in
                completion(compiled)
            }
        }
    }
}
