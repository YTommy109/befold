@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

struct MockFileWatcher: FileWatching {
    func stop() {}
}

/// 事前に与えたチャンク列を順に返すモック。最後のチャンクと同時に isAtEnd を返す。
/// バックグラウンドの読み込みタスクから呼ばれるため LockedBox でスレッド安全にする。
final class MockChunkedReader: ChunkedTextReading, @unchecked Sendable {
    private let chunks: [String]
    private let index = LockedBox(0)

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func readNextChunk() async throws -> (text: String, isAtEnd: Bool) {
        let current = index.get()
        guard current < chunks.count else { return ("", true) }
        index.set(current + 1)
        return (chunks[current], current + 1 >= chunks.count)
    }
}

/// 初回チャンクは成功し、2 回目以降の readNextChunk が throw するモック
/// (セッション途中の読み込みエラーからの回復テスト用)。
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

/// UserDefaults.standard を読むと過去の実行で永続化された値に影響されるため、
/// テストごとに使い捨てのスイートを注入して密閉性を保つ。
/// `onChangeBox` / `onRenameBox` を渡すと watcherFactory に渡されたコールバックを捕捉し、
/// テストから手動で発火できるようにする(ファイル監視イベントのシミュレート用)。
@MainActor
func makeStore(
    reader: InMemoryFileReader,
    onChangeBox: LockedBox<(@MainActor @Sendable () -> Void)?>? = nil,
    onRenameBox: LockedBox<(@MainActor @Sendable (URL) -> Void)?>? = nil,
    chunkedReaderFactory: ViewerStore.ChunkedReaderFactory? = nil,
    clock: any Clock<Duration> = ContinuousClock()
) -> ViewerStore {
    ViewerStore(
        watcherFactory: { _, onChange, onRename in
            onChangeBox?.set(onChange)
            onRenameBox?.set(onRename)
            return MockFileWatcher()
        },
        fileReader: reader,
        chunkedReaderFactory: chunkedReaderFactory,
        defaults: makeIsolatedDefaults(prefix: "ViewerStoreTests"),
        clock: clock
    )
}

/// openFile / 監視コールバックが予約した非同期読み込みの完了を待つ。
@MainActor
func awaitLoad(_ store: ViewerStore) async {
    await store.loadTask?.value
}

/// openFile して非同期読み込みの完了まで待つ(同期読み込み時代の openFile 相当)。
@MainActor
func openAndLoad(_ store: ViewerStore, _ url: URL) async {
    store.openFile(url)
    await awaitLoad(store)
}

@Suite
@MainActor
struct ViewerStoreTests {
    @Test(arguments: [
        ("test.mmd", "graph TD; A-->B", FileType.mmd),
        ("test.md", "# Hello", FileType.markdown),
    ])
    func openFileByType(filename: String, content: String, expectedType: FileType) async {
        let file = URL(fileURLWithPath: "/files/\(filename)")
        let reader = InMemoryFileReader()
        reader.setFile(content, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.content == content)
        #expect(store.fileType == expectedType)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openEmptyFile() async {
        let file = URL(fileURLWithPath: "/files/empty.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("", at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.content == "")

        store.close()
    }

    @Test
    func reopenDifferentFile() async {
        let file1 = URL(fileURLWithPath: "/files/first.mmd")
        let file2 = URL(fileURLWithPath: "/files/second.md")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file1)
        reader.setFile("# Second", at: file2)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file1)
        #expect(store.content == "graph TD; A-->B")
        #expect(store.fileType == .mmd)

        await openAndLoad(store, file2)

        #expect(store.content == "# Second")
        #expect(store.fileType == .markdown)
        #expect(store.filePath == file2)

