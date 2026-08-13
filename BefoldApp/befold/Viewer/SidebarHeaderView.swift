import BefoldKit
import SwiftUI

/// サイドバー上部の見出し行(基準ディレクトリ・フォルダー名・表示切り替えの各トグル・
/// 名前フィルター欄)。
///
/// `FileListView` から分けているのは、ここが扱うのが「一覧の見せ方の切り替え」であって
/// 一覧行の描画ではないため(TASK-443)。表示設定のトグルを増やすときに触るのはこの型だけで、
/// 行・コンテキストメニュー・キー操作には影響しない。
///
/// 各トグルの真実の源は `SidebarDisplayPreference` で、`model` の値はその写し。
/// ここは写しを読んで見た目を決め、切り替えの実行はクロージャで上位(ViewerWindowController)
/// へ返す。
struct SidebarHeaderView: View {
    @Bindable var model: FileListModel
    /// フォルダー名のパスポップアップが起こす移動の受け手。
    ///
    /// **移動用のクロージャを別に増やさない。** ⌘↑ / delete と同じ
    /// `fileListDidRequestNavigation(to:)` を通すことで、上へ移動する経路が 1 本に
    /// 保たれる(TASK-475)。ウィンドウ側が保持するため弱参照で持つ。
    weak var delegate: FileListViewDelegate?
    let onSortOrderChanged: (SortOrder) -> Void
    var onToggleHiddenFiles: (() -> Void)?
    let onToggleChangedFilesOnly: () -> Void
    let onToggleSidebarTreeLayout: () -> Void

    @FocusState private var isFilterFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            baseDirectoryIndicator
            navigationHeader
            if model.isFilterActive {
                filterField
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var filterField: some View {
        TextField(
            String(localized: "sidebar.filter.placeholder", bundle: .l10n),
            text: $model.filterText
        )
        .textFieldStyle(.plain)
        .focused($isFilterFieldFocused)
        .onAppear { isFilterFieldFocused = true }
        .onKeyPress(.escape) {
            closeFilter()
            return .handled
        }
    }

    /// フィルターフィールドを閉じ、フィルター文字列を解除する。
    /// アイコン再押下・esc のどちらからも同じ挙動にするための共通口。
    private func closeFilter() {
        model.isFilterActive = false
        model.filterText = ""
    }

    /// 基準ディレクトリの解決前(初回表示直後の一瞬)は行を出さない。
    @ViewBuilder
    private var baseDirectoryIndicator: some View {
        if let base = model.baseDirectory {
            BaseDirectoryIndicator(base: base)
        }
    }

    private var controls: SidebarHeaderControlsModel {
        SidebarHeaderControlsModel(
            layoutMode: model.layoutMode,
            sortOrder: model.sortOrder,
            showHiddenFiles: model.showHiddenFiles,
            showChangedFilesOnly: model.showChangedFilesOnly,
            isFilterActive: model.isFilterActive,
            isFilterTextEmpty: model.filterText.isEmpty
        )
    }

    /// 左＝一覧の形、右＝絞り込み。位置がその系統を表しているので、ボタンを足すときは
    /// どちらの群かを先に決めること(並びは SidebarHeaderControlsModelTests が固定している)。
    private var navigationHeader: some View {
        HStack {
            headerControls(placement: .leading)
            SidebarPathMenuButton(
                directory: model.currentDirectory,
                home: DirectoryLister.defaultHome,
                onNavigate: { delegate?.fileListDidRequestNavigation(to: $0) }
            )
            Spacer()
            headerControls(placement: .trailing)
        }
    }

    private func headerControls(placement: SidebarHeaderControls.Placement) -> some View {
        SidebarHeaderControls(
            controls: controls,
            placement: placement,
            onToggleLayoutMode: onToggleSidebarTreeLayout,
            onToggleChangedFilesOnly: onToggleChangedFilesOnly,
            onToggleFilter: toggleFilter,
            onSelectOverflowItem: selectOverflowItem
        )
    }

    private func toggleFilter() {
        if model.isFilterActive {
            closeFilter()
        } else {
            model.isFilterActive = true
        }
    }

    private func selectOverflowItem(_ kind: SidebarOverflowItem.Kind) {
        switch kind {
        case .sortFoldersFirst: onSortOrderChanged(.foldersFirst)
        case .sortAlphabetical: onSortOrderChanged(.alphabetical)
        case .hiddenFiles: onToggleHiddenFiles?()
        }
    }
}
