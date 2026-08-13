@testable import befold
import Foundation
import Testing

/// 一覧の引き当て述語(TASK-442.2 で SidebarNavigator から移設)を検証する。
@Suite
@MainActor
struct FileListModelLookupTests {
    private let directory = URL(fileURLWithPath: "/tmp/befold-list-lookup")

    private func makeModel(entries: [FileListEntry]) -> FileListModel {
        let model = FileListModel(currentDirectory: directory, entries: [], selection: nil)
        model.setEntries(entries, for: directory, didFailEnumeration: false)
        return model
    }

    @Test("フォルダーの正規化キーが一致する行の URL を返す")
    func findsFolderByPathKey() {
        let folder = directory.appendingPathComponent("sub")
        let model = makeModel(entries: [FileListEntry(url: folder, kind: .folder)])

        #expect(model.folderEntryURL(forKey: folder.normalizedPathKey) == folder)
    }

    @Test("同じキーの行がファイルならフォルダーとしては引き当てない")
    func ignoresNonFolderEntry() {
        let file = directory.appendingPathComponent("note.md")
        let model = makeModel(entries: [FileListEntry(url: file, kind: .file)])

        #expect(model.folderEntryURL(forKey: file.normalizedPathKey) == nil)
        #expect(model.folderEntryURL(forKey: "/nowhere") == nil)
    }

    /// `pathKey` はシンボリックリンクを解決した実体パスなので、同じキーの行が複数並ぶ
    /// ことがある(祖先を指すリンクがあるときの `.parentNavigation` 行、実体と並ぶリンク)。
    /// 索引経由(先勝ち・kind を見ない)に戻すと、このテストが落ちる(TASK-450)。
    @Test("同じキーの非フォルダー行が先にあってもフォルダー行を引き当てる")
    func findsFolderBehindSameKeyNonFolderRow() {
        let folder = directory.appendingPathComponent("sub")
        let model = makeModel(entries: [
            FileListEntry(url: folder, kind: .parentNavigation),
            FileListEntry(url: folder, kind: .folder),
        ])

        #expect(model.folderEntryURL(forKey: folder.normalizedPathKey) == folder)
    }

    @Test("一覧にある行は一覧側の URL を返す")
    func returnsEntryURLWhenPresent() {
        let file = directory.appendingPathComponent("note.md")
        let model = makeModel(entries: [FileListEntry(url: file, kind: .file)])

        #expect(model.matchingEntryURL(for: file) == file)
    }

    /// tree 表示では展開したサブフォルダーの子行も同じ一覧に並ぶ。「親ディレクトリ ==
    /// currentDirectory」だけで判定すると子ファイルを選ぶたびにフォルダー移動が
    /// 誤発火する(TASK-465)。行の存在も見ていることを固定する。
    @Test("展開した子フォルダーの行は表示中フォルダーから到達できる扱いにする")
    func treatsExpandedChildRowAsReachable() {
        let child = directory.appendingPathComponent("sub/note.md")
        let model = makeModel(entries: [FileListEntry(url: child, kind: .file)])

        #expect(model.isReachableInCurrentListing(child))
    }

    /// 一覧がまだ届いていない起動直後は行が 1 つも無い。表示中フォルダー直下のファイルは
    /// 「行が無いだけ」なので、フォルダーを動かす必要はない。
    @Test("表示中フォルダー直下は行が無くても到達できる扱いにする")
    func treatsCurrentDirectoryChildAsReachableWithoutRows() {
        let model = makeModel(entries: [])

        #expect(model.isReachableInCurrentListing(directory.appendingPathComponent("note.md")))
    }

    @Test("一覧にも表示中フォルダー直下にも無ければ到達できない")
    func treatsUnlistedFileInOtherDirectoryAsUnreachable() {
        let model = makeModel(entries: [])
        let elsewhere = URL(fileURLWithPath: "/tmp/befold-elsewhere/note.md")

        #expect(!model.isReachableInCurrentListing(elsewhere))
    }

    @Test("一覧に無ければ渡した URL をそのまま返す")
    func returnsGivenURLWhenAbsent() {
        let model = makeModel(entries: [])
        let missing = directory.appendingPathComponent("missing.md")

        #expect(model.matchingEntryURL(for: missing) == missing)
    }
}
