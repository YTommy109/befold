@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ディレクトリ列挙に失敗したときの DirectoryLister の振る舞い(TASK-404)。
/// DirectoryListerTests から分けているのは、swiftlint の file_length /
/// type_body_length を超えないようにするため
/// (DirectoryListerAppendingOpenFileTests と同じ理由)。
struct DirectoryListerEnumerationFailureTests {
    /// 「読めなかった」と「空だった」を同じ `[]` にすると、ツリー展開が権限の無い
    /// フォルダを空フォルダとして確定表示する。childEntries はここを nil で分ける。
    @Test("childEntries は列挙失敗で nil を返し、空ディレクトリの [] と区別できる")
    func childEntriesDistinguishesFailureFromEmptyDirectory() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-befold-dir-\(UUID().uuidString)")
        #expect(
            DirectoryLister.childEntries(
                in: missing, sortOrder: .foldersFirst, showHiddenFiles: false
            ) == nil
        )

        let empty = try TempDir()
        #expect(
            DirectoryLister.childEntries(
                in: empty.url, sortOrder: .foldersFirst, showHiddenFiles: false
            ) == []
        )
    }

    /// ルート一覧は失敗しても行の配列を返す(親移動行・開いている文書の行を出すため)。
    /// 失敗した事実は畳まず `didFailEnumeration` で運ぶ。ここを空配列だけで表すと、
    /// 空状態の文言が「対応ファイルがありません」と言い切る(TASK-410)。
    @Test("ルート一覧は列挙失敗を didFailEnumeration で伝え、空フォルダと区別する")
    func listEntriesReportsEnumerationFailure() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-befold-dir-\(UUID().uuidString)")

        let failed = DirectoryLister.listing(
            in: missing, sortOrder: .foldersFirst, showHiddenFiles: false
        )

        #expect(failed.didFailEnumeration)
        #expect(failed.rows().isEmpty)

        let empty = try TempDir()
        let succeeded = DirectoryLister.listing(
            in: empty.url, sortOrder: .foldersFirst, showHiddenFiles: false
        )

        #expect(!succeeded.didFailEnumeration)
        #expect(succeeded.rows().isEmpty)
    }

    /// 「開いている文書は必ず一覧に含める」は列挙の成否に関わらず保つ不変条件。
    /// 失敗を Optional で表して行ごと落とすと、読めないフォルダーを開いた瞬間に
    /// いま見ている文書までサイドバーから消える。
    @Test("列挙に失敗しても、開いている文書の行は一覧へ足せる")
    func failedListingStillAcceptsOpenFile() {
        let missing = URL(fileURLWithPath: "/nonexistent-befold-dir-\(UUID().uuidString)")
        let openFile = missing.appendingPathComponent("open.md")

        let listing = DirectoryLister.listing(
            in: missing, sortOrder: .foldersFirst, showHiddenFiles: false
        )
        let withOpenFile = listing.appendingOpenFile(openFile, in: missing)

        #expect(withOpenFile.rows().map(\.url) == [openFile])
        #expect(withOpenFile.didFailEnumeration)
    }
}
