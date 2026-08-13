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
    /// スパイの生存を保つ入れ物(`FileListView.delegate` は弱参照)。
    private let delegates = FileListViewDelegateStore()

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
            delegate: delegates.makeSpy(onSelect: onSelect, onNavigate: onNavigate),
            onSortOrderChanged: { _ in }
        )
    }

    @Test("サイドバーの「別の場所で開く」項目は新しいタブと新しいウィンドウの両方を持つ")
    func openElsewhereEntriesCoverTabAndWindow() {
        #expect(SidebarContextMenu.openElsewhereEntries.map(\.disposition) == [.newTab, .newWindow])
        #expect(
            SidebarContextMenu.openElsewhereEntries.map(\.titleKey)
                == ["sidebar.context.openInNewTab", "sidebar.context.openInNewWindow"]
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

        let path = view.model.relativePathForCopy(URL(fileURLWithPath: "/tmp/repo/src/a.swift"))

        #expect(path == "src/a.swift")
    }

    @Test("relativePathForCopy は baseDirectory 未解決なら rootDirectory を基準にする")
    func relativePathForCopyFallsBackToRootDirectoryWhenBaseDirectoryUnresolved() {
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })
        view.model.rootDirectory = URL(fileURLWithPath: "/tmp/FileListViewTests")
        view.model.baseDirectory = nil

        let path = view.model.relativePathForCopy(URL(fileURLWithPath: "/tmp/FileListViewTests/sub/a.swift"))

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

        let result = view.selectNext(in: view.model.listSnapshot)

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

        let result = view.selectPrevious(in: view.model.listSnapshot)

        #expect(result == .handled)
        #expect(view.model.selection == fixture.file1.id)
        #expect(selected.get() == fixture.file1.url)
    }

    @Test("フォルダーを降りた直後のハイライトから、そのまま矢印キー操作を続けられる")
    func keyboardNavigationStartsFromTheDescendHighlight() {
        // navigateToFolder が先頭行をハイライトした状態(選択はあるがプレビューは一覧)。
        // ここから ↓ を押した利用者は 2 行目へ進めなければならない(TASK-310 AC#3)。
        let fixture = StandardEntries()
        let selected = LockedBox<URL?>(nil)
        let view = makeView(entries: fixture.all, selection: nil) { url in selected.set(url) }
        view.model.selection = view.model.firstSelectableEntryURL
        #expect(view.model.selection == fixture.file0.id)

        let result = view.selectNext(in: view.model.listSnapshot)

        #expect(result == .handled)
        #expect(view.model.selection == fixture.folder.id)
        // 移った先はフォルダーなので開かない。提示対象はそのフォルダーの一覧へ移る。
        #expect(selected.get() == nil)
        #expect(view.model.previewTarget == .folder(fixture.folder.url))
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

        let result = view.selectNext(in: view.model.listSnapshot)

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

        let result = view.selectNext(in: view.model.listSnapshot)

        #expect(result == .handled)
        #expect(view.model.selection == folder.id)
        #expect(selected.get() == nil)
    }

    // MARK: - 開閉三角のクリック（TASK-472）

    /// 三角の中心あたりの座標。行の左端(パディングを含む)から測る。
    private func disclosureCenterX(depth: Int) -> CGFloat {
        SidebarRowIndent.rowHorizontalPadding
            + SidebarRowIndent.leadingInset(forDepth: depth)
            + SidebarRowIndent.disclosureWidth / 2
    }

    @Test("三角の上のクリックは開閉のトグルになる")
    func clickOnDisclosureTogglesExpansion() {
        let base = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/dir"), kind: .folder)
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })

        let collapsed = base.disclosing(.collapsed)
        #expect(view.disclosureAction(for: collapsed, atX: disclosureCenterX(depth: 0)) == .expand)

        let expanded = base.disclosing(.expanded)
        #expect(view.disclosureAction(for: expanded, atX: disclosureCenterX(depth: 0)) == .collapse)
    }

    /// 三角より右(行の名前の側)は行本体のクリックのまま。ここが nil でないと、
    /// フォルダ行をどこで押しても開閉してしまい選択できなくなる。
    @Test("三角より右のクリックは行本体のクリックのまま")
    func clickOutsideDisclosureIsRowClick() {
        let entry = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/dir"), kind: .folder)
            .disclosing(.collapsed)
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })

        #expect(view.disclosureAction(for: entry, atX: disclosureCenterX(depth: 0) + 40) == nil)
    }

    /// ドリルダウン表示とプレビュー内のフォルダー一覧には三角が無く、同じ位置は
    /// 行本体の一部でしかない。座標だけで決めると、ここで誤って開閉が走る。
    @Test("三角の無い行では、三角の位置をクリックしても開閉しない")
    func clickAtDisclosurePositionDoesNothingWithoutDisclosure() {
        let folder = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/dir"), kind: .folder)
        let file = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/a.mmd"), kind: .file)
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })

        #expect(view.disclosureAction(for: folder, atX: disclosureCenterX(depth: 0)) == nil)
        #expect(view.disclosureAction(for: file, atX: disclosureCenterX(depth: 0)) == nil)
    }

    /// 深い行の三角はインデントぶん右にある。行の depth を見ずに固定位置で
    /// 判定していると、深い行では名前の上を押して開閉が走る。
    @Test("深い行では三角の位置が depth に追随する")
    func disclosureHitAreaFollowsDepth() {
        let entry = FileListEntry(url: URL(fileURLWithPath: "/tmp/FileListViewTests/dir"), kind: .folder)
            .disclosing(.collapsed)
            .indented(to: 2)
        let view = makeView(entries: [], selection: nil, onSelect: { _ in })

        #expect(view.disclosureAction(for: entry, atX: disclosureCenterX(depth: 2)) == .expand)
        #expect(view.disclosureAction(for: entry, atX: disclosureCenterX(depth: 0)) == nil)
    }
}
