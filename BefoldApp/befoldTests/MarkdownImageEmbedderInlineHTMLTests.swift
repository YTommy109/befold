// BefoldApp/befoldTests/MarkdownImageEmbedderInlineHTMLTests.swift
import BefoldKit
import Foundation
import Testing

/// inline HTML の <img src="..."> に対する data URI 埋め込み(TASK-524)。
/// markdown 記法 ![alt](path) 側は MarkdownImageEmbedderTests が受け持つ。
@Suite
struct MarkdownImageEmbedderInlineHTMLTests {
    private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// メモリ上のファイル配置の基準ディレクトリ(実ファイルシステムには存在しない)。
    private let baseURL = URL(fileURLWithPath: "/virtual/docs/doc.md")

    private func url(_ relativePath: String) -> URL {
        baseURL.deletingLastPathComponent().appendingPathComponent(relativePath).standardized
    }

    private func dataURI(_ data: Data, mimeType: String = "image/png") -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func makeEmbedder(files: [String: Data]) -> MarkdownImageEmbedder {
        let fileReader = InMemoryFileReader()
        for (path, data) in files {
            fileReader.setDataFile(data, at: url(path))
        }
        return MarkdownImageEmbedder(fileReader: fileReader)
    }

    /// src の書き方(相対・サブディレクトリ・上位相対・絶対・file URL)を変えても、
    /// src 属性の値だけが data URI に差し替わり、他の属性は原文のまま残ること。
    @Test(arguments: [
        (markdown: #"<img src="photo.png">"#, placedAt: "photo.png"),
        (markdown: #"<img src="./images/photo.png">"#, placedAt: "images/photo.png"),
        (markdown: #"<img src="../shared/photo.png">"#, placedAt: "../shared/photo.png"),
        (markdown: #"<img src="/virtual/docs/photo.png">"#, placedAt: "photo.png"),
        (markdown: #"<img src="file:///virtual/docs/photo.png">"#, placedAt: "photo.png"),
        // シングルクォート
        (markdown: "<img src='photo.png'>", placedAt: "photo.png"),
        // クォート無し
        (markdown: #"<img src=photo.png>"#, placedAt: "photo.png"),
        // 大文字のタグ名・属性名
        (markdown: #"<IMG SRC="photo.png">"#, placedAt: "photo.png"),
        // = の周りの空白
        (markdown: #"<img src = "photo.png">"#, placedAt: "photo.png"),
    ])
    func embedsImageTagSource(markdown: String, placedAt: String) {
        let embedder = makeEmbedder(files: [placedAt: pngData])

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown.replacingOccurrences(of: srcValue(in: markdown), with: dataURI(pngData)))
    }

    /// 属性順序が異なっても(width が src より前でも)差し替わり、他の属性は残ること。
    @Test("属性順序が異なっても src だけを差し替える")
    func embedsRegardlessOfAttributeOrder() {
        let embedder = makeEmbedder(files: ["photo.png": pngData])

        let result = embedder.embedLocalImages(
            in: #"<img width="380" alt="図" src="photo.png" loading="lazy">"#, baseURL: baseURL
        )

        #expect(result == #"<img width="380" alt="図" src="\#(dataURI(pngData))" loading="lazy">"#)
    }

    /// 属性値に > を含んでいてもタグの終端を誤認せず、src だけを差し替えること。
    @Test("alt に > を含む img タグでも src を差し替える")
    func embedsWhenAttributeValueContainsAngleBracket() {
        let embedder = makeEmbedder(files: ["photo.png": pngData])

        let result = embedder.embedLocalImages(
            in: #"<img alt="a > b" src="photo.png">"#, baseURL: baseURL
        )

        #expect(result == #"<img alt="a > b" src="\#(dataURI(pngData))">"#)
    }

    /// 表の 1 行に複数の img タグが並ぶ形(README の機能ギャラリー)でも全て差し替わること。
    @Test("同一行の複数の img タグをそれぞれ差し替える")
    func embedsMultipleImageTagsOnSameLine() {
        let embedder = makeEmbedder(files: ["a.png": pngData, "b.png": pngData])

        let result = embedder.embedLocalImages(
            in: #"| <img src="a.png" width="380"> | <img src="b.png" width="380"> |"#,
            baseURL: baseURL
        )

        let uri = dataURI(pngData)
        #expect(result == #"| <img src="\#(uri)" width="380"> | <img src="\#(uri)" width="380"> |"#)
    }

    /// markdown 記法と img タグが同じ行に混在しても、両方が差し替わること。
    @Test("markdown 記法と img タグが混在する行で両方を差し替える")
    func embedsBothNotationsOnSameLine() {
        let embedder = makeEmbedder(files: ["a.png": pngData, "b.png": pngData])

        let result = embedder.embedLocalImages(
            in: #"![alt](a.png) と <img src="b.png">"#, baseURL: baseURL
        )

        let uri = dataURI(pngData)
        #expect(result == #"![alt](\#(uri)) と <img src="\#(uri)">"#)
    }

    /// SVG も image/svg+xml の data URI になること(markdown 記法と同じ対応表を使う)。
    @Test("img タグの SVG を image/svg+xml の data URI に差し替える")
    func embedsSVGImageTag() {
        let svgData = Data("<svg></svg>".utf8)
        let embedder = makeEmbedder(files: ["icon.svg": svgData])

        let result = embedder.embedLocalImages(in: #"<img src="icon.svg">"#, baseURL: baseURL)

        #expect(result == #"<img src="\#(dataURI(svgData, mimeType: "image/svg+xml"))">"#)
    }

    /// 埋め込み対象外の img タグ(リモート URL・欠損ファイル・非対応拡張子・フェンス内・
    /// インラインコード内・src 無し・空の src)は原文のまま残ること。
    /// いずれのケースでも photo.png / doc.pdf を用意した上で判定する。
    @Test(arguments: [
        #"<img src="https://example.com/photo.png">"#, // リモート URL
        #"<img src="//example.com/photo.png">"#, // プロトコル相対(ローカルには解決しない)
        #"<img src="nowhere.png">"#, // 存在しないファイル
        #"<img src="doc.pdf">"#, // 非対応拡張子
        #"<img alt="なし">"#, // src が無い
        #"<img src="">"#, // src が空
        """
        ```html
        <img src="photo.png">
        ```
        """, // フェンスコードブロック内
        """
        ~~~
        <img src="photo.png">
        ~~~
        """, // チルダフェンス内
        #"書き方は `<img src="photo.png">` とする"#, // インラインコード内
        "# 見出し\n\n画像を含まない本文。", // img タグを含まない
    ])
    func leavesImageTagUntouchedWhenNotEmbeddable(markdown: String) {
        let embedder = makeEmbedder(files: ["photo.png": pngData, "doc.pdf": pngData])

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown)
    }

    /// サイズ上限を超える img タグは markdown 記法と同じく原文のまま残ること。
    @Test("サイズ上限を超える img タグは変更しない")
    func leavesOversizedImageTagUntouched() {
        let embedder = makeEmbedder(files: ["big.png": Data(count: 100)])
        let markdown = #"<img src="big.png">"#

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL, maxImageSizeBytes: 99)

        #expect(result == markdown)
    }

    /// src="..." の値部分(クォートの内側、クォート無しならその語)を取り出す。
    /// 期待値の組み立てにだけ使う簡易版で、実装とは別に書いている。
    private func srcValue(in markdown: String) -> String {
        guard let range = markdown.range(of: #"(?i)src\s*=\s*"#, options: .regularExpression) else {
            Issue.record("src 属性が見つからない: \(markdown)")
            return ""
        }
        let rest = markdown[range.upperBound...]
        if let quote = rest.first, quote == "\"" || quote == "'" {
            let body = rest.dropFirst()
            return String(body[body.startIndex ..< (body.firstIndex(of: quote) ?? body.endIndex)])
        }
        return String(rest.prefix { !$0.isWhitespace && $0 != ">" })
    }
}
