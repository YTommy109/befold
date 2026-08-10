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

    /// ルート一覧は失敗を空へ畳む(TASK-410)。畳んでいることを明示的に固定しておかないと、
    /// 後から Optional 化したときに `appendingOpenFile` の不変条件が黙って壊れる。
    @Test("ルート一覧は列挙失敗でも空の配列を返す")
    func listEntriesFoldsFailureIntoEmptyList() {
        let missing = URL(fileURLWithPath: "/nonexistent-befold-dir-\(UUID().uuidString)")

        let entries = DirectoryLister.listEntries(
            in: missing, sortOrder: .foldersFirst, showHiddenFiles: false, home: missing
        )

        #expect(entries.isEmpty)
    }
}
