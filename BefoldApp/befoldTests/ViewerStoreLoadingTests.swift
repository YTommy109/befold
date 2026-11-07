@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// isLoading(読み込み中インジケータ用状態)まわりのテスト。
/// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
@Suite
@MainActor
struct ViewerStoreLoadingTests {
    @Test("明示的な再読み込みは同じ内容でも再描画し、監視の再読み込みは省略する", arguments: ["md", "html", "csv", "swift", "svg"])
    func explicitReloadPublishesUnchangedContent(fileExtension: String) async {
        let file = URL(fileURLWithPath: "/files/reload.\(fileExtension)")
        let reader = InMemoryFileReader()
        reader.setFile("reload fixture", at: file)
        let store = makeStore(reader: reader)
        defer { store.close() }
        store.openFile(file)
        await awaitLoad(store)
        let initialRevision = store.contentState.contentRevision

        store.loadContent()
        await awaitLoad(store)
        #expect(store.contentState.contentRevision == initialRevision)

        store.loadContent(forceRefresh: true)
        await awaitLoad(store)
        #expect(store.contentState.contentRevision == initialRevision + 1)
        #expect(store.contentState.content == "reload fixture")

        reader.setFile("updated fixture", at: file)
        store.loadContent(forceRefresh: true)
        await awaitLoad(store)
        #expect(store.contentState.content == "updated fixture")
        #expect(store.contentState.contentRevision == initialRevision + 2)
    }

    @Test("openFile 直後は isLoading = true、読込完了後は false になる")
    func isLoadingReflectsInFlightLoad() async {
        let file = URL(fileURLWithPath: "/files/loading.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)
        #expect(store.contentState.isLoading)

        await awaitLoad(store)
        #expect(!store.contentState.isLoading)

        store.close()
    }

    @Test("close() は実行中の isLoading をリセットする")
    func closeResetsIsLoading() {
        let file = URL(fileURLWithPath: "/files/loading2.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)

        let store = makeStore(reader: reader)
        store.openFile(file)
        #expect(store.contentState.isLoading)

        store.close()
        #expect(!store.contentState.isLoading)
    }
}

// 行指向ファイルのチャンク読み込み(段階読み込み)まわりのテスト。
// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
