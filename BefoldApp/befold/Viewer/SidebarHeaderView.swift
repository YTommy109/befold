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
    let onSortOrderChanged: (SortOrder) -> Void
    var onToggleHiddenFiles: (() -> Void)?
    /// nil のときは git 変更のみ表示のボタンを出さない。
    /// 開発中機能の露出点(ViewerWindowController が FeatureGate で決める)。
    var onToggleChangedFilesOnly: (() -> Void)?

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

    private var navigationHeader: some View {
        HStack {
            Text(model.currentDirectory.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            sortOrderButton
            hiddenFilesButton
            changedFilesOnlyButton
            filterButton
        }
    }

    private var sortOrderButton: some View {
        Button {
            let next: SortOrder = model.sortOrder == .foldersFirst ? .alphabetical : .foldersFirst
            onSortOrderChanged(next)
        } label: {
            Image(systemName: model.sortOrder == .foldersFirst
                ? "folder.fill" : "textformat.abc")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(model.sortOrder == .foldersFirst
            ? String(localized: "sidebar.sort.alphabetical", bundle: .l10n)
            : String(localized: "sidebar.sort.foldersFirst", bundle: .l10n))
    }

    private var hiddenFilesButton: some View {
        Button {
            onToggleHiddenFiles?()
        } label: {
            Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                .foregroundStyle(model.showHiddenFiles ? .primary : .secondary)
        }
        .buttonStyle(.borderless)
        .help(model.showHiddenFiles
            ? String(localized: "sidebar.hiddenFiles.hide", bundle: .l10n)
            : String(localized: "sidebar.hiddenFiles.show", bundle: .l10n))
    }

    /// git 変更のあるファイルのみに絞るトグル。不可視ファイルのトグルとは独立した軸のため、
    /// 1 クリックで往復でき、両方の状態が同時に見えるよう別ボタンにしている(TASK-282)。
    @ViewBuilder
    private var changedFilesOnlyButton: some View {
        if let onToggleChangedFilesOnly {
            Button(action: onToggleChangedFilesOnly) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(model.showChangedFilesOnly ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(model.showChangedFilesOnly
                ? String(localized: "sidebar.changedFilesOnly.hide", bundle: .l10n)
                : String(localized: "sidebar.changedFilesOnly.show", bundle: .l10n))
        }
    }

    private var filterButton: some View {
        Button {
            if model.isFilterActive {
                closeFilter()
            } else {
                model.isFilterActive = true
            }
        } label: {
            Image(systemName: model.filterText.isEmpty
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(model.filterText.isEmpty ? .secondary : .primary)
        }
        .buttonStyle(.borderless)
        .help(model.isFilterActive
            ? String(localized: "sidebar.filter.hide", bundle: .l10n)
            : String(localized: "sidebar.filter.show", bundle: .l10n))
    }
}
