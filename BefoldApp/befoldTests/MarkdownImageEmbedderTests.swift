// BefoldApp/befoldTests/MarkdownImageEmbedderTests.swift
import BefoldKit
import Foundation
import Testing

@Suite
struct MarkdownImageEmbedderTests {
    private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func dataURI(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    @Test("相対パスのローカル画像を data URI に差し替える")
    func embedsRelativeLocalImage() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "photo.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "before\n![説明](photo.png)\nafter", baseURL: baseURL
        )

        #expect(result == "before\n![説明](\(dataURI(pngData, mimeType: "image/png")))\nafter")
    }

    @Test("サブディレクトリの相対パスを解決する")
    func embedsImageInSubdirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let subDir = tmp.url.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try pngData.write(to: subDir.appendingPathComponent("chart.png"))
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![chart](./images/chart.png)", baseURL: baseURL
        )

        #expect(result == "![chart](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("絶対パスのローカル画像を data URI に差し替える")
    func embedsAbsolutePathImage() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let imageURL = try tmp.file(named: "photo.jpg", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![alt](\(imageURL.path))", baseURL: baseURL
        )

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/jpeg")))")
    }

    @Test("SVG を image/svg+xml の data URI に差し替える")
    func embedsSVGImage() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        try tmp.file(named: "icon.svg", data: svg)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![icon](icon.svg)", baseURL: baseURL
        )

        #expect(result == "![icon](\(dataURI(svg, mimeType: "image/svg+xml")))")
    }

    @Test("title 付き記法で title を保持する")
    func preservesTitle() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "photo.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![alt](photo.png \"タイトル\")", baseURL: baseURL
        )

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/png")) \"タイトル\")")
    }

    @Test("パーセントエンコードされたパスを解決する")
    func resolvesPercentEncodedPath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "画像 1.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![alt](%E7%94%BB%E5%83%8F%201.png)", baseURL: baseURL
        )

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("同一行の複数画像をそれぞれ差し替える")
    func embedsMultipleImagesOnOneLine() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "a.png", data: pngData)
        let gifData = Data([0x47, 0x49, 0x46])
        try tmp.file(named: "b.gif", data: gifData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "![a](a.png) と ![b](b.gif)", baseURL: baseURL
        )

        let expected = "![a](\(dataURI(pngData, mimeType: "image/png"))) と "
            + "![b](\(dataURI(gifData, mimeType: "image/gif")))"
        #expect(result == expected)
    }

    /// 埋め込み対象外の markdown(リモート URL・欠損ファイル・非対応拡張子・フェンスコード・
    /// チルダフェンス・インラインコード・素の markdown)は元の文字列のまま変更されないこと。
    /// いずれのケースでも photo.png / doc.pdf を用意した上で判定する。
    @Test(arguments: [
        "![remote](https://example.com/photo.png)", // リモート URL の画像
        "![missing](nowhere.png)", // 存在しないファイル
        "![pdf](doc.pdf)", // 非対応拡張子のファイル
        """
        ```markdown
        ![alt](photo.png)
        ```
        """, // フェンスコードブロック内の画像記法
        """
        ~~~
        ![alt](photo.png)
        ~~~
        """, // チルダフェンス内の画像記法
        "記法は `![alt](photo.png)` と書く", // インラインコード内の画像記法
        "# 見出し\n\n[リンク](other.md) と本文。", // 画像記法を含まない markdown
    ])
    func leavesMarkdownUntouchedWhenNotEmbeddable(markdown: String) throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "photo.png", data: pngData)
        try tmp.file(named: "doc.pdf", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown)
    }

    @Test("サイズ上限を超える画像は変更しない")
    func leavesOversizedImageUntouched() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "big.png", data: Data(count: 100))
        let baseURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "![big](big.png)"

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: markdown, baseURL: baseURL, maxImageSizeBytes: 99
        )

        #expect(result == markdown)
    }

    @Test("フェンス終了後の画像は差し替える")
    func embedsImageAfterFenceCloses() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "photo.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = """
        ```
        ![in fence](photo.png)
        ```
        ![out](photo.png)
        """

        let result = MarkdownImageEmbedder.embedLocalImages(in: markdown, baseURL: baseURL)

        let expected = """
        ```
        ![in fence](photo.png)
        ```
        ![out](\(dataURI(pngData, mimeType: "image/png")))
        """
        #expect(result == expected)
    }

    @Test("インラインコードの後ろにある画像は差し替える")
    func embedsImageAfterInlineCode() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try tmp.file(named: "photo.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")

        let result = MarkdownImageEmbedder.embedLocalImages(
            in: "`code` ![alt](photo.png)", baseURL: baseURL
        )

        #expect(result == "`code` ![alt](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("ファイルが変わったら新しい内容で再生成する(キャッシュを無効化する)")
    func regeneratesAfterFileChanges() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let imageURL = try tmp.file(named: "photo.png", data: pngData)
        let baseURL = tmp.url.appendingPathComponent("doc.md")
        let markdown = "![alt](photo.png)"

        let first = MarkdownImageEmbedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(first == "![alt](\(dataURI(pngData, mimeType: "image/png")))")

        // 同じパスを異なる内容(異なるサイズ)で上書きし、キャッシュが再利用されないことを確認する
        let gifBytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        try gifBytes.write(to: imageURL)

        let second = MarkdownImageEmbedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(second == "![alt](\(dataURI(gifBytes, mimeType: "image/png")))")
    }
}
