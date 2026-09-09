@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 「そもそもチャンク読みへ入るのか」の振り分け。境界は **`ChunkedTextReading` を
/// 一切使わない**こと——チャンク非対応の種別・サイズ上限・一括読み込みへ落ちる経路だけを
/// 見る。チャンクに載ったあとの蓄積・打ち切り・失敗は `ViewerStoreChunkTests` にある。
@Suite
@MainActor
struct ViewerStoreChunkRoutingTests {
    @Test("非行指向ファイルは従来の一括読み込み")
    func nonLineOrientedFileUsesFullLoad() async {
        let file = URL(fileURLWithPath: "/files/doc.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello\n\nWorld", at: file)
        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.content == "# Hello\n\nWorld")
        #expect(store.contentState.isTruncated == false)

        store.close()
    }

    @Test("10MB 超・50MB 以下の画像ファイルは正常に読み込める")
    func imageOverTextSizeLimitStillLoads() async {
        let file = URL(fileURLWithPath: "/files/large.png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.contentState.isRejected)
        #expect(store.contentState.fileType == .image(mimeType: "image/png"))
        #expect(store.contentState.content == data.base64EncodedString())

        store.close()
    }

    /// markdown はチャンク読み込みの対象になったため(Issue #307)、10MB 上限が
    /// 残るのはチャンク非対応(mmd/svg/html)だけになった。
    @Test("チャンク非対応テキストが 10MB を超えると fileTooLarge")
    func nonChunkableTextOverLimitIsRejected() async {
        let file = URL(fileURLWithPath: "/files/huge.html")
        let reader = InMemoryFileReader()
        reader.setFile("<h1>Big</h1>", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)
        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.rejectReason == .fileTooLarge)

        store.close()
    }

    @Test("事前サイズチェックをすり抜けた場合(fileSize が nil)でも NormalizedTextCache の fileTooLarge が unsupportedFormat に丸められない")
    func sizeCheckBypassStillReportsFileTooLarge() async {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data(count: NormalizedTextCache.maxFileSizeBytes + 1), at: file)
        reader.setSizeUnknown(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.rejectReason == .fileTooLarge)
        #expect(store.contentState.content == "")

        store.close()
    }
}
