@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import SwiftUI
import Testing

/// サイドバーで矢印キー選択してもプレビュー内容が変わらない問題の回帰テスト。
/// `selectNext()` / `selectPrevious()` が選択インデックスを進める/戻すだけでなく、
/// 選択先がファイルなら `onSelect` を呼んで表示を追従させることを検証する。
@Suite
@MainActor
struct FileListViewTests {
    private func makeView(
        entries: [FileListEntry],
        selection: FileListEntry.ID?,
        onNavigate: @escaping (URL) -> Void = { _ in },
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
            onNavigate: onNavigate,
            onSortOrderChanged: { _ in },
            onOpenInNewWindow: { _ in }
        )
    }

    @Test("relativePathForCopy は baseDirectory(git ルート)を基準に相対パスを返す")
    func relativePathForCopyUsesGitRootBaseDirectory() {
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })
        view.model.rootDirectory = URL(fileURLWithPath: "/tmp/FileListViewTests")
        view.model.baseDirectory = BaseDirectoryDescriptor(
            gitRoot: URL(fileURLWithPath: "/tmp/repo"),
            workspaceRoot: view.model.rootDirectory
        )

        let path = view.relativePathForCopy(URL(fileURLWithPath: "/tmp/repo/src/a.swift"))

        #expect(path == "src/a.swift")
    }

    @Test("relativePathForCopy は baseDirectory 未解決なら rootDirectory を基準にする")
    func relativePathForCopyFallsBackToRootDirectoryWhenBaseDirectoryUnresolved() {
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })
        view.model.rootDirectory = URL(fileURLWithPath: "/tmp/FileListViewTests")
        view.model.baseDirectory = nil

        let path = view.relativePathForCopy(URL(fileURLWithPath: "/tmp/FileListViewTests/sub/a.swift"))

        #expect(path == "sub/a.swift")
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

    @Test("selectNext で次のファイルへ選択が進んだとき onSelect が呼ばれる(回帰テスト)")
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

    @Test("downArrow キーで次のファイルへ選択が進み onSelect が呼ばれる(キー操作経路全体の回帰テスト)")
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

    // MARK: - 修飾キー付きのキー操作(TASK-311)

    /// 親エントリ付きのフィクスチャ。`navigateToParent` は `.parentNavigation` の
    /// 有無で境界を扱うため、あり/なしの両方を作り分けられるようにする。
    private struct EntriesWithParent {
        let parent = FileListEntry(url: URL(fileURLWithPath: "/tmp"), kind: .parentNavigation)
        let file0 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file0.mmd"), kind: .file)
        let file1 = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/file1.mmd"), kind: .file)

        var all: [FileListEntry] {
            [parent, file0, file1]
        }
    }

    @Test("Cmd+↑ は選択移動ではなく上位フォルダーへ移動する(Finder 準拠)")
    func commandUpArrowNavigatesToParent() {
        let fixture = EntriesWithParent()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow, modifiers: .command)

        #expect(result == .handled)
        #expect(navigated.get() == fixture.parent.url)
        // 選択は動かない(selectPrevious へ落ちていないことの確認)。
        #expect(view.model.selection == fixture.file1.id)
    }

    @Test("修飾キーなしの ↑ は従来どおり選択を 1 つ上へ移動する")
    func plainUpArrowStillSelectsPrevious() {
        let fixture = EntriesWithParent()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow)

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file0.id)
        #expect(navigated.get() == nil)
    }

    @Test("Cmd+← は従来どおり上位フォルダーへ移動する")
    func commandLeftArrowStillNavigatesToParent() {
        let fixture = EntriesWithParent()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.leftArrow, modifiers: .command)

        #expect(result == .handled)
        #expect(navigated.get() == fixture.parent.url)
    }

    @Test("親エントリが無ければ Cmd+↑ は何もしない(ホームディレクトリ境界)")
    func commandUpArrowIsIgnoredWithoutParentEntry() {
        let fixture = StandardEntries()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow, modifiers: .command)

        #expect(result == .ignored)
        #expect(navigated.get() == nil)
        #expect(view.model.selection == fixture.file1.id)
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
