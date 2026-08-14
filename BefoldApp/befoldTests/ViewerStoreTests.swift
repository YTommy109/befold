@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ファイルを開く・別ファイルへ切り替える基本フローと、表示設定の既定値・永続化を検証する。
/// モックとヘルパーは ViewerStoreTestSupport.swift を参照。
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

        #expect(store.contentState.content == content)
        #expect(store.contentState.fileType == expectedType)
        #expect(store.contentState.filePath == file)

        store.close()
    }

    @Test
    func openEmptyFile() async {
        let file = URL(fileURLWithPath: "/files/empty.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("", at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.content == "")

        store.close()
    }

    /// 差分は表示中ファイルに紐づく。取得は非同期なので、切替時に捨てておかないと
    /// 着地までの間、前のファイルの差分が新しいファイルの内容として描画される。
    @Test("別ファイルを開くと前のファイルの差分を捨てる")
    func openFileClearsDiffContent() async {
        let first = URL(fileURLWithPath: "/files/first.swift")
        let second = URL(fileURLWithPath: "/files/second.swift")
        let reader = InMemoryFileReader()
        reader.setFile("let a = 1", at: first)
        reader.setFile("let b = 2", at: second)

        let store = makeStore(reader: reader)
        await openAndLoad(store, first)
        store.diffContent = .diff("@@ -1 +1 @@\n-let a = 0\n+let a = 1\n")

        await openAndLoad(store, second)

        #expect(store.diffContent == .unavailable)

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
        #expect(store.contentState.content == "graph TD; A-->B")
        #expect(store.contentState.fileType == .mmd)

        await openAndLoad(store, file2)

        #expect(store.contentState.content == "# Second")
        #expect(store.contentState.fileType == .markdown)
        #expect(store.contentState.filePath == file2)

        store.close()
    }

    @Test
    func openFileStopsPreviousWatcher() {
        let file1 = URL(fileURLWithPath: "/files/a.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("A", at: file1)
        reader.setFile("B", at: URL(fileURLWithPath: "/files/b.mmd"))

        nonisolated(unsafe) var stopCount = 0
        let store = ViewerStore(watcherFactory: { _, _, _, _ in
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
            watcherFactory: { _, _, _, _ in MockFileWatcher() },
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

        #expect(!store.contentState.isTruncated)
        #expect(!store.contentState.isRejected)

        store.close()
    }
}
