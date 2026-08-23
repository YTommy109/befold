import BefoldKit
import Foundation

/// ヘッダー操作行に出すボタン 1 個分の記述。
struct SidebarHeaderControl: Equatable {
    /// ボタンの種類。ビューはこれを見て押したときの動作を選ぶ。
    /// ForEach の id に使うため Hashable にする。
    enum Kind: Hashable {
        /// 一覧の形（ツリー / ドリルダウン）。左群に単独で置く。
        case layoutMode
        case changedFilesOnly
        case filter
        /// ソート順・不可視ファイルを畳んだオーバーフローメニュー。
        case overflow
    }

    let kind: Kind
    let systemImage: String
    /// help(ツールチップ)のローカライズキー。
    let helpKey: String
    /// 絞り込みが効いていることをアクセント色で示すか。
    let isAccented: Bool
}

/// オーバーフローメニュー 1 項目分の記述。
struct SidebarOverflowItem: Equatable {
    /// ForEach の id に使うため Hashable にする。
    enum Kind: Hashable {
        case sortFoldersFirst
        case sortAlphabetical
        case hiddenFiles
    }

    let kind: Kind
    let titleKey: String
    let isChecked: Bool
}

/// サイドバーヘッダーの操作行の構成を決める値型。
///
/// **左群は「一覧の形」、右群は「絞り込み」**という分割が設計上の判断で、位置がその
/// 系統を表している(設計: docs/superpowers/specs/2026-08-13-sidebar-header-controls-design.md)。
/// 並び順は `SidebarHeaderControlsModelTests` が配列比較で固定しているので、ボタンを
/// 足すときはどちらの群に属するかを先に決めること。
///
/// **⋯ に入れてよいのは「サイドバーの一覧の見え方に効く設定で、常設に値しないもの」だけ。**
/// ファイル操作・ウィンドウ操作は入れない。何でも入る箱にすると、畳んだこと自体が
/// 新しい散らかりになる。
struct SidebarHeaderControlsModel: Equatable {
    /// 左群(フォルダー名の左)。
    let leading: [SidebarHeaderControl]
    /// 右群(フォルダー名の右)。
    let trailing: [SidebarHeaderControl]
    /// ⋯ を開いたときの項目。
    let overflowItems: [SidebarOverflowItem]

    /// - Parameter canFilterChangedFiles: git 管理下で「変更のあるファイルのみ」を出して
    ///   よいか(`FileListModel.canFilterChangedFiles`)。**既定値を持たせない。**
    ///   渡し忘れが「git 管理外でもボタンが出る」へ静かに倒れる形を作らないため。
    init(
        layoutMode: SidebarLayoutMode,
        sortOrder: SortOrder,
        showHiddenFiles: Bool,
        showChangedFilesOnly: Bool,
        canFilterChangedFiles: Bool,
        isFilterActive: Bool,
        isFilterTextEmpty: Bool
    ) {
        leading = Self.leadingControls(layoutMode: layoutMode)
        trailing = Self.trailingControls(
            showHiddenFiles: showHiddenFiles,
            showChangedFilesOnly: showChangedFilesOnly,
            canFilterChangedFiles: canFilterChangedFiles,
            isFilterActive: isFilterActive,
            isFilterTextEmpty: isFilterTextEmpty
        )
        overflowItems = Self.overflowItems(sortOrder: sortOrder, showHiddenFiles: showHiddenFiles)
    }

    private static func leadingControls(layoutMode: SidebarLayoutMode) -> [SidebarHeaderControl] {
        let isTree = layoutMode == .tree
        return [
            SidebarHeaderControl(
                kind: .layoutMode,
                // アイコン自体がモードを表すため、アクセントでは示さない。
                systemImage: isTree ? "list.bullet.indent" : "list.bullet",
                helpKey: isTree ? "sidebar.layout.drillDown" : "sidebar.layout.tree",
                isAccented: false
            ),
        ]
    }

    /// git 管理外では「変更のあるファイルのみ」を**出さない**(無効のまま置かない)。
    /// メニューは項目位置が固定なのでグレーアウトが自然だが、ヘッダーは並びが詰まるので、
    /// 押せないボタンを残すより消えたほうが素直(TASK-537)。
    private static func trailingControls(
        showHiddenFiles: Bool,
        showChangedFilesOnly: Bool,
        canFilterChangedFiles: Bool,
        isFilterActive: Bool,
        isFilterTextEmpty: Bool
    ) -> [SidebarHeaderControl] {
        var controls: [SidebarHeaderControl] = []
        if canFilterChangedFiles {
            controls.append(SidebarHeaderControl(
                kind: .changedFilesOnly,
                systemImage: "arrow.triangle.branch",
                helpKey: showChangedFilesOnly
                    ? "sidebar.changedFilesOnly.hide"
                    : "sidebar.changedFilesOnly.show",
                isAccented: showChangedFilesOnly
            ))
        }
        controls.append(SidebarHeaderControl(
            kind: .filter,
            systemImage: isFilterTextEmpty
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill",
            helpKey: isFilterActive ? "sidebar.filter.hide" : "sidebar.filter.show",
            isAccented: !isFilterTextEmpty
        ))
        controls.append(SidebarHeaderControl(
            kind: .overflow,
            systemImage: "ellipsis.circle",
            helpKey: "sidebar.more",
            // 畳んだ絞り込みが効いていることを伝える唯一の手掛かり。
            isAccented: showHiddenFiles
        ))
        return controls
    }

    private static func overflowItems(
        sortOrder: SortOrder, showHiddenFiles: Bool
    ) -> [SidebarOverflowItem] {
        [
            SidebarOverflowItem(
                kind: .sortFoldersFirst,
                titleKey: "sidebar.sortOrder.foldersFirst",
                isChecked: sortOrder == .foldersFirst
            ),
            SidebarOverflowItem(
                kind: .sortAlphabetical,
                titleKey: "sidebar.sortOrder.alphabetical",
                isChecked: sortOrder == .alphabetical
            ),
            SidebarOverflowItem(
                kind: .hiddenFiles,
                titleKey: "menu.view.showHiddenFiles",
                isChecked: showHiddenFiles
            ),
        ]
    }
}
