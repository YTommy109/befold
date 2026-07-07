@testable import befold
import Foundation
import Testing

private struct MockFileWatcher: FileWatching {
    func stop() {}
}

@Suite
@MainActor
struct ViewerStoreTests {
    /// UserDefaults.standard を読むと過去の実行で永続化された値に影響されるため、
    /// テストごとに使い捨てのスイートを注入して密閉性を保つ。
    private func makeStore(reader: InMemoryFileReader) -> ViewerStore {
        let suiteName = "ViewerStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: reader,
            defaults: defaults
        )
    }

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
        #expect(!store.isDeleted)
        #expect(store.filePath == file)

        store.close()
    }

    @Test
    func openNonexistentFileMarksDeleted() {
        let file = URL(fileURLWithPath: "/files/missing.mmd")

        let store = makeStore(reader: InMemoryFileReader())
        store.openFile(file)

        #expect(store.isDeleted)
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
        #expect(!store.isDeleted)

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

        #expect(store.isUnsupported)
        #expect(store.content == "")
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func openTextFileWithUnknownExtensionIsNotUnsupported() {
        let file = URL(fileURLWithPath: "/files/notes.txt")
        let reader = InMemoryFileReader()
        reader.setFile("hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(store.content == "hello")
        #expect(store.fileType == .code(language: "plaintext"))

        store.close()
    }

    @Test
    func openOversizedFileMarksUnsupportedWithoutLoading() {
        let file = URL(fileURLWithPath: "/files/huge.csv")
        let reader = InMemoryFileReader()
        reader.setFile("col1,col2\n1,2", at: file)
        reader.setSize(ViewerStore.maxFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.isUnsupported)
        #expect(store.content == "")
        #expect(!store.isDeleted)

        store.close()
    }

    @Test
    func openFileAtSizeLimitLoadsContent() {
        let file = URL(fileURLWithPath: "/files/ok.csv")
        let reader = InMemoryFileReader()
        reader.setFile("col1,col2\n1,2", at: file)
        reader.setSize(ViewerStore.maxFileSizeBytes, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(store.content == "col1,col2\n1,2")

        store.close()
    }

    @Test
    func switchingFromOversizedToNormalResetsUnsupported() {
        let hugeFile = URL(fileURLWithPath: "/files/huge.log")
        let normalFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile("x", at: hugeFile)
        reader.setSize(ViewerStore.maxFileSizeBytes + 1, at: hugeFile)
        reader.setFile("# Hello", at: normalFile)

        let store = makeStore(reader: reader)
        store.openFile(hugeFile)
        #expect(store.isUnsupported)

        store.openFile(normalFile)
        #expect(!store.isUnsupported)
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
        #expect(store.isUnsupported)

        store.openFile(textFile)
        #expect(!store.isUnsupported)
        #expect(store.content == "# Hello")

        store.close()
    }

    @Test
    func watcherCallbackReloadsContent() {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        // factory に渡された onChange を保持する
        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)
        store.openFile(file)
        #expect(store.content == "graph TD; A-->B")

        // ファイル内容を書き換えてから監視コールバックを発火する
        reader.setFile("graph TD; X-->Y", at: file)
        onChange?()

        #expect(store.content == "graph TD; X-->Y")

        store.close()
    }

    @Test
    func watcherCallbackTracksDeletionAndRecreation() {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)
        store.openFile(file)
        #expect(!store.isDeleted)

        // ファイル削除 → コールバック発火で isDeleted が立つ
        reader.setFile(nil, at: file)
        onChange?()
        #expect(store.isDeleted)

        // 再作成 → コールバック発火で isDeleted が戻り、新しい内容が読める
        reader.setFile("graph TD; C-->D", at: file)
        onChange?()
        #expect(!store.isDeleted)
        #expect(store.content == "graph TD; C-->D")

        store.close()
    }

    @Test
    func watcherRenameUpdatesPathAndReloadsContent() {
        let oldFile = URL(fileURLWithPath: "/files/old.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: oldFile)

        // factory に渡された onRename を保持する
        nonisolated(unsafe) var onRename: (@MainActor @Sendable (URL) -> Void)?
        let store = ViewerStore(watcherFactory: { _, _, rename in
            onRename = rename
            return MockFileWatcher()
        }, fileReader: reader)
        store.openFile(oldFile)
        #expect(store.filePath == oldFile)

        // 別名 + 別内容 + 別タイプへ移動したことを通知する
        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)

        nonisolated(unsafe) var renamedTo: URL?
        store.onFileRenamed = { renamedTo = $0 }
        onRename?(newFile)

        #expect(store.filePath == newFile)
        #expect(store.fileType == .markdown)
        #expect(store.content == "# Renamed")
        #expect(!store.isDeleted)
        #expect(renamedTo == newFile)

        store.close()
    }

    /// 実際の画像ファイルは isBinary 判定が true になるため、テストでも
    /// setBinary(true) を付けて「バイナリ判定より先に画像として読む」順序を検証する。
    @Test
    func openImageFileLoadsBase64Content() {
        let file = URL(fileURLWithPath: "/files/photo.png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let reader = InMemoryFileReader()
        reader.setDataFile(imageData, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(!store.isDeleted)
        #expect(store.fileType == .image(mimeType: "image/png"))
        #expect(store.content == imageData.base64EncodedString())

        store.close()
    }

    @Test
    func openPdfFileLoadsBase64Content() {
        let file = URL(fileURLWithPath: "/files/doc.pdf")
        let pdfData = Data("%PDF-1.4".utf8)
        let reader = InMemoryFileReader()
        reader.setDataFile(pdfData, at: file)
        reader.setBinary(true, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(!store.isDeleted)
        #expect(store.fileType == .pdf)
        #expect(store.content == pdfData.base64EncodedString())

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

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)
        store.openFile(file)
        #expect(store.content == data1.base64EncodedString())

        reader.setDataFile(data2, at: file)
        onChange?()

        #expect(store.content == data2.base64EncodedString())

        store.close()
    }

    /// 画像・PDF はテキストの 10MB 制限ではなく緩い 50MB 制限が適用される。
    @Test
    func imageOverTextSizeLimitStillLoads() {
        let file = URL(fileURLWithPath: "/files/scan.png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let reader = InMemoryFileReader()
        reader.setDataFile(imageData, at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ViewerStore.maxFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(!store.isUnsupported)
        #expect(store.content == imageData.base64EncodedString())

        store.close()
    }

    @Test
    func imageOverBinarySizeLimitMarksUnsupported() {
        let file = URL(fileURLWithPath: "/files/huge.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89]), at: file)
        reader.setBinary(true, at: file)
        reader.setSize(ViewerStore.maxBinaryFileSizeBytes + 1, at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)

        #expect(store.isUnsupported)
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

        #expect(store.isUnsupported)
        #expect(store.content == "")
        #expect(!store.isDeleted)

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
    func showLineNumbersPersistedToUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
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
        defaults.removePersistentDomain(forName: #function)
    }
}

private struct StopCountingWatcher: FileWatching {
    let onStop: @Sendable () -> Void
    func stop() {
        onStop()
    }
}
