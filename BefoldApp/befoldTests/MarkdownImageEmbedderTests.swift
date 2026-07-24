// BefoldApp/befoldTests/MarkdownImageEmbedderTests.swift
import BefoldKit
import Foundation
import Testing

@Suite
struct MarkdownImageEmbedderTests {
    private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// メモリ上のファイル配置の基準ディレクトリ(実ファイルシステムには存在しない)。
    private let baseURL = URL(fileURLWithPath: "/virtual/docs/doc.md")

    private func url(_ relativePath: String) -> URL {
        baseURL.deletingLastPathComponent().appendingPathComponent(relativePath).standardized
    }

    private func dataURI(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    /// 指定した画像を配置した埋め込み器を返す。キャッシュはインスタンス所有のため
    /// テストごとに新しい埋め込み器を作れば互いに干渉しない。
    private func makeEmbedder(
        files: [String: Data]
    ) -> (embedder: MarkdownImageEmbedder, fileReader: InMemoryFileReader) {
        let fileReader = InMemoryFileReader()
        for (path, data) in files {
            fileReader.setDataFile(data, at: url(path))
        }
        return (MarkdownImageEmbedder(fileReader: fileReader), fileReader)
    }

    @Test("相対パスのローカル画像を data URI に差し替える")
    func embedsRelativeLocalImage() {
        let embedder = makeEmbedder(files: ["photo.png": pngData]).embedder

        let result = embedder.embedLocalImages(
            in: "before\n![説明](photo.png)\nafter", baseURL: baseURL
        )

        #expect(result == "before\n![説明](\(dataURI(pngData, mimeType: "image/png")))\nafter")
    }

    @Test("サブディレクトリの相対パスを解決する")
    func embedsImageInSubdirectory() {
        let embedder = makeEmbedder(files: ["images/chart.png": pngData]).embedder

        let result = embedder.embedLocalImages(in: "![chart](./images/chart.png)", baseURL: baseURL)

        #expect(result == "![chart](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("絶対パスのローカル画像を data URI に差し替える")
    func embedsAbsolutePathImage() {
        let embedder = makeEmbedder(files: ["photo.jpg": pngData]).embedder
        let imagePath = url("photo.jpg").path

        let result = embedder.embedLocalImages(in: "![alt](\(imagePath))", baseURL: baseURL)

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/jpeg")))")
    }

    @Test("SVG を image/svg+xml の data URI に差し替える")
    func embedsSVGImage() {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        let embedder = makeEmbedder(files: ["icon.svg": svg]).embedder

        let result = embedder.embedLocalImages(in: "![icon](icon.svg)", baseURL: baseURL)

        #expect(result == "![icon](\(dataURI(svg, mimeType: "image/svg+xml")))")
    }

    @Test("title 付き記法で title を保持する")
    func preservesTitle() {
        let embedder = makeEmbedder(files: ["photo.png": pngData]).embedder

        let result = embedder.embedLocalImages(in: "![alt](photo.png \"タイトル\")", baseURL: baseURL)

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/png")) \"タイトル\")")
    }

    @Test("パーセントエンコードされたパスを解決する")
    func resolvesPercentEncodedPath() {
        let embedder = makeEmbedder(files: ["画像 1.png": pngData]).embedder

        let result = embedder.embedLocalImages(
            in: "![alt](%E7%94%BB%E5%83%8F%201.png)", baseURL: baseURL
        )

        #expect(result == "![alt](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("同一行の複数画像をそれぞれ差し替える")
    func embedsMultipleImagesOnOneLine() {
        let gifData = Data([0x47, 0x49, 0x46])
        let embedder = makeEmbedder(files: ["a.png": pngData, "b.gif": gifData]).embedder

        let result = embedder.embedLocalImages(in: "![a](a.png) と ![b](b.gif)", baseURL: baseURL)

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
    func leavesMarkdownUntouchedWhenNotEmbeddable(markdown: String) {
        let embedder = makeEmbedder(files: ["photo.png": pngData, "doc.pdf": pngData]).embedder

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown)
    }

    @Test("サイズ上限を超える画像は変更しない")
    func leavesOversizedImageUntouched() {
        let embedder = makeEmbedder(files: ["big.png": Data(count: 100)]).embedder
        let markdown = "![big](big.png)"

        let result = embedder.embedLocalImages(
            in: markdown, baseURL: baseURL, maxImageSizeBytes: 99
        )

        #expect(result == markdown)
    }

    @Test("サイズを取得できない画像は変更しない")
    func leavesImageWithUnknownSizeUntouched() {
        let (embedder, fileReader) = makeEmbedder(files: ["photo.png": pngData])
        fileReader.setSizeUnknown(true, at: url("photo.png"))
        let markdown = "![alt](photo.png)"

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown)
    }

