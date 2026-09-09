import Foundation

/// XSLT 変換表示の Swift → JS 契約。
///
/// viewer 側の受け手は `viewer-src/renderers.ts` の `_renderXslt` で、
/// `render(content, type)` の type トークンと content の JSON キーの**両方**を
/// ここと共有する。片側だけ変えても Swift はビルドが通るため、
/// `ViewerXSLTBridgeContractTests` が viewer-bundle.js を読んで実際に照合する。
public enum ViewerXSLTBridge {
    /// `render(content, type)` の第 2 引数。`FileType.jsValue` と同じ名前空間の値だが、
    /// **`FileType` の case にはしない** —— 拡張子から決まらず、描画のたびに
    /// 「xsl を解決できたか」で決まるため。`FileType` に持たせると、表示モード・
    /// チャンク可否・capabilities・QuickLook 対象集合の判定が、答えを持たない値に
    /// 答えることになる。
    public static let renderType = "xslt"

    /// `render()` へ渡す content。JS 側は `xml` / `xsl` の 2 キーで読む。
    public static func payload(xml: String, xsl: String) -> String? {
        ViewerBridge.jsonLiteral(Payload(xml: xml, xsl: xsl))
    }

    private struct Payload: Encodable {
        let xml: String
        let xsl: String
    }
}
