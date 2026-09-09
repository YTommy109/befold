import Foundation

/// XML に添えられた XSL スタイルシートを解決して本文を読み出す。
///
/// e-Gov 電子申請の公文書のように、表示ロジックを `.xsl`(XSLT 1.0)側に持つ
/// XML のためのもの。変換そのものは行わない —— 変換は viewer 側の
/// `XSLTProcessor` が担い、JS へ渡す形は `ViewerXSLTBridge` が持つ。ここは
/// 「どの xsl を使うか」と「その本文」だけを返す
/// (WKWebView 上で XSLTProcessor が動くことは TASK-596 の Notes に実測を残してある)。
public enum XSLStylesheetResolver {
    /// スタイルシートの探索と読み込み。見つからなければ nil。
    ///
    /// 探索の順序は次のとおりで、いずれも**同じディレクトリの中だけ**を見る。
    /// 1. `<?xml-stylesheet ... href="..."?>` 処理命令が指すファイル
    /// 2. 同名の `.xsl`
    ///
    /// - Parameters:
    ///   - xml: XML の本文。処理命令の探索に使う。
    ///   - fileURL: XML ファイルのパス。相対 href の解決基準になる。
    public static func resolve(xml: String, fileURL: URL, fileReader: any FileReading) -> String? {
        let directory = fileURL.deletingLastPathComponent()
        let candidates = [
            stylesheetHref(inPrologOf: xml).map { directory.appendingPathComponent($0) },
            fileURL.deletingPathExtension().appendingPathExtension("xsl"),
        ]
        for case let candidate? in candidates {
            // ディレクトリを跨ぐ href は受け付けない(XML は外部から受け取る文書で、
            // `../` を含む href が読み取り権限の外へ手を伸ばす経路になりうる)。
            guard candidate.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                  fileReader.isExistingFile(at: candidate),
                  let text = try? fileReader.readString(from: candidate), !text.isEmpty
            else { continue }
            return text
        }
        return nil
    }

    /// プロローグ(ルート要素の開始タグより前)にある `<?xml-stylesheet?>` の href。
    ///
    /// 探索範囲をプロローグに限るのは、本文全体を文字列一致すると
    /// コメントや CDATA の中にある同じ形に当たるため。処理命令が置けるのは
    /// そもそもプロローグだけなので、範囲を狭めても取りこぼしは生じない。
    static func stylesheetHref(inPrologOf xml: String) -> String? {
        let prolog = xml[..<rootElementStart(in: xml)]
        guard let piRange = prolog.range(of: "<?xml-stylesheet"),
              let piEnd = prolog.range(of: "?>", range: piRange.upperBound ..< prolog.endIndex)
        else { return nil }
        let pseudoAttributes = prolog[piRange.upperBound ..< piEnd.lowerBound]
        // type/media/title など他の疑似属性より前に href が来るとは限らないため、
        // href= を明示的に探す(先頭の属性を取る形にすると type="text/xsl" を拾う)。
        guard let hrefRange = pseudoAttributes.range(of: "href") else { return nil }
        let afterHref = pseudoAttributes[hrefRange.upperBound...].drop(while: { $0 == " " || $0 == "=" })
        guard let quote = afterHref.first, quote == "\"" || quote == "'" else { return nil }
        let value = afterHref.dropFirst().prefix(while: { $0 != quote })
        let href = String(value).removingPercentEncoding ?? String(value)
        // 空・絶対 URL・パス区切りを含むものは扱わない(同一ディレクトリのみが対象)。
        guard !href.isEmpty, !href.contains("/"), !href.contains(":") else { return nil }
        return href
    }

    /// ルート要素の開始位置(最初の `<` のうち `<?` / `<!` でないもの)。
    /// 見つからなければ末尾を返す。
    private static func rootElementStart(in xml: String) -> String.Index {
        var index = xml.startIndex
        while let open = xml.range(of: "<", range: index ..< xml.endIndex) {
            let next = xml.index(after: open.lowerBound)
            guard next < xml.endIndex, xml[next] == "?" || xml[next] == "!" else { return open.lowerBound }
            index = next
        }
        return xml.endIndex
    }
}