    @Test("読み込みに失敗した画像は変更しない")
    func leavesUnreadableImageUntouched() {
        let (embedder, fileReader) = makeEmbedder(files: ["photo.png": pngData])
        fileReader.setReadError(true, at: url("photo.png"))
        let markdown = "![alt](photo.png)"

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        #expect(result == markdown)
    }

    @Test("フェンス終了後の画像は差し替える")
    func embedsImageAfterFenceCloses() {
        let embedder = makeEmbedder(files: ["photo.png": pngData]).embedder
        let markdown = """
        ```
        ![in fence](photo.png)
        ```
        ![out](photo.png)
        """

        let result = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        let expected = """
        ```
        ![in fence](photo.png)
        ```
        ![out](\(dataURI(pngData, mimeType: "image/png")))
        """
        #expect(result == expected)
    }

    @Test("インラインコードの後ろにある画像は差し替える")
    func embedsImageAfterInlineCode() {
        let embedder = makeEmbedder(files: ["photo.png": pngData]).embedder

        let result = embedder.embedLocalImages(in: "`code` ![alt](photo.png)", baseURL: baseURL)

        #expect(result == "`code` ![alt](\(dataURI(pngData, mimeType: "image/png")))")
    }

    @Test("サイズが変わったら新しい内容で再生成する(キャッシュを無効化する)")
    func regeneratesAfterSizeChanges() {
        let (embedder, fileReader) = makeEmbedder(files: ["photo.png": pngData])
        let markdown = "![alt](photo.png)"

        let first = embedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(first == "![alt](\(dataURI(pngData, mimeType: "image/png")))")

        // 同じパスを異なる内容(異なるサイズ)で上書きし、キャッシュが再利用されないことを確認する
        let gifBytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        fileReader.setDataFile(gifBytes, at: url("photo.png"))

        let second = embedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(second == "![alt](\(dataURI(gifBytes, mimeType: "image/png")))")
    }

    @Test("サイズが同じでも更新日時が変わったら再生成する")
    func regeneratesAfterModificationDateChanges() {
        let (embedder, fileReader) = makeEmbedder(files: ["photo.png": pngData])
        let imageURL = url("photo.png")
        fileReader.setModificationDate(Date(timeIntervalSince1970: 1000), at: imageURL)
        let markdown = "![alt](photo.png)"

        let first = embedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(first == "![alt](\(dataURI(pngData, mimeType: "image/png")))")

        // サイズを変えずに内容と更新日時だけを変える(サイズだけをキャッシュキーにしていると検出できない)
        let sameSizeData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0xFF])
        fileReader.setDataFile(sameSizeData, at: imageURL)
        fileReader.setModificationDate(Date(timeIntervalSince1970: 2000), at: imageURL)

        let second = embedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(second == "![alt](\(dataURI(sameSizeData, mimeType: "image/png")))")
    }

    @Test("サイズと更新日時が同じならキャッシュ済みの data URI を返す")
    func reusesCachedDataURIWhenUnchanged() {
        let (embedder, fileReader) = makeEmbedder(files: ["photo.png": pngData])
        let imageURL = url("photo.png")
        fileReader.setModificationDate(Date(timeIntervalSince1970: 1000), at: imageURL)
        let markdown = "![alt](photo.png)"

        let first = embedder.embedLocalImages(in: markdown, baseURL: baseURL)

        // 読み込みを失敗させてもキャッシュヒットなら同じ結果を返す(＝再読込していない)。
        fileReader.setReadError(true, at: imageURL)

        let second = embedder.embedLocalImages(in: markdown, baseURL: baseURL)
        #expect(second == first)
    }
}
