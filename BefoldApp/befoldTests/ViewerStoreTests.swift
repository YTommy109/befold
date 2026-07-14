@testable import befold
import BefoldKit
import Foundation
import Testing

private struct MockFileWatcher: FileWatching {
    func stop() {}
}

private final class MockChunkedReader: ChunkedTextReading {
    private var chunks: [String]
    private var index = 0

    init(chunks: [String]) {
        self.chunks = chunks
    }

    var isAtEnd: Bool {
        index >= chunks.count
    }

    func readNextChunk() throws -> String {
        guard index < chunks.count else { return "" }
        defer { index += 1 }
        return chunks[index]
    }
}

/// UserDefaults.standard を読むと過去の実行で永続化された値に影響されるため、
/// テストごとに使い捨てのスイートを注入して密閉性を保つ。
/// `onChangeBox` / `onRenameBox` を渡すと watcherFactory に渡されたコールバックを捕捉し、
/// テストから手動で発火できるようにする(ファイル監視イベントのシミュレート用)。
@MainActor
private func makeStore(
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

@Suite
@MainActor
struct ViewerStoreTests {
    @Test(arguments: [
        ("test.mmd", "graph TD; A-->B", FileType.mmd),
        ("test.md", "# Hello", FileType.markdown),
    ])
    func openFileByType(filename: String, content: String, expectedType: FileType) {
        let file = URL(fileURLWithPath: "/files/\(filename)")
        let reader = InMemoryFileReader()
        reader.setFile(content, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.content == content)
        #expect(store.fileType == expectedType)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openEmptyFile() {
        let file = URL(fileURLWithPath: "/files/empty.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.content == "")

        store.close()
    }

    @Test
    func reopenDifferentFile() {
        let file1 = URL(fileURLWithPath: "/files/first.mmd")
        let file2 = URL(fileURLWithPath: "/files/second.md")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file1)
        reader.setFile("# Second", at: file2)

        let store = makeStore(reader: reader)
        store.openFile(file1)
        #expect(store.content == "graph TD; A-->B")
        #expect(store.fileType == .mmd)

        store.openFile(file2)

        #expect(store.content == "# Second")
        #expect(store.fileType == .markdown)
        #expect(store.filePath == file2)

        store.close()
    }

    @Test
    func openBinaryFileMarksUnsupported() {
        let file = URL(fileURLWithPath: "/files/data.bin")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.rejectReason == .unsupportedFormat)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openTextFileWithUnknownExtensionIsNotUnsupported() {
        let file = URL(fileURLWithPath: "/files/notes.txt")
        let reader = InMemoryFileReader()
        reader.setFile("hello", at: file)

        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _ in MockChunkedReader(chunks: ["hello"]) }
        )
        store.openFile(file)

        #expect(!store.isRejected)
        #expect(store.content == "hello")
        #expect(store.fileType == .code(language: "plaintext"))

        store.close()
    }

    @Test
    func openOversizedFileMarksUnsupportedWithoutLoading() {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.rejectReason == .fileTooLarge)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openFileAtSizeLimitLoadsContent() {
        let file = URL(fileURLWithPath: "/files/ok.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func switchingFromOversizedToNormalResetsUnsupported() {
        let hugeFile = URL(fileURLWithPath: "/files/huge.log")
        let normalFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("x", at: hugeFile)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: hugeFile)
        reader.setFile("# Hello", at: normalFile)

        let store = makeStore(reader: reader)
        store.openFile(hugeFile)
        #expect(store.isRejected)

        store.openFile(normalFile)
        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func switchingFromBinaryToTextResetsUnsupported() {
        let binaryFile = URL(fileURLWithPath: "/files/data.bin")
        let textFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("binary-ish", at: binaryFile)
        reader.setBinary(true, at: binaryFile)
        reader.setFile("# Hello", at: textFile)

        let store = makeStore(reader: reader)
        store.openFile(binaryFile)
        #expect(store.isRejected)

        store.openFile(textFile)
        #expect(!store.isRejected)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func watcherCallbackReloadsContent() {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        // ファイル内容を書き換えてから監視コールバックを発火する
        reader.setFile("graph TD; X-->Y", at: file)
        onChangeBox.get()?()

        #expect(store.content == "graph TD; X-->Y")

        store.close()
    }

    @Test
    func watcherRenameUpdatesPathAndReloadsContent() {
        let oldFile = URL(fileURLWithPath: "/files/old.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: oldFile)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(reader: reader, onRenameBox: onRenameBox)
        store.openFile(oldFile)
        #expect(store.filePath == oldFile)

        // 別名 + 別内容 + 別タイプへ移動したことを通知する
        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)

        nonisolated(unsafe) var renamedTo: URL?
        store.onFileRenamed = { renamedTo = $0 }
        onRenameBox.get()?(newFile)

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
    func openBinaryFileLoadsBase64Content(filename: String, data: Data, expectedType: FileType) {
        let file = URL(fileURLWithPath: "/files/\(filename)")
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isRejected)
        #expect(store.fileType == expectedType)
        #expect(store.content == data.base64EncodedString())

        store.close()
    }

    @Test
    func imageFileWatcherCallbackReloadsContent() {
        let file = URL(fileURLWithPath: "/files/photo.png")
        let data1 = Data([0x89, 0x50, 0x4E, 0x47])
        let data2 = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
        let reader = InMemoryFileReader()
        reader.setDataFile(data1, at: file)
        reader.setBinary(true, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        store.openFile(file)
        #expect(store.content == data1.base64EncodedString())

        reader.setDataFile(data2, at: file)
        onChangeBox.get()?()

        #expect(store.content == data2.base64EncodedString())

        store.close()
    }

    @Test
    func imageOverBinarySizeLimitMarksUnsupported() {
        let file = URL(fileURLWithPath: "/files/huge.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.isRejected)
        #expect(store.content == "")

        store.close()
    }

    /// 画像・PDF の読み込み失敗は無表示ではなく非対応表示にする。
    @Test
    func imageReadFailureMarksUnsupported() {
        let file = URL(fileURLWithPath: "/files/locked.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setReadError(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.isRejected)
        #expect(store.content == "")

        store.close()
    }

    @Test
    func openFileFiresOnContentReloaded() {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let store = makeStore(reader: reader)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        store.openFile(file)

        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func watcherCallbackFiresOnContentReloaded() {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        store.openFile(file)
        #expect(firedCount == 1)

        // ファイル変更(監視コールバック)のたびに再発火する。
        reader.setFile("graph TD; X-->Y", at: file)
        onChangeBox.get()?()

        #expect(firedCount == 2)

        store.close()
    }

    /// ファイルサイズ超過 → 縮小のような、isRejected が変化する再読込でも発火することを確認する。
    @Test
    func watcherCallbackFiresOnContentReloadedWhenUnsupportedChanges() {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        store.openFile(file)
        #expect(store.isRejected)
        #expect(firedCount == 1)

        // サイズが上限内に戻る → isRejected が false に変わる再読込でも発火する。
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)
        onChangeBox.get()?()

        #expect(!store.isRejected)
        #expect(firedCount == 2)

        store.close()
    }

    @Test
    func watcherRenameFiresOnContentReloaded() {
        let oldFile = URL(fileURLWithPath: "/files/old.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: oldFile)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(reader: reader, onRenameBox: onRenameBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        store.openFile(oldFile)
        #expect(firedCount == 1)

        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)
        onRenameBox.get()?(newFile)

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
    func normalFileIsNotTruncated() {
        let file = URL(fileURLWithPath: "/files/small.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isTruncated)
        #expect(!store.isRejected)

        store.close()
    }
}

/// 行指向ファイルのチャンク読み込み(段階読み込み)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
@Suite
@MainActor
struct ViewerStoreChunkTests {
    @Test("行指向ファイルは初回チャンクのみ表示し isTruncated = true になる")
    func lineOrientedFileShowsFirstChunk() {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _ in MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4"]) }
        )
        store.openFile(file)

        #expect(store.content == "a,b\n1,2\n")
        #expect(store.isTruncated == true)
        #expect(store.displayedLineCount == 3)

        store.close()
    }

    @Test("loadMoreLines は次チャンクを蓄積し isTruncated を更新する")
    func loadMoreLinesAccumulatesContent() {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _ in MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4"]) }
        )
        store.openFile(file)

        let result = store.loadMoreLines()

        #expect(result != nil)
        #expect(result?.chunk == "3,4")
        #expect(store.content == "a,b\n1,2\n3,4")
        #expect(store.isTruncated == false)

        store.close()
    }

    @Test("loadMoreLines は全チャンク読み込み後は nil を返す")
    func loadMoreLinesReturnsNilWhenComplete() {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b", at: file)
        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _ in MockChunkedReader(chunks: ["a,b"]) }
        )
        store.openFile(file)

        #expect(store.isTruncated == false)
        #expect(store.loadMoreLines() == nil)

        store.close()
    }

    @Test("FileWatcher 発火でチャンクセッションがリセットされる")
    func fileWatcherResetChunkSession() {
        let file = URL(fileURLWithPath: "/files/data.csv")
        let reader = InMemoryFileReader()
        reader.setFile("a,b\n1,2\n3,4\n5,6", at: file)
        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        nonisolated(unsafe) var callCount = 0
        let store = makeStore(
            reader: reader,
            onChangeBox: onChangeBox,
            chunkedReaderFactory: { _ in
                callCount += 1
                return MockChunkedReader(chunks: ["a,b\n1,2\n", "3,4\n5,6"])
            }
        )
        store.openFile(file)
        #expect(callCount == 1)
        #expect(store.isTruncated == true)

        _ = store.loadMoreLines()
        #expect(store.isTruncated == false)

        onChangeBox.get()?()
        #expect(callCount == 2)
        #expect(store.content == "a,b\n1,2\n")
        #expect(store.isTruncated == true)

        store.close()
    }

    @Test("非行指向ファイルは従来の一括読み込み")
    func nonLineOrientedFileUsesFullLoad() {
        let file = URL(fileURLWithPath: "/files/doc.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello\n\nWorld", at: file)
        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.content == "# Hello\n\nWorld")
        #expect(store.isTruncated == false)

        store.close()
    }

    @Test("非行指向テキストが 10MB を超えると fileTooLarge")
    func nonLineOrientedTextOverLimitIsRejected() {
        let file = URL(fileURLWithPath: "/files/huge.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Big", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)
        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.rejectReason == .fileTooLarge)

        store.close()
    }
}