        store.close()
    }

    @Test
    func openBinaryFileMarksUnsupported() async {
        let file = URL(fileURLWithPath: "/files/data.bin")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.rejectReason == .unsupportedFormat)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openTextFileWithUnknownExtensionIsNotUnsupported() async {
        let file = URL(fileURLWithPath: "/files/notes.txt")
        let reader = InMemoryFileReader()
        reader.setFile("hello", at: file)

        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["hello"]) }
        )
        await openAndLoad(store, file)

        #expect(!store.isRejected)
        #expect(store.content == "hello")
        #expect(store.fileType == .code(language: "plaintext"))

        store.close()
    }

    @Test
    func openOversizedFileMarksUnsupportedWithoutLoading() async {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.rejectReason == .fileTooLarge)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openFileAtSizeLimitLoadsContent() async {
        let file = URL(fileURLWithPath: "/files/ok.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func switchingFromOversizedToNormalResetsUnsupported() async {
        let hugeFile = URL(fileURLWithPath: "/files/huge.md")
        let normalFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("x", at: hugeFile)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: hugeFile)
        reader.setFile("# Hello", at: normalFile)

        let store = makeStore(reader: reader)
        await openAndLoad(store, hugeFile)
        #expect(store.isRejected)

        await openAndLoad(store, normalFile)
        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func switchingFromBinaryToTextResetsUnsupported() async {
        let binaryFile = URL(fileURLWithPath: "/files/data.bin")
        let textFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: binaryFile)
        reader.setBinary(true, at: binaryFile)
        reader.setFile("# Hello", at: textFile)

        let store = makeStore(reader: reader)
        await openAndLoad(store, binaryFile)
        #expect(store.isRejected)

        await openAndLoad(store, textFile)
        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func watcherCallbackReloadsContent() async {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        #expect(store.content == "graph TD; A-->B")

        // ファイル内容を書き換えてから監視コールバックを発火する
        reader.setFile("graph TD; X-->Y", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.content == "graph TD; X-->Y")

        store.close()
    }

    @Test
    func watcherRenameUpdatesPathAndReloadsContent() async {
        let oldFile = URL(fileURLWithPath: "/files/old.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: oldFile)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(reader: reader, onRenameBox: onRenameBox)
        await openAndLoad(store, oldFile)
        #expect(store.filePath == oldFile)

        // 別名 + 別内容 + 別タイプへ移動したことを通知する
        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)

        nonisolated(unsafe) var renamedTo: URL?
        store.onFileRenamed = { _, newURL in renamedTo = newURL }
        onRenameBox.get()?(newFile)
        await awaitLoad(store)

        #expect(store.filePath == newFile)
        #expect(store.fileType == .markdown)
        #expect(store.content == "# Renamed")
        #expect(renamedTo == newFile)

        store.close()
    }

    /// 実際の画像・PDF ファイルは isBinary 判定が true になるため、テストでも
    /// setBinary(true) を付けて「バイナリ判定より先にバイナリとして読む」順序を検証する。
    @Test(arguments: [
        (
            filename: "photo.png", data: Data([0x89, 0x50, 0x4E, 0x47]),
            expectedType: FileType.image(mimeType: "image/png")
        ),
        (filename: "doc.pdf", data: Data("%PDF-1.4".utf8), expectedType: FileType.pdf),
    ])
    func openBinaryFileLoadsBase64Content(filename: String, data: Data, expectedType: FileType) async {
        let file = URL(fileURLWithPath: "/files/\(filename)")
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.isRejected)
        #expect(store.fileType == expectedType)
        #expect(store.content == data.base64EncodedString())

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
        #expect(store.content == data1.base64EncodedString())

        reader.setDataFile(data2, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.content == data2.base64EncodedString())

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

        #expect(store.isRejected)
        #expect(store.content == "")

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

        #expect(store.isRejected)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openFileFiresOnContentReloaded() async {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let store = makeStore(reader: reader)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, file)

        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func watcherCallbackFiresOnContentReloaded() async {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, file)
        #expect(firedCount == 1)

        // ファイル変更(監視コールバック)のたびに再発火する。
        reader.setFile("graph TD; X-->Y", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(firedCount == 2)

        store.close()
    }

    /// ファイルサイズ超過 → 縮小のような、isRejected が変化する再読込でも発火することを確認する。
    @Test
    func watcherCallbackFiresOnContentReloadedWhenUnsupportedChanges() async {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, file)
        #expect(store.isRejected)
        #expect(firedCount == 1)

        // サイズが上限内に戻る → isRejected が false に変わる再読込でも発火する。
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(!store.isRejected)
        #expect(firedCount == 2)

        store.close()
    }

    @Test
    func watcherRenameFiresOnContentReloaded() async {
        let oldFile = URL(fileURLWithPath: "/files/old.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: oldFile)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(reader: reader, onRenameBox: onRenameBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, oldFile)
        #expect(firedCount == 1)

        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)
        onRenameBox.get()?(newFile)
        await awaitLoad(store)

        #expect(firedCount == 2)

        store.close()
    }

    @Test
    func openFileStopsPreviousWatcher() {
        let file1 = URL(fileURLWithPath: "/files/a.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("A", at: file1)
        reader.setFile("B", at: URL(fileURLWithPath: "/files/b.mmd"))

        nonisolated(unsafe) var stopCount = 0
        let store = ViewerStore(watcherFactory: { _, _, _ in
            StopCountingWatcher { stopCount += 1 }
        }, fileReader: reader)

        store.openFile(file1)
        #expect(stopCount == 0)

        let file2 = URL(fileURLWithPath: "/files/b.mmd")
        store.openFile(file2)
        #expect(stopCount == 1)

        store.close()
    }

    @Test("showLineNumbers のデフォルトは false")
    func showLineNumbersDefaultsToFalse() {
        let store = makeStore(reader: InMemoryFileReader())
        #expect(!store.showLineNumbers)
        store.close()
    }

    @Test("showLineNumbers のトグルが UserDefaults に永続化される")
    func showLineNumbersPersistedToUserDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerStoreTests-showLineNumbers")
        let store = ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: InMemoryFileReader(),
            defaults: defaults
        )

        store.showLineNumbers = true
        #expect(defaults.bool(forKey: "ShowLineNumbers") == true)

        store.showLineNumbers = false
        #expect(defaults.bool(forKey: "ShowLineNumbers") == false)

        store.close()
    }

    @Test("10MB 以下のファイルは isTruncated = false")
    func normalFileIsNotTruncated() async {
        let file = URL(fileURLWithPath: "/files/small.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.isTruncated)
        #expect(!store.isRejected)

        store.close()
    }
}

