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

        #expect(store.isUnsupported)
        #expect(store.content == "")

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

        #expect(!store.isUnsupported)
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

/// ファイル削除確定(グレース期間付き onFileGone)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
@Suite
@MainActor
struct ViewerStoreFileGoneTests {
    private func makeStore(reader: InMemoryFileReader) -> ViewerStore {
        let suiteName = "ViewerStoreFileGoneTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ViewerStore(
            watcherFactory: { _, _, _ in MockFileWatcher() },
            fileReader: reader,
            defaults: defaults
        )
    }

    /// firedCount が期待値に達するまで短い間隔でポーリングする。
    /// フルスイート並列実行下では CPU 競合でタイマーが遅延しうるため、
    /// 固定 sleep ではなく条件成立を待つことでフレーキーさを避ける。
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test
    func openNonexistentFileFiresOnFileGoneAfterGrace() async throws {
        let file = URL(fileURLWithPath: "/files/missing.mmd")
        let store = makeStore(reader: InMemoryFileReader())

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)
        // グレース期間中は発火しない
        #expect(firedCount == 0)

        try await waitUntil { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func watcherCallbackCancelsFileGoneOnRecreation() async throws {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)
        #expect(firedCount == 0)

        // ファイル削除 → コールバック発火でグレース期間開始
        reader.setFile(nil, at: file)
        onChange?()

        // グレース期間内に再作成 → onFileGone は発火しない
        reader.setFile("graph TD; C-->D", at: file)
        onChange?()
        // グレース期間(0.3s)を過ぎても発火しないことを確認
        try await Task.sleep(for: .seconds(0.8))
        #expect(firedCount == 0)
        #expect(store.content == "graph TD; C-->D")

        store.close()
    }

    @Test
    func watcherCallbackFiresOnFileGoneAfterGracePeriod() async throws {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)

        // ファイル削除 → コールバック発火
        reader.setFile(nil, at: file)
        onChange?()

        // グレース期間後に onFileGone が発火する
        try await waitUntil { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }

    @Test
    func fileGoneDetectionSurvivesRecreateAndRedelete() async throws {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        nonisolated(unsafe) var onChange: (@MainActor @Sendable () -> Void)?
        let store = ViewerStore(watcherFactory: { _, callback, _ in
            onChange = callback
            return MockFileWatcher()
        }, fileReader: reader)

        nonisolated(unsafe) var firedCount = 0
        store.onFileGone = { firedCount += 1 }
        store.openFile(file)

        // 削除 → グレース期間開始
        reader.setFile(nil, at: file)
        onChange?()
        // 監視イベントなしで再作成(発火直前の存在再確認だけで救済されるケース)。
        // グレースタスクは発火せずに完了する。
        // 待ち時間はフルスイート並列実行下でのタイマー遅延を吸収できるよう
        // グレース期間(0.3s)に余裕を持たせている(FileWatcherIntegrationTests の
        // フレーキー対策と同様の考え方)。
        reader.setFile("graph TD; C-->D", at: file)
        try await Task.sleep(for: .seconds(0.8))
        #expect(firedCount == 0)

        // 再削除 → 完了済みの stale タスクが検知を塞いでいないこと
        reader.setFile(nil, at: file)
        onChange?()
        try await waitUntil { firedCount == 1 }
        #expect(firedCount == 1)

        store.close()
    }
}
