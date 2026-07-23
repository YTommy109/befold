@testable import befold
import BefoldTestSupport
import Foundation
import SwiftUI
import Testing

/// サイドバーで矢印キー選択してもプレビュー内容が変わらない問題(#142)の回帰テスト。
/// `selectNext()` / `selectPrevious()` が選択インデックスを進める/戻すだけでなく、
/// 選択先がファイルなら `onSelect` を呼んで表示を追従させることを検証する。
@Suite
@MainActor
struct FileListViewTests {
    private func makeView(
        entries: [FileListEntry],
        selection: FileListEntry.ID?,
        onSelect: @escaping (URL) -> Void
    ) -> FileListView {
        let model = FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/FileListViewTests"),
            entries: entries,
            selection: selection
        )
        return FileListView(
            model: model,
            onSelect: onSelect,
            onNavigate: { _ in },
            onSortOrderChanged: { _ in },
            onOpenInNewWindow: { _ in }
        )
    }

    /// selectNext / selectPrevious / downArrow ルーティングの各テストで共通して使う
    /// 標準フィクスチャ(`[file0, folder, file1, file2]`)。
    private struct StandardEntries {
        let file0 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file0.mmd"), kind: .file)
        let folder = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/folder"), kind: .folder)
        let file1 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file1.mmd"), kind: .file)
        let file2 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file2.mmd"), kind: .file)

        var all: [FileListEntry] {
            [file0, folder, file1, file2]
        }
    }

    @Test("selectNext で次のファイルへ選択が進んだとき onSelect が呼ばれる(#142 の回帰テスト)")
    func selectNextMovesToNextFileAndCallsOnSelect() {
        let fixture = StandardEntries()
        let selected = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id
        ) { url in
            selected.set(url)
        }

        let result = view.selectNext()

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file2.id)
        #expect(selected.get() == fixture.file2.url)
    }

    @Test("selectPrevious で前のファイルへ選択が戻ったとき onSelect が呼ばれる")
    func selectPreviousMovesToPreviousFileAndCallsOnSelect() {
        let fixture = StandardEntries()
        let selected = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file2.id
        ) { url in
            selected.set(url)
        }

        let result = view.selectPrevious()

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file1.id)
        #expect(selected.get() == fixture.file1.url)
    }

    @Test("選択が nil の状態で selectNext を呼ぶと先頭エントリが選択され onSelect が呼ばれる")
    func selectNextFromNilSelectionSelectsFirstEntryAndCallsOnSelect() {
        let firstFile = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/first.mmd"), kind: .file)
        let secondFile = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/second.mmd"), kind: .file)
        let selected = LockedBox<URL?>(nil)

        let view = makeView(
            entries: [firstFile, secondFile],
            selection: nil
        ) { url in
            selected.set(url)
        }

        let result = view.selectNext()

        #expect(result == .handled)
        #expect(view.model.selection == firstFile.id)
        #expect(selected.get() == firstFile.url)
    }

    @Test("downArrow キーで次のファイルへ選択が進み onSelect が呼ばれる(#142 のキー操作経路全体の回帰テスト)")
    func downArrowRoutesToSelectNextAndCallsOnSelect() {
        let fixture = StandardEntries()
        let selected = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id
        ) { url in
            selected.set(url)
        }

        let result = view.handleKey(.downArrow)

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file2.id)
        #expect(selected.get() == fixture.file2.url)
    }

    @Test("選択先エントリがフォルダの場合は onSelect が呼ばれない")
    func selectNextIntoFolderDoesNotCallOnSelect() {
        let file0 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file0.mmd"), kind: .file)
        let folder = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/folder"), kind: .folder)
        let selected = LockedBox<URL?>(nil)

        let view = makeView(
            entries: [file0, folder],
            selection: file0.id
        ) { url in
            selected.set(url)
        }

        let result = view.selectNext()

        #expect(result == .handled)
        #expect(view.model.selection == folder.id)
        #expect(selected.get() == nil)
    }
}
