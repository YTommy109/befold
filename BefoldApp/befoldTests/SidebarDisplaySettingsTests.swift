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

    /// `applying` は `isOn` と対。**適用した直後は必ず `isOn` が反転している**ことで
    /// 両者の網羅が食い違っていないことを測る(片方だけ足すと「チェックは付くが
    /// 適用されない」形が作れる)。並び順だけは反転ではなく指定なので別に測る。
    @Test("トグル 3 種は適用すると isOn が反転する", arguments: [
        SidebarDisplayChange.toggleHiddenFiles,
        .toggleChangedFilesOnly,
        .toggleLayoutMode,
    ])
    func applyingFlipsIsOnForToggles(change: SidebarDisplayChange) {
        let allOn = settings(showHiddenFiles: true, showChangedFilesOnly: true, layoutMode: .tree)
        for start in [SidebarDisplaySettings.initial, allOn] {
            #expect(start.applying(change).isOn(change) == !start.isOn(change))
        }
    }

    @Test("並び順の適用は指定した順序を ON にする")
    func applyingSortOrderSetsRequestedOrder() {
        for current in SortOrder.allCases {
            for requested in SortOrder.allCases {
                let next = settings(sortOrder: current).applying(.setSortOrder(requested))

                #expect(next.sortOrder == requested)
                #expect(next.isOn(.setSortOrder(requested)))
            }
        }
    }

    /// 切り替えは互いに独立。1 つ適用したときに他の 3 値が動かないことを見る
    /// (`applying` が `var next = self` を土台にしていることの担保)。
    @Test("1 つの適用は他の値を動かさない", arguments: [
        SidebarDisplayChange.toggleHiddenFiles,
        .toggleChangedFilesOnly,
        .toggleLayoutMode,
        .setSortOrder(.alphabetical),
    ])
    func applyingLeavesOtherValuesUntouched(change: SidebarDisplayChange) {
        let start = SidebarDisplaySettings.initial
        let next = start.applying(change)
        let all: [SidebarDisplayChange] = [
            .toggleHiddenFiles, .toggleChangedFilesOnly, .toggleLayoutMode, .setSortOrder(.alphabetical),
        ]
        let others = all.filter { $0 != change }

        for other in others {
            #expect(next.isOn(other) == start.isOn(other))
        }
    }
}
