import Foundation

/// 法令標準XML（e-Gov 法令検索が配布する法令XML）に当てる内蔵スタイルシート。
///
/// e-Gov は表示用の XSLT を配布しておらず（サーバー側で HTML を生成している）、
/// 法令XMLには `<?xml-stylesheet?>` も同名 `.xsl` も付いてこない。そのため
/// TASK-596 の汎用経路だけでは必ずソースコード表示に落ちる。ここが「文書に
/// 添えられていないスタイルシート」を befold 側から供給する（TASK-597）。
///
/// 供給するだけで、描画経路は増やさない —— `XSLStylesheetResolver.resolve` の
/// 最後の候補として差し込むので、以降は同ディレクトリに `.xsl` があるときと
/// まったく同じ道（`RenderableContent.make` → `ViewerXSLTBridge` → viewer の
/// `XSLTProcessor`）を通る。
public enum JapaneseLawStylesheet {
    /// バンドルへ同梱する XSL のファイル名（拡張子を除く）。
    static let resourceName = "japanese-law"

    /// 法令標準XMLなら内蔵スタイルシートを返す。それ以外は nil。
    public static func stylesheet(forXML xml: String) -> String? {
        guard isJapaneseLawXML(xml) else { return nil }
        return bundled
    }

    /// ルート要素から法令標準XMLかどうかを判定する。
    ///
    /// **namespace では判定できない。** 法令標準XMLスキーマ v3
    /// (`XMLSchemaForJapaneseLaw_v3.xsd`, Version 3.0 / Nov 24 2020) は
    /// `targetNamespace` を宣言しておらず、ルート要素 `Law` も無名前空間にある
    /// （実測: スキーマ中に `targetNamespace` の出現が 0 件）。代わりに
    /// 「ルート要素が `Law` で、必須属性 `Era` と `Num` を持つ」ことで判定する。
    ///
    /// 走査はルート要素の開始タグだけに限る。本文全体を文字列一致すると、
    /// コメントや CDATA の中にある同じ形に当たる（`XSLStylesheetResolver` が
    /// 処理命令の探索をプロローグに限っているのと同じ理由）。
    static func isJapaneseLawXML(_ xml: String) -> Bool {
        let start = XSLStylesheetResolver.rootElementStart(in: xml)
        guard start < xml.endIndex,
              let tagEnd = xml.range(of: ">", range: start ..< xml.endIndex)
        else { return false }
        let tag = xml[start ..< tagEnd.lowerBound]
        guard tag.hasPrefix("<Law"), let afterName = tag.dropFirst(4).first, afterName.isWhitespace
        else { return false }
        return tag.contains("Era=") && tag.contains("Num=")
    }

    /// 同梱 XSL の本文。バンドルから読めなければ nil（その場合は従来どおり
    /// ソースコード表示に落ちる）。`JapaneseLawStylesheetTests` が実際に読めることを見る
    /// —— Package.swift / project.yml への登録漏れは、これが無いと実行時まで気づけない。
    static let bundled: String? = {
        guard let url = Bundle.befoldKitResources.url(forResource: resourceName, withExtension: "xsl")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
}
