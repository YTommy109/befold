@testable import befold
import BefoldTestSupport
import Foundation
import SwiftUI
import Testing

/// サイドバーの修飾キー付きキー操作(⌘↑ / delete / ⌘←)による上位フォルダーへの移動。
///
/// `FileListViewTests` から分けているのは行数上限(`type_body_length`)のためで、
/// 測っている対象も「一覧内の選択移動」ではなく「ルートを変える移動」で分かれる。
@Suite
@MainActor
struct FileListViewNavigationKeyTests {
    /// スパイの生存を保つ入れ物(`FileListView.delegate` は弱参照)。
    private let delegates = FileListViewDelegateStore()

    private func makeView(
        entries: [FileListEntry],
        selection: FileListEntry.ID?,
        currentDirectory: URL = URL(fileURLWithPath: "/tmp/FileListViewTests"),
        onNavigate: @escaping (URL) -> Void = { _ in },
        onSelect: @escaping (URL) -> Void
    ) -> FileListView {
        let model = FileListModel(
            currentDirectory: currentDirectory,
            entries: entries,
            selection: selection
        )
        return FileListView(
            model: model,
            delegate: delegates.makeSpy(onSelect: onSelect, onNavigate: onNavigate),
            onSortOrderChanged: { _ in },
            onToggleChangedFilesOnly: {},
            onToggleSidebarTreeLayout: {}
        )
    }

    // MARK: - 修飾キー付きのキー操作(TASK-311)

    /// 上位フォルダーへ移動できる状態のフィクスチャ。行き先は一覧ではなく
    /// `SidebarPathMenu` が `currentDirectory` とホームから決めるため、
    /// **カレントディレクトリをホーム配下に置く**のがこのフィクスチャの要点(TASK-475)。
    private struct EntriesUnderHome {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("FileListViewTests")
        var parentURL: URL {
            directory.deletingLastPathComponent()
        }

        var file0: FileListEntry {
            FileListEntry(url: directory.appendingPathComponent("file0.mmd"), kind: .file)
        }

        var file1: FileListEntry {
            FileListEntry(url: directory.appendingPathComponent("file1.mmd"), kind: .file)
        }

        var all: [FileListEntry] {
            [file0, file1]
        }
    }

    @Test("Cmd+↑ は選択移動ではなく上位フォルダーへ移動する(Finder 準拠)")
    func commandUpArrowNavigatesToParent() {
        let fixture = EntriesUnderHome()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            currentDirectory: fixture.directory,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow, modifiers: .command)

        #expect(result == .handled)
        #expect(navigated.get() == fixture.parentURL)
        // 選択は動かない(selectPrevious へ落ちていないことの確認)。
        #expect(view.model.selection == fixture.file1.id)
    }

    @Test("修飾キーなしの ↑ は従来どおり選択を 1 つ上へ移動する")
    func plainUpArrowStillSelectsPrevious() {
        let fixture = EntriesUnderHome()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            currentDirectory: fixture.directory,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow)

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file0.id)
        #expect(navigated.get() == nil)
    }

    /// **⌘← は上位フォルダーへ移動しない（TASK-584 で廃止）。** 本文からサイドバーへ
    /// 戻る操作に充てた。上へ出る手段は ⌘↑ と delete に残っている（Finder も ⌘← を
    /// 上位移動には使わない）。ここが `.handled` に戻ると、その戻る操作が奪われる。
    @Test("Cmd+← はサイドバーでは何もしない（上位移動から外した）")
    func commandLeftArrowNoLongerNavigatesToParent() {
        let fixture = EntriesUnderHome()
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: fixture.all,
            selection: fixture.file1.id,
            currentDirectory: fixture.directory,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.leftArrow, modifiers: .command)

        #expect(result == .ignored)
        #expect(navigated.get() == nil)
    }

    /// カレントディレクトリがホームの外(既定の `/tmp/FileListViewTests`)なら、
    /// 上へ出す先が無いので何も起きない。
    @Test("ホームの外では Cmd+↑ は何もしない(ホームディレクトリ境界)")
    func commandUpArrowIsIgnoredOutsideHome() {
        let outside = URL(fileURLWithPath: "/tmp/FileListViewTests")
        let file = FileListEntry(url: outside.appendingPathComponent("file0.mmd"), kind: .file)
        let navigated = LockedBox<URL?>(nil)

        let view = makeView(
            entries: [file],
            selection: file.id,
            currentDirectory: outside,
            onNavigate: { url in navigated.set(url) },
            onSelect: { _ in }
        )

        let result = view.handleKey(.upArrow, modifiers: .command)

        #expect(result == .ignored)
        #expect(navigated.get() == nil)
        #expect(view.model.selection == file.id)
    }
}