private struct StopCountingWatcher: FileWatching {
    let onStop: @Sendable () -> Void
    func stop() {
        onStop()
    }
}

/// ファイル削除確定(グレース期間付き onFileGone)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
/// グレース期間の待機は TestClock を注入して仮想時刻で厳密に進めるため、実時間依存はなく
/// 通常どおり並列実行できる。
@Suite
@MainActor
struct ViewerStoreFileGoneTests {
    @Test
    func openNonexistentFileFiresOnFileGoneAfterGrace() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/missing.mmd")
        let store = makeStore(reader: InMemoryFileReader(), clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)
        await clock.waitForPendingSleepers(atLeast: 1)
        // グレース期間中は発火しない
        #expect(firedCount == 0)

        // 0.999 秒では未到達で発火しない
        clock.advance(by: .milliseconds(999))
        await yieldMainActor()
        #expect(firedCount == 0)

        // グレース期間 1 秒到達で発火する
        clock.advance(by: .milliseconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func openNonexistentFileDoesNotFireOnContentReloaded() {
        let file = URL(fileURLWithPath: "/files/missing.mmd")
        let store = makeStore(reader: InMemoryFileReader())

        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        store.openFile(file)

        // ファイルが存在しない場合は scheduleFileGone() へ抜けるため、
        // 内容は確定せず onContentReloaded は発火しない。
        #expect(firedCount == 0)

        store.close()
    }

    @Test
    func watcherCallbackCancelsFileGoneOnRecreation() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)
        #expect(firedCount == 0)

