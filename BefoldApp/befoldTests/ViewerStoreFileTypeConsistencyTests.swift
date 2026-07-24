@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// apply() の同一内容スキップ(dataHash 比較)が fileType の変化を見落とさないことを確認する。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
@Suite
@MainActor
struct ViewerStoreFileTypeConsistencyTests {
    /// 内容が完全に同一(バイト列一致)のままリネームされた場合、apply() の同一内容スキップに
    /// 入っても fileType は必ず新しい判定へ更新されるべき。
    @Test
    func watcherRenameWithIdenticalContentUpdatesFileType() async {
        let oldFile = URL(fileURLWithPath: "/files/notes.md")
        let reader = InMemoryFileReader()
        reader.setFile("same content", at: oldFile)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(reader: reader, onRenameBox: onRenameBox)
        await openAndLoad(store, oldFile)
        #expect(store.fileType == .markdown)

        // 拡張子だけ変わり、バイト列は完全に同一(dataHash が一致する)。
        let newFile = URL(fileURLWithPath: "/files/notes.mmd")
        reader.setFile("same content", at: newFile)

        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        onRenameBox.get()?(newFile)
        await awaitLoad(store)

        #expect(store.fileType == .mmd)
        #expect(store.filePath == newFile)
        #expect(firedCount == 1)

        store.close()
    }

    /// openFile で同じ store インスタンスを使い回して切り替える場合も、内容が偶然同一の
    /// 別ファイル(別タイプ)へ切り替えたら fileType が更新されるべき。
    @Test
    func openFileWithIdenticalContentAcrossDifferentTypesUpdatesFileType() async {
        let file1 = URL(fileURLWithPath: "/files/first.md")
        let file2 = URL(fileURLWithPath: "/files/second.mmd")
        let reader = InMemoryFileReader()
        reader.setFile("same content", at: file1)
        reader.setFile("same content", at: file2)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file1)
        #expect(store.fileType == .markdown)

        await openAndLoad(store, file2)

        #expect(store.fileType == .mmd)
        #expect(store.filePath == file2)

        store.close()
    }

    /// ファイル切替中(読み込み完了前)は filePath だけが先行して新ファイルを指す
    /// 中間状態が観測されてはいけない(GitHub issue #252: HTML 表示直後に他ファイルへ
    /// 切り替えると空白表示になる不具合の再発防止)。切替直後は旧ファイルの
    /// filePath/fileType/content が組のまま保たれ、読み込み完了後に新ファイルの組へ
    /// 一括で切り替わることを確認する。
    @Test
    func filePathStaysPairedWithFileTypeAndContentDuringSwitch() async {
        let htmlFile = URL(fileURLWithPath: "/files/page.html")
        let cssFile = URL(fileURLWithPath: "/files/style.css")
        let reader = InMemoryFileReader()
        reader.setFile("<html></html>", at: htmlFile)
        reader.setFile("body { color: red; }", at: cssFile)

        let store = makeStore(reader: reader)
        await openAndLoad(store, htmlFile)
        #expect(store.fileType == .html)
        #expect(store.filePath == htmlFile)

        store.openFile(cssFile)
        // 読み込み完了前は、旧ファイルの filePath/fileType/content が組のまま残るべき
        // (filePath だけ新ファイルを指し、fileType/content が旧ファイルのままという
        // 中間状態は許されない)。
        #expect(store.filePath == htmlFile)
        #expect(store.fileType == .html)
        #expect(store.content == "<html></html>")

        await awaitLoad(store)
        #expect(store.filePath == cssFile)
        #expect(store.fileType == .code(language: "css"))
        #expect(store.content == "body { color: red; }")

        store.close()
    }

    /// 内容・タイプとも完全に同一の再読込では、従来どおり再描画をスキップする
    @Test
    func watcherCallbackWithIdenticalContentAndTypeSkipsReload() async {
        let file = URL(fileURLWithPath: "/files/notes.md")
        let reader = InMemoryFileReader()
        reader.setFile("same content", at: file)

        let onChangeBox = LockedBox<(@MainActor @Sendable () -> Void)?>(nil)
        let store = makeStore(reader: reader, onChangeBox: onChangeBox)
        await openAndLoad(store, file)
        let revisionAfterFirstLoad = store.contentRevision

        nonisolated(unsafe) var firedCount = 0
        store.onContentReloaded = { firedCount += 1 }
        // 内容もタイプも変わらない再読込(touch・アトミック保存等の再通知を模す)。
        onChangeBox.get()?()
        await awaitLoad(store)

        #expect(store.contentRevision == revisionAfterFirstLoad)
        #expect(firedCount == 0)

        store.close()
    }
}
