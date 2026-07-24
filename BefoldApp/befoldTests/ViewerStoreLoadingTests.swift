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
    @Test("openFile 直後は isLoading = true、読込完了後は false になる")
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

// 行指向ファイルのチャンク読み込み(段階読み込み)まわりのテスト。
// ViewerStoreTests から分離し、型の行数を SwiftLint の type_body_length 内に収める。