        // ファイル削除 → コールバック発火でグレース期間開始
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await clock.waitForPendingSleepers(atLeast: 1)

        // グレース期間内に再作成 → グレースタスクがキャンセルされ待機が消える
        reader.setFile("graph TD; C-->D", at: file)
        onChangeBox.get()?()
        #expect(clock.pendingSleepCount == 0)

        // 10 秒進めても発火しない
        clock.advance(by: .seconds(10))
        await yieldMainActor()
        #expect(firedCount == 0)
        #expect(store.content == "graph TD; C-->D")

        store.close()
    }

    @Test
    func watcherCallbackFiresOnFileGoneAfterGracePeriod() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)

        // ファイル削除 → コールバック発火でグレース期間開始
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await clock.waitForPendingSleepers(atLeast: 1)

        // 0.999 秒では未到達で発火しない
        clock.advance(by: .milliseconds(999))
        await yieldMainActor()
        #expect(firedCount == 0)

        // グレース期間 1 秒到達で発火する
        clock.advance(by: .milliseconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func fileGoneDetectionSurvivesRecreateAndRedelete() async {
        let clock = TestClock()
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox, clock: clock)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)

        // 削除 → グレース期間開始
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await clock.waitForPendingSleepers(atLeast: 1)

        // 監視イベントなしで再作成(発火直前の存在再確認だけで救済されるケース)。
        // グレース期間を過ぎてもファイルが存在するため発火せず、タスクは完了する。
        reader.setFile("graph TD; C-->D", at: file)
        clock.advance(by: .seconds(1))
        await yieldMainActor()
        #expect(firedCount == 0)
        // 完了済み(stale)タスクは待機を残していない
        #expect(clock.pendingSleepCount == 0)

        // 再削除 → 完了済みの stale タスクが検知を塞いでいないこと
        reader.setFile(nil, at: file)
        onChangeBox.get()?()
        await clock.waitForPendingSleepers(atLeast: 1)
        clock.advance(by: .seconds(1))
        await waitUntilYielding { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }
}