/// isLoading(task-30 の読み込み中インジケータ用状態)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
@Suite
@MainActor
struct ViewerStoreLoadingTests {
    @Test("openFile 直後は isLoading = true、読込完了後は false になる(task-30)")
    func isLoadingReflectsInFlightLoad() async {
        let file = URL(fileURLWithPath: "/files/loading.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)
        #expect(store.isLoading)

        await awaitLoad(store)
        #expect(!store.isLoading)

        store.close()
    }

    @Test("close() は実行中の isLoading をリセットする")
    func closeResetsIsLoading() {
        let file = URL(fileURLWithPath: "/files/loading2.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)
        #expect(store.isLoading)

        store.close()
        #expect(!store.isLoading)
    }
}

/// 行指向ファイルのチャンク読み込み(段階読み込み)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
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
        // 「続きを読み込めませんでした」に切り替える。正常な EOF との区別が
        // TASK-25 の狙い)。
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

    @Test("チャンク読み込みエラー後にファイルが再読込されると loadFailed がリセットされる(TASK-39)")
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

    @Test("チャンク読み込みエラー後に同一内容で再読込されても loadFailed がリセットされる(TASK-45)")
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

    @Test("事前サイズチェックをすり抜けた場合(fileSize が nil)でも NormalizedTextCache の fileTooLarge が unsupportedFormat に丸められない(TASK-41)")
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

private struct StopCountingWatcher: FileWatching {
    let onStop: @Sendable () -> Void
    func stop() {
        onStop()
    }
}
