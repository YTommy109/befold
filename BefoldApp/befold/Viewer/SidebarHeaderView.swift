import BefoldKit
import SwiftUI

/// サイドバー上部の見出し行(基準ディレクトリ・フォルダー名・表示切り替えの各トグル・
/// 名前フィルター欄)。
///
/// `FileListView` から分けているのは、ここが扱うのが「一覧の見せ方の切り替え」であって
/// 一覧行の描画ではないため(TASK-443)。表示設定のトグルを増やすときに触るのはこの型だけで、
/// 行・コンテキストメニュー・キー操作には影響しない。
///
/// 各トグルの真実の源は `SidebarDisplayDefaults` で、`model` の値はその写し。
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
    /// スライドモードの解除。ウィンドウ側の `toggleSlideMode(_:)` と同じ経路を通す
    /// （状態と幅の更新順序を 1 箇所に保つため、ここで直接 model を書き換えない）。
    /// **既定値を持たせない。** 渡し忘れが「押しても何も起きないボタン」へ静かに倒れる。
    let onToggleSlideMode: () -> Void

    @FocusState private var isFilterFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.transient.isSlideMode {
                slideModeIndicator
            } else {
                baseDirectoryIndicator
                navigationHeader
                if model.transient.isFilterActive {
                    filterField
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// スライドモード中のヘッダー。**状態表示と解除操作を兼ねる。**
    /// 幅がアイコン 1 つ分しかないので他の操作は一切出さない（メニューからも解除できる）。
    private var slideModeIndicator: some View {
        Button {
            onToggleSlideMode()
        } label: {
            Image(systemName: "play.rectangle")
                .foregroundStyle(.tint)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "sidebar.slideMode.exit", bundle: .l10n))
    }

    private var filterField: some View {
        @Bindable var transient = model.transient
        return TextField(
            String(localized: "sidebar.filter.placeholder", bundle: .l10n),
            text: $transient.filterText
        )
        .textFieldStyle(.plain)
        .focused($isFilterFieldFocused)
        .onAppear { isFilterFieldFocused = true }
        .onKeyPress(.escape) {
            model.transient.closeFilter()
            return .handled
        }
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
            canFilterChangedFiles: model.canFilterChangedFiles,
            isFilterActive: model.transient.isFilterActive,
            isFilterTextEmpty: model.transient.filterText.isEmpty
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
        if model.transient.isFilterActive {
            model.transient.closeFilter()
        } else {
            model.transient.isFilterActive = true
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
