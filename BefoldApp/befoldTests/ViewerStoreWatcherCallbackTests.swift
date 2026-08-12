@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ファイル監視の変更・リネームコールバックによる再読込と、onContentReloaded の発火回数を検証する。
@Suite
@MainActor
struct ViewerStoreWatcherCallbackTests {
    @Test
    func watcherCallbackReloadsContent() async {
        let file = URL(fileURLWithPath: "/files/test.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("graph TD; A-->B", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        #expect(store.contentState.content == "graph TD; A-->B")

        // ファイル内容を書き換えてから監視コールバックを発火する
        reader.setFile("graph TD; X-->Y", at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.contentState.content == "graph TD; X-->Y")

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
        #expect(store.contentState.filePath == oldFile)

        // 別名 + 別内容 + 別タイプへ移動したことを通知する
        let newFile = URL(fileURLWithPath: "/files/renamed.md")
        reader.setFile("# Renamed", at: newFile)

        nonisolated(unsafe) var renamedTo: URL?
        store.onFileRenamed = { _, newURL in renamedTo = newURL }
        onRenameBox.get()?(newFile)
        await awaitLoad(store)

        #expect(store.contentState.filePath == newFile)
        #expect(store.contentState.fileType == .markdown)
        #expect(store.contentState.content == "# Renamed")
        #expect(renamedTo == newFile)

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
        let file = URL(fileURLWithPath: "/files/huge.html")
        let reader = InMemoryFileReader()
        reader.setFile("<h1>Hello</h1>", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        await openAndLoad(store, file)
        #expect(store.contentState.isRejected)
        #expect(firedCount == 1)

        // サイズが上限内に戻る → isRejected が false に変わる再読込でも発火する。
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(!store.contentState.isRejected)
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
}
