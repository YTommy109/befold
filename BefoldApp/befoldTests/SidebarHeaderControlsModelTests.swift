@testable import befold
import BefoldKit
import Testing

/// サイドバーヘッダーの操作行の構成（左右の群・並び・アクセント）を固定する。
/// SwiftUI ビューは自動テスト対象外のため、判定はこの値型に閉じ込めて検証する
/// (TASK-473、設計は docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md)。
@Suite
struct SidebarHeaderControlsModelTests {
    private func makeModel(
        layoutMode: SidebarLayoutMode = .drillDown,
        sortOrder: SortOrder = .foldersFirst,
        showHiddenFiles: Bool = false,
        showChangedFilesOnly: Bool = false,
        canFilterChangedFiles: Bool = true,
        isFilterActive: Bool = false,
        isFilterTextEmpty: Bool = true
    ) -> SidebarHeaderControlsModel {
        SidebarHeaderControlsModel(
            layoutMode: layoutMode,
            sortOrder: sortOrder,
            showHiddenFiles: showHiddenFiles,
            showChangedFilesOnly: showChangedFilesOnly,
            canFilterChangedFiles: canFilterChangedFiles,
            isFilterActive: isFilterActive,
            isFilterTextEmpty: isFilterTextEmpty
        )
    }

    /// git 管理外では絞り込む対象が無いので、押せないボタンを残さず消す(TASK-537)。
    /// 残る 2 つの並びが変わらないことも同時に固定する。
    @Test("git 管理外では変更のみ表示のボタンが出ない")
    func hidesChangedFilesOnlyOutsideGit() {
        let outsideGit = makeModel(canFilterChangedFiles: false)

        #expect(outsideGit.trailing.map(\.kind) == [.filter, .overflow])
        #expect(outsideGit.leading.map(\.kind) == [.layoutMode])
    }

    /// 左右分割そのものを固定する。doc コメントだけでは次のボタン追加で崩れるため、
    /// 並びを配列比較で押さえる（設計「テスト」節の 4 番）。
    @Test("左が表示形式、右が変更のみ・フィルター・⋯ の順になる")
    func groupsSplitFormFromFiltering() {
        let model = makeModel()

        #expect(model.leading.map(\.kind) == [.layoutMode])
        #expect(model.trailing.map(\.kind) == [.changedFilesOnly, .filter, .overflow])
    }

    @Test("表示形式のアイコンは現在のモードを表す", arguments: [
        (SidebarLayoutMode.tree, "list.bullet.indent"),
        (SidebarLayoutMode.drillDown, "list.bullet"),
    ])
    func layoutModeIconReflectsMode(mode: SidebarLayoutMode, expected: String) {
        let model = makeModel(layoutMode: mode)

        #expect(model.leading.first?.systemImage == expected)
    }

    /// 畳んだ絞り込み（不可視ファイル）が効いていることは ⋯ のアクセントだけが伝える。
    /// これが破れると、一覧にドットファイルが並ぶ理由がヘッダーから消える。
    @Test("⋯ は不可視ファイル ON のとき、かつそのときだけアクセントになる", arguments: [true, false])
    func overflowIsAccentedOnlyWhenHiddenFilesShown(showHiddenFiles: Bool) {
        let model = makeModel(showHiddenFiles: showHiddenFiles)

        let overflow = model.trailing.first { $0.kind == .overflow }
        #expect(overflow?.isAccented == showHiddenFiles)
    }

    /// ソート順は「常にどちらか」なのでアクセント対象にしない（設計「状態の見え方」節）。
    @Test("ソート順を変えても ⋯ のアクセントは変わらない")
    func sortOrderDoesNotAccentOverflow() {
        let alphabetical = makeModel(sortOrder: .alphabetical)

        let overflow = alphabetical.trailing.first { $0.kind == .overflow }
        #expect(overflow?.isAccented == false)
    }

    @Test("⋯ の中身はソート順 2 択と不可視ファイルの順に並ぶ")
    func overflowItemsAreSortThenHiddenFiles() {
        let model = makeModel()

        #expect(model.overflowItems.map(\.kind) == [.sortFoldersFirst, .sortAlphabetical, .hiddenFiles])
    }

    @Test("⋯ のチェックは現在のソート順の側に付く", arguments: [
        (SortOrder.foldersFirst, [true, false]),
        (SortOrder.alphabetical, [false, true]),
    ])
    func overflowChecksFollowSortOrder(sortOrder: SortOrder, expected: [Bool]) {
        let model = makeModel(sortOrder: sortOrder)

        let sortItems = model.overflowItems.filter { $0.kind != .hiddenFiles }
        #expect(sortItems.map(\.isChecked) == expected)
    }

    @Test("⋯ の不可視ファイル項目のチェックは現在値と一致する", arguments: [true, false])
    func hiddenFilesItemIsCheckedWhenShown(showHiddenFiles: Bool) {
        let model = makeModel(showHiddenFiles: showHiddenFiles)

        let item = model.overflowItems.first { $0.kind == .hiddenFiles }
        #expect(item?.isChecked == showHiddenFiles)
    }

    /// フィルターは「入力があるか」でアクセント、「開いているか」で help が変わる。
    /// 既存の SidebarHeaderView の振る舞いを保つ（アイコンも .fill へ切り替わる）。
    @Test("フィルターは入力があるときアクセントになる", arguments: [true, false])
    func filterIsAccentedWhenTextPresent(isFilterTextEmpty: Bool) {
        let model = makeModel(isFilterActive: true, isFilterTextEmpty: isFilterTextEmpty)

        let filter = model.trailing.first { $0.kind == .filter }
        #expect(filter?.isAccented == !isFilterTextEmpty)
        #expect(filter?.systemImage == (isFilterTextEmpty
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill"))
    }

    @Test("フィルターの help は開閉状態で入れ替わる", arguments: [true, false])
    func filterHelpFollowsOpenState(isFilterActive: Bool) {
        let model = makeModel(isFilterActive: isFilterActive)

        let filter = model.trailing.first { $0.kind == .filter }
        #expect(filter?.helpKey == (isFilterActive ? "sidebar.filter.hide" : "sidebar.filter.show"))
    }

    @Test("変更のみは ON のときアクセントになる", arguments: [true, false])
    func changedFilesOnlyIsAccentedWhenOn(showChangedFilesOnly: Bool) {
        let model = makeModel(showChangedFilesOnly: showChangedFilesOnly)

        let control = model.trailing.first { $0.kind == .changedFilesOnly }
        #expect(control?.isAccented == showChangedFilesOnly)
    }
}
