@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 2 回目の readNextChunk で失敗するモック(チャンク読み込みエラーの検証用)。
private final class FailingSecondChunkReader: ChunkedTextReading, @unchecked Sendable {
    private let firstChunk: String
    private let readCount = LockedBox(0)

    init(firstChunk: String) {
        self.firstChunk = firstChunk
    }

    func readNextChunk() async throws -> (text: String, isAtEnd: Bool) {
        let count = readCount.get() + 1
        readCount.set(count)
        guard count == 1 else { throw TextEncodingError.decodeFailed }
        return (firstChunk, false)
    }
}

@Suite
@MainActor
struct ViewerStoreChunkTests {
    @Test("行指向ファイルは初回チャンクのみ表示し isTruncated = true になる")
    func lineOrientedFileShowsFirstChunk() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4"]) }
        )
        await openAndLoad(store, file)

        #expect(store.content == "a,b\n1,2\n")
        #expect(store.isTruncated == true)
        #expect(store.displayedLineCount == 2)

        store.close()
    }

    @Test("loadMoreLines は次チャンクを蓄積し isTruncated を更新する")
    func loadMoreLinesAccumulatesContent() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4"]) }
        )
        await openAndLoad(store, file)

        let result = await store.loadMoreLines()

        #expect(result != nil)
        #expect(result?.chunk == "3,4")
        #expect(store.content == "a,b\n1,2\n3,4")
        #expect(store.isTruncated == false)

        store.close()
    }

    @Test("loadMoreLines は追記のたびに contentRevision を増分して返す")
    func loadMoreLinesReturnsIncrementedContentRevision() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4\n5,6", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4\n", "5,6"]) }
        )
        await openAndLoad(store, file)
        let initialRevision = store.contentRevision

        let firstResult = await store.loadMoreLines()
        #expect(firstResult?.contentRevision == initialRevision + 1)
        #expect(store.contentRevision == initialRevision + 1)

        let secondResult = await store.loadMoreLines()
        #expect(secondResult?.contentRevision == initialRevision + 2)
        #expect(store.contentRevision == initialRevision + 2)

        store.close()
    }

    @Test("loadMoreLines は全チャンク読み込み後は nil を返す")
    func loadMoreLinesReturnsNilWhenComplete() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["a,b"]) }
        )
        await openAndLoad(store, file)

        #expect(store.isTruncated == false)
        #expect(await store.loadMoreLines() == nil)

        store.close()
    }

    @Test("FileWatcher 発火でチャンクセッションがリセットされる")
    func fileWatcherResetChunkSession() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4\n5,6", at: file)
        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let callCount = LockedBox(0)
        let store = makeStore(
            reader: reader,
            onChangeBox: onChangeBox,
            chunkedReaderFactory: { _, _ in
                callCount.update { $0 += 1 }
                return MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4\n5,6"])
            }
        )
        await openAndLoad(store, file)
        #expect(callCount.get() == 1)
        #expect(store.isTruncated == true)

        _ = await store.loadMoreLines()
        #expect(store.isTruncated == false)

        // ファイル内容が変わった場合にセッションがリセットされることを検証する。
        reader.setFile("a,b\n1,2\n3,4\n5,6\n7,8", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        #expect(callCount.get() == 2)
        #expect(store.content == "a,b\n1,2\n")
        #expect(store.isTruncated == true)

        store.close()
    }

    @Test("末尾に改行がないチャンクは途中の行も 1 行として数える")
    func displayedLineCountCountsTrailingPartialLine() async {
        let file = URL(fileURLWithPath: "/files/oneline.js")
        let reader = InMemoryFileReader()
        reader.setFile("var x = 1;", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["var x = 1;", "var y = 2;"]) }
        )
        await openAndLoad(store, file)

        // 改行なしの強制分割チャンクでも「0 行」ではなく途中行を 1 行と数える。
        #expect(store.displayedLineCount == 1)

        let result = await store.loadMoreLines()
        #expect(result?.lineCount == 1)
        #expect(store.displayedLineCount == 1)

        store.close()
    }

    @Test("チャンク読み込みエラー時は空チャンクと loadFailed=true(isTruncated=true 維持)を返し、表示済みコンテンツを保持してセッションを終了する")
    func loadMoreLinesErrorKeepsContentAndStops() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("first\nsecond", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in
                FailingSecondChunkReader(firstChunk: "old\n")
            }
        )
        await openAndLoad(store, file)
        #expect(store.content == "old\n")
        #expect(store.isTruncated == true)

        // 2 回目の読み込みが TextEncodingError で失敗 → 表示済みコンテンツを保持し
        // セッション終了。10MB 超ファイルで fileTooLarge に置き換わることを防ぐ。
        // isTruncated は true のまま維持し loadFailed で区別する(バナーは消さず
        // 「続きを読み込めませんでした」に切り替える。正常な EOF と区別することが狙い)。
        let result = await store.loadMoreLines()
        #expect(result != nil)
        #expect(result?.chunk == "")
        #expect(result?.isTruncated == true)
        #expect(result?.loadFailed == true)
        #expect(store.content == "old\n")
        #expect(store.isTruncated == true)
        #expect(store.loadFailed == true)

        store.close()
    }

    @Test("チャンク読み込みエラー後にファイルが再読込されると loadFailed がリセットされる")
    func loadFailedResetsOnReload() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("old\nrest", at: file)
        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let callCount = LockedBox(0)
        let store = makeStore(
            reader: reader,
            onChangeBox: onChangeBox,
            chunkedReaderFactory: { _, _ in
                callCount.update { $0 += 1 }
                return callCount.get() == 1
                    ? FailingSecondChunkReader(firstChunk: "old\n")
                    : MockChunkedReader(chunks: ["new\n", "content"])
            }
        )
        await openAndLoad(store, file)
        _ = await store.loadMoreLines()
        #expect(store.loadFailed == true)

        // ファイル変更を検知した再読込で新しいチャンクセッションが張り直され、
        // loadFailed は false にリセットされる(エラーバナーが再描画で無効な
        // 「さらに読み込む」ボタンへ戻らないことの前提となる状態)。
        reader.setFile("new\ncontent", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)
        #expect(store.loadFailed == false)
        #expect(store.isTruncated == true)

        store.close()
    }

    @Test("チャンク読み込みエラー後に同一内容で再読込されても loadFailed がリセットされる")
    func loadFailedResetsOnReloadWithIdenticalContent() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("old\nrest", at: file)
        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let callCount = LockedBox(0)
        let store = makeStore(
            reader: reader,
            onChangeBox: onChangeBox,
            chunkedReaderFactory: { _, _ in
                callCount.update { $0 += 1 }
                return callCount.get() == 1
                    ? FailingSecondChunkReader(firstChunk: "old\n")
                    : MockChunkedReader(chunks: ["old\n", "rest"])
            }
        )
        await openAndLoad(store, file)
        _ = await store.loadMoreLines()
        #expect(store.loadFailed == true)

        // ハッシュと fileType が変わらない「同一内容」の再保存であっても、
        // 直前のチャンク読込が失敗している場合は early-return せずに
        // chunkSession を張り直し loadFailed をリセットする(apply() の早期リターンが
        // loadFailed を無視すると、エラーバナーが再読込しても消えなくなる)。
        onChangeBox.get()?()
        await awaitLoad(store)
        #expect(store.loadFailed == false)

        let result = await store.loadMoreLines()
        #expect(result?.loadFailed == false)
        #expect(result?.chunk == "rest")

        store.close()
    }

    @Test("chunkedReaderFactory はファイル種別を受け取る(CSV 判定に使う)")
    func chunkedReaderFactoryReceivesFileType() async {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b", at: file)
        let receivedType = LockedBox<FileType?>(nil)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, fileType in
                receivedType.set(fileType)
                return MockChunkedReader(chunks: ["a,b"])
            }
        )
        await openAndLoad(store, file)

        #expect(receivedType.get()?.csvDelimiter == ",")

        store.close()
    }

    @Test("レガシーエンコーディングの行指向ファイルはチャンク読みできる")
    func legacyEncodingLineOrientedFileUsesDirectChunking() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let text = "名前,値\nテスト,1\n"
        let data = try #require(text.data(using: .shiftJIS))
        let file = try tmp.file(named: "data.csv", data: data)

        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.rejectReason == nil)
        #expect(store.content.contains("名前"))
        #expect(store.isTruncated == false)

        store.close()
    }

    @Test("非行指向ファイルは従来の一括読み込み")
    func nonLineOrientedFileUsesFullLoad() async {
        let file = URL(fileURLWithPath: "/files/doc.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello\n\nWorld", at: file)
        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.content == "# Hello\n\nWorld")
        #expect(store.isTruncated == false)

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

        #expect(!store.isRejected)
        #expect(store.fileType == .image(mimeType: "image/png"))
        #expect(store.content == data.base64EncodedString())

        store.close()
    }

    @Test("非行指向テキストが 10MB を超えると fileTooLarge")
    func nonLineOrientedTextOverLimitIsRejected() async {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Big", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)
        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.rejectReason == .fileTooLarge)

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

        #expect(store.rejectReason == .fileTooLarge)
        #expect(store.content == "")

        store.close()
    }
}
