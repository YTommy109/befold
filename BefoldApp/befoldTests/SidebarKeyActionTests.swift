@testable import befold
import SwiftUI
import Testing

/// サイドバーのキー操作の割り当て(TASK-361.4)。
///
/// GUI 層は自動テスト対象外なので、**ドリルダウン側の割り当てが変わっていないこと**は
/// この純粋関数のテストが唯一の測り方になる。ゲート越しに参照する形だけを残すと、
/// 動いているビルドの側しか検証されない(.claude/CLAUDE.md「フィーチャーゲート」)。
@Suite
struct SidebarKeyActionTests {
    private func action(
        _ key: KeyEquivalent, modifiers: EventModifiers = [],
        target: SidebarKeyAction.Target?, mode: SidebarLayoutMode
    ) -> SidebarKeyAction {
        SidebarKeyAction.action(key: key, modifiers: modifiers, target: target, mode: mode)
    }

    private let folder = SidebarKeyAction.Target(kind: .folder)
    private let expandedFolder = SidebarKeyAction.Target(kind: .folder, isExpanded: true)
    private let file = SidebarKeyAction.Target(kind: .file)
    private let parent = SidebarKeyAction.Target(kind: .parentNavigation)

    // MARK: - ドリルダウン（従来の割り当てを変えていないこと）

    @Test("ドリルダウン: → / return / l はフォルダへ入る")
    func drillDownForwardEntersFolder() {
        for key in [KeyEquivalent.rightArrow, .return, "l"] {
            #expect(action(key, target: folder, mode: .drillDown) == .navigateInto)
        }
    }

    @Test("ドリルダウン: ← / h / delete は親へ戻る")
    func drillDownBackwardNavigatesToParent() {
        for key in [KeyEquivalent.leftArrow, "h", .delete] {
            #expect(action(key, target: folder, mode: .drillDown) == .navigateToParent)
        }
    }

    @Test("ドリルダウン: 展開状態は割り当てに影響しない")
    func drillDownIgnoresExpansion() {
        #expect(action(.rightArrow, target: expandedFolder, mode: .drillDown) == .navigateInto)
        #expect(action(.leftArrow, target: expandedFolder, mode: .drillDown) == .navigateToParent)
    }

    // MARK: - 表示モードによらず同じもの

    @Test("上下移動と cmd+↑ は表示モードによらず同じ")
    func verticalMovementIsModeIndependent() {
        for mode in SidebarLayoutMode.allCases {
            #expect(action(.downArrow, target: file, mode: mode) == .selectNext)
            #expect(action("j", target: file, mode: mode) == .selectNext)
            #expect(action(.upArrow, target: file, mode: mode) == .selectPrevious)
            #expect(action("k", target: file, mode: mode) == .selectPrevious)
            #expect(
                action(.upArrow, modifiers: .command, target: file, mode: mode) == .navigateToParent
            )
        }
    }

    @Test("ファイル行では表示モードによらず開く")
    func fileOpensInEveryMode() {
        for mode in SidebarLayoutMode.allCases {
            #expect(action(.return, target: file, mode: mode) == .openFile)
        }
    }

    /// `..` はツリー表示でも上位フォルダーへの移動手段のまま。展開はできない。
    @Test("親移動行は表示モードによらずフォルダ移動")
    func parentNavigationRowNavigatesInEveryMode() {
        for mode in SidebarLayoutMode.allCases {
            #expect(action(.return, target: parent, mode: mode) == .navigateInto)
        }
    }

    // MARK: - ツリー展開

    @Test("ツリー: 畳んでいるフォルダで → は展開する")
    func treeForwardExpandsCollapsedFolder() {
        #expect(action(.rightArrow, target: folder, mode: .tree) == .expand)
        #expect(action(.return, target: folder, mode: .tree) == .expand)
    }

    @Test("ツリー: 展開済みのフォルダで → は最初の子へ進む")
    func treeForwardMovesIntoExpandedFolder() {
        #expect(action(.rightArrow, target: expandedFolder, mode: .tree) == .selectNext)
    }

    @Test("ツリー: 展開済みのフォルダで ← は畳む")
    func treeBackwardCollapsesExpandedFolder() {
        #expect(action(.leftArrow, target: expandedFolder, mode: .tree) == .collapse)
        #expect(action("h", target: expandedFolder, mode: .tree) == .collapse)
    }

    @Test("ツリー: 畳んでいる行で ← は従来どおり親へ戻る")
    func treeBackwardOnCollapsedRowNavigatesToParent() {
        #expect(action(.leftArrow, target: folder, mode: .tree) == .navigateToParent)
        #expect(action(.leftArrow, target: file, mode: .tree) == .navigateToParent)
    }

    /// ツリーでは ← が畳みになるため、上へ出る手段を delete に残しておかないと
    /// キーボードだけでルートより上へ行けなくなる。
    @Test("ツリー: delete は展開中のフォルダでもルートを 1 つ上げる")
    func treeDeleteAlwaysNavigatesToParent() {
        #expect(action(.delete, target: expandedFolder, mode: .tree) == .navigateToParent)
    }

    @Test("選択が無ければ前後移動以外は何もしない")
    func noSelectionIgnoresForwardAndBackward() {
        #expect(action(.return, target: nil, mode: .tree) == .ignored)
        #expect(action(.rightArrow, target: nil, mode: .drillDown) == .ignored)
    }

    // MARK: - ダブルクリック（return と同じ判断源）

    @Test("ダブルクリックは return と同じ動作になる")
    func doubleClickMatchesReturn() {
        for mode in SidebarLayoutMode.allCases {
            for target in [folder, expandedFolder, file, parent] {
                #expect(
                    SidebarKeyAction.doubleClickAction(target: target, mode: mode)
                        == action(.return, target: target, mode: mode)
                )
            }
        }
    }

    // MARK: - Target の導出

    @Test("行の開閉三角から展開状態が導かれる")
    func targetDerivesExpansionFromDisclosure() {
        let base = FileListEntry(url: URL(fileURLWithPath: "/tmp/a"), kind: .folder)

        #expect(!SidebarKeyAction.Target(entry: base).isExpanded)
        #expect(!SidebarKeyAction.Target(entry: base.disclosing(.collapsed)).isExpanded)
        #expect(SidebarKeyAction.Target(entry: base.disclosing(.expanded)).isExpanded)
        #expect(SidebarKeyAction.Target(entry: base.disclosing(.loadingChildren)).isExpanded)
        #expect(
            SidebarKeyAction.Target(entry: base.disclosing(.expandedEmpty(isFiltered: false)))
                .isExpanded
        )
        // 列挙に失敗した行も「展開されている」側。畳む操作(←)を届かせるためで、
        // 展開(→)を出すと beginExpanding が弾いて無反応になる(TASK-404)。
        #expect(SidebarKeyAction.Target(entry: base.disclosing(.expandedFailed)).isExpanded)
    }

    /// 失敗した行で ← を押したら畳めること(無反応にならないこと)を経路で押さえる。
    @Test("列挙に失敗したフォルダ行では、← が畳む操作になる")
    func leftArrowCollapsesFailedFolder() {
        let base = FileListEntry(url: URL(fileURLWithPath: "/tmp/a"), kind: .folder)
        let target = SidebarKeyAction.Target(entry: base.disclosing(.expandedFailed))

        #expect(
            SidebarKeyAction.action(
                key: .leftArrow, modifiers: [], target: target, mode: .tree
            ) == .collapse
        )
    }
}
