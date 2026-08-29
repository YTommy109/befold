@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import PDFKit
import Testing

/// 画像・PDF などバイナリファイルの読み込みと、そのサイズ上限・読み込み失敗時の扱いを検証する。
///
/// 経路は 2 本ある。画像は base64 の文字列にして JS へ渡し、PDF は生データのまま
/// `PDFView` が描く(TASK-564.1 / ADR 0009)。上限と拒否理由は両経路で共有する。
@Suite
@MainActor
struct ViewerStoreBinaryContentTests {
    /// 実際の画像・PDF ファイルは isBinary 判定が true になるため、テストでも
    /// setBinary(true) を付けて「バイナリ判定より先にバイナリとして読む」順序を検証する。
    @Test
    func openImageFileLoadsBase64Content() async {
        let file = URL(fileURLWithPath: "/files/photo.png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.contentState.isRejected)
        #expect(store.contentState.fileType == .image(mimeType: "image/png"))
        #expect(store.contentState.content == data.base64EncodedString())

        store.close()
    }

    /// PDF は base64 化せず生データのまま表示状態へ載る(`PDFView` が Data を直接受ける)。
    @Test
    func openPDFFileLoadsRawData() async {
        let file = URL(fileURLWithPath: "/files/doc.pdf")
        let data = minimalPDFData()
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.contentState.isRejected)
        #expect(store.contentState.fileType == .pdf)
        #expect(store.contentState.data == data)
        #expect(store.contentState.content.isEmpty)

        store.close()
    }

    /// PDF として開けないファイルは、読み込みに成功していても拒否する。
    /// 拒否しないと `PDFView` が黙って空白を出すだけになり、バナーも出ない。
    @Test
    func damagedPDFMarksUnsupported() async {
        let file = URL(fileURLWithPath: "/files/damaged.pdf")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data("%PDF-1.4".utf8), at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.rejectReason == .damagedDocument)
        #expect(store.contentState.data == nil)

        store.close()
    }

    @Test
    func imageFileWatcherCallbackReloadsContent() async {
        let file = URL(fileURLWithPath: "/files/photo.png")
        let data1 = Data([0x89, 0x50, 0x4E, 0x47])
        let data2 = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
        let reader = InMemoryFileReader()
        reader.setDataFile(data1, at: file)
        reader.setBinary(true, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        #expect(store.contentState.content == data1.base64EncodedString())

        reader.setDataFile(data2, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.contentState.content == data2.base64EncodedString())

        store.close()
    }

    @Test
    func imageOverBinarySizeLimitMarksUnsupported() async {
        let file = URL(fileURLWithPath: "/files/huge.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.isRejected)
        #expect(store.contentState.content == "")

        store.close()
    }

    /// 画像・PDF の読み込み失敗は無表示ではなく非対応表示にする。
    @Test
    func imageReadFailureMarksUnsupported() async {
        let file = URL(fileURLWithPath: "/files/locked.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setReadError(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.isRejected)
        #expect(store.contentState.content == "")

        store.close()
    }

    /// PDF/画像は NormalizedTextCache を作らないため、同一内容スキップの hash は
    /// LoadedContent が運ぶ。これが nil に戻ると、内容が 1 バイトも変わらない
    /// ウォッチャイベント(mtime/xattr の更新、同ディレクトリの変化)のたびに
    /// contentRevision が増えてフル再描画が走り、描画面が作り直されて画面がちらつく
    /// (Issue #608)。
    @Test(arguments: [
        (filename: "same.png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        (filename: "same.pdf", data: minimalPDFData()),
    ])
    func binaryReloadWithIdenticalContentDoesNotBumpRevision(
        filename: String, data: Data
    ) async {
        let file = URL(fileURLWithPath: "/files/\(filename)")
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        let revisionAfterOpen = store.contentState.contentRevision

        // 内容は書き換えずにウォッチャだけ発火させる。
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.contentState.contentRevision == revisionAfterOpen)

        store.close()
    }

    /// 拒否された読み込みに hash を与えると、content がどちらも空なので hash が一致し、
    /// 拒否理由の変化が同一内容スキップに握り潰される。LoadedContent.contentHash を
    /// 「読み込みに成功したときだけ non-nil」に保つ約束が破れたら、このテストが落ちる。
    @Test
    func rejectReasonTransitionIsNotSkipped() async {
        let file = URL(fileURLWithPath: "/files/transition.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        #expect(store.contentState.rejectReason == .fileTooLarge)

        reader.setSize(1, at: file)
        reader.setReadError(true, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.contentState.rejectReason == .unsupportedFormat)

        store.close()
    }
}

/// 1 ページだけの最小の PDF。`PDFDocument` が開けることだけが要件。
/// `@MainActor` の Suite 引数からも使えるよう、型の外の nonisolated な関数にする。
func minimalPDFData() -> Data {
    let document = PDFDocument()
    document.insert(PDFPage(), at: 0)
    return document.dataRepresentation() ?? Data()
}
