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
///
/// **項目の identity は「選ぶと起こる表示切り替え」そのもの**(TASK-592)。項目用の
/// Kind を別に持つと Kind → `SidebarDisplayChange` の対応表がどこかに要り、交差した
/// 対応(`.sortAlphabetical → .setSortOrder(.foldersFirst)`)がコンパイルを通る。
/// 対応表を無くせば交差は書きようがない。
struct SidebarOverflowItem: Equatable {
    /// 選ばれたときに起こす表示切り替え。ForEach の id も兼ねる。
    let change: SidebarDisplayChange
    let titleKey: String
    /// チェックマークを付けるか。**init で受け取らない**——`change` が今 ON かを
    /// `SidebarDisplaySettings.isOn(_:)` から導く。渡せる形にすると「チェックは
    /// フォルダー優先、選ぶとアルファベット順」がコンパイルを通ってしまう。
    let isChecked: Bool

    init(change: SidebarDisplayChange, titleKey: String, in settings: SidebarDisplaySettings) {
        self.change = change
        self.titleKey = titleKey
        isChecked = settings.isOn(change)
    }
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

    /// - Parameters:
    ///   - settings: この窓のサイドバー表示 4 値(`FileListModel.display.settings`)。
    ///     **4 値を個別の引数で持ち回らない**——経路が増えるたびに引数が伸びて片方だけ
    ///     通し忘れる(`SidebarDisplayOverrides` と同じ理由、TASK-413 と同型)。⋯ の
    ///     チェックを `isOn(_:)` で導くのにも 4 値が揃っている必要がある。
    ///   - canFilterChangedFiles: git 管理下で「変更のあるファイルのみ」を出して
    ///     よいか(`FileListModel.canFilterChangedFiles`)。**既定値を持たせない。**
    ///     渡し忘れが「git 管理外でもボタンが出る」へ静かに倒れる形を作らないため。
    init(
        settings: SidebarDisplaySettings,
        canFilterChangedFiles: Bool,
        isFilterActive: Bool,
        isFilterTextEmpty: Bool
    ) {
        leading = Self.leadingControls(layoutMode: settings.layoutMode)
        trailing = Self.trailingControls(
            showHiddenFiles: settings.showHiddenFiles,
            showChangedFilesOnly: settings.showChangedFilesOnly,
            canFilterChangedFiles: canFilterChangedFiles,
            isFilterActive: isFilterActive,
            isFilterTextEmpty: isFilterTextEmpty
        )
        overflowItems = Self.overflowItems(settings)
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

    /// ⋯ の中身。並びと「どの切り替えを表すか」は `SidebarHeaderControlsModelTests` が
    /// `map(\.change)` の配列比較で同時に固定している。
    private static func overflowItems(_ settings: SidebarDisplaySettings) -> [SidebarOverflowItem] {
        [
            SidebarOverflowItem(
                change: .setSortOrder(.foldersFirst),
                titleKey: "sidebar.sortOrder.foldersFirst",
                in: settings
            ),
            SidebarOverflowItem(
                change: .setSortOrder(.alphabetical),
                titleKey: "sidebar.sortOrder.alphabetical",
                in: settings
            ),
            SidebarOverflowItem(
                change: .toggleHiddenFiles,
                titleKey: "menu.view.showHiddenFiles",
                in: settings
            ),
        ]
    }
}
