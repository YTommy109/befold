import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// ロード時のウォームアップ(ViewerLoadPipeline.load)と描画直前の埋め込み
/// (ViewerRenderer.renderableContent)が、本番の既定値では同一の
/// MarkdownImageEmbedder インスタンス(.shared)を経由することをピン留めする。
///
/// 両者の `imageEmbedder` は独立した `= .shared` デフォルト引数のため、片方だけが
/// 別インスタンスへ分岐してもコンパイルは通る。分岐するとキャッシュが共有されず、
/// markdown 描画のたびに全ローカル画像をメインスレッドで再読込・base64 化する
/// (画像の多いドキュメントでビーチボール)。
///
/// そのため、このテストだけは意図的に `imageEmbedder` を注入せず本番の既定値を通す
/// (`.shared` は DefaultFileReader を持つため、ここだけは実 FS が必要)。実 FS 依存は
/// TempDir 1 個 + 8 バイトの PNG 1 個に抑え、ウォームアップ後にその画像のパーミッションを
/// 0o000 にして「サイズ・更新日時は読めるが内容は読めない」状態を作る
/// (ファイル削除ではサイズ照合の時点で埋め込み自体が中止され、キャッシュ共有を判定できない)。
@Suite
struct MarkdownImageEmbedderSharedInstanceTests {
    private static let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test("ロード時のウォームアップと描画時の埋め込みが同一インスタンス(.shared)のキャッシュを共有する")
    func warmupAndRenderShareSharedEmbedderCache() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let markdown = "![alt](shared.png)"
        let markdownURL = try tmp.file(named: "doc.md", contents: markdown)
        let imageURL = tmp.url.appendingPathComponent("shared.png")
        try Self.pngData.write(to: imageURL)

        // 本番の既定値(imageEmbedder 未指定 = .shared)でウォームアップする。
        let fileReader = DefaultFileReader()
        _ = await ViewerLoadPipeline.load(
            resolved: markdownURL,
            fileType: .markdown,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: { cache, fileType in
                try ViewerLoadPipeline.defaultChunkedReaderFactory(cache, fileType)
            },
            embedLocalImages: true
        )

        // 内容だけを読めなくする(サイズ・更新日時は不変なのでキャッシュ照合は成立する)。
        // 以降 data URI が返るのはウォームアップ時のキャッシュを引けた場合、
        // つまり両者が同一インスタンスを経由している場合だけ。
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: imageURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path) }

        // root 実行などで権限が効かないとテストが無意味に緑になるため、
        // 実際に内容が読めなくなったことを先に確認する。
        try #require((try? Data(contentsOf: imageURL)) == nil)

        // 本番の既定値(imageEmbedder 未指定 = .shared)で描画直前の埋め込みを行う。
        let rendered = RenderableContent.make(
            markdown, fileType: .markdown, filePath: markdownURL, isSourceMode: false
        )

        let expectedURI = "data:image/png;base64,\(Self.pngData.base64EncodedString())"
        #expect(rendered == "![alt](\(expectedURI))")
    }
}
