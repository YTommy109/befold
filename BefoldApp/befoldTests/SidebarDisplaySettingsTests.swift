@testable import befold
import Testing

/// 「その切り替えが今 ON か」の定義を固定する。
///
/// この述語は View メニューのチェック状態(`SidebarDisplayMenuState`)と、サイドバー
/// ヘッダーの ⋯ メニューのチェックマーク(`SidebarOverflowItem`)の**両方が読む唯一の
/// 定義**(TASK-592)。以前は 2 箇所が別々に符号化していたため、片方だけを直すと
/// 「メニューはチェックが付くのに ⋯ は付かない」形が作れた。
@Suite
struct SidebarDisplaySettingsTests {
    private func settings(
        showHiddenFiles: Bool = false,
        showChangedFilesOnly: Bool = false,
        layoutMode: SidebarLayoutMode = .drillDown,
        sortOrder: SortOrder = .foldersFirst
    ) -> SidebarDisplaySettings {
        SidebarDisplaySettings(
            showHiddenFiles: showHiddenFiles, showChangedFilesOnly: showChangedFilesOnly,
            layoutMode: layoutMode, sortOrder: sortOrder
        )
    }

    @Test("不可視ファイル表示の ON は現在値と一致する", arguments: [true, false])
    func hiddenFilesIsOnFollowsCurrentValue(showHiddenFiles: Bool) {
        let settings = settings(showHiddenFiles: showHiddenFiles)

        #expect(settings.isOn(.toggleHiddenFiles) == showHiddenFiles)
    }

    @Test("変更ファイルのみの ON は現在値と一致する", arguments: [true, false])
    func changedFilesOnlyIsOnFollowsCurrentValue(showChangedFilesOnly: Bool) {
        let settings = settings(showChangedFilesOnly: showChangedFilesOnly)

        #expect(settings.isOn(.toggleChangedFilesOnly) == showChangedFilesOnly)
    }

    /// 表示形式は 2 値なので「ON」はツリー側と決めてある。
    /// `SidebarDisplayMenuState.checksTreeLayout` が元から採っていた定義。
    @Test("表示形式はツリーのときだけ ON になる", arguments: [
        (SidebarLayoutMode.tree, true),
        (SidebarLayoutMode.drillDown, false),
    ])
    func layoutModeIsOnOnlyForTree(layoutMode: SidebarLayoutMode, expected: Bool) {
        let settings = settings(layoutMode: layoutMode)

        #expect(settings.isOn(.toggleLayoutMode) == expected)
    }

    /// 並び順だけは「反転」ではなく「指定した値にする」なので、問い合わせた順序と
    /// 現在値が一致するときだけ ON。全組み合わせで測る。
    @Test("並び順は現在の順序と一致するときだけ ON になる")
    func sortOrderIsOnOnlyForCurrentOrder() {
        for current in SortOrder.allCases {
            for queried in SortOrder.allCases {
                let settings = settings(sortOrder: current)

                #expect(settings.isOn(.setSortOrder(queried)) == (current == queried))
            }
        }
    }
}
