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

    @Test("ツリー: 畳んでいる行・ファイル行で ← はツリー内の親行へ選択を移す")
    func treeBackwardOnCollapsedRowSelectsParentRow() {
        #expect(action(.leftArrow, target: folder, mode: .tree) == .selectParent)
        #expect(action(.leftArrow, target: file, mode: .tree) == .selectParent)
        #expect(action("h", target: folder, mode: .tree) == .selectParent)
        #expect(action("h", target: file, mode: .tree) == .selectParent)
    }

    /// ツリーの ← が「ルートを変えない」という判断を、破れたら落ちる形で押さえる。
    /// 個別ケースの列挙だと、あとから足したターゲットで穴が開く(TASK-408)。
    @Test("ツリー: ← / h はどの行でもルートを変えない")
    func treeBackwardNeverChangesRoot() {
        let targets: [SidebarKeyAction.Target?] = [folder, expandedFolder, file, parent, nil]
        for key in [KeyEquivalent.leftArrow, "h"] {
            for target in targets {
                #expect(action(key, target: target, mode: .tree) != .navigateToParent)
                #expect(action(key, target: target, mode: .tree) != .navigateInto)
            }
        }
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

    /// ツリーの展開済みフォルダだけは return と意図的に分かれる(開閉のトグル)。
    /// それ以外は return と同じ判断源を通す。
    @Test("ダブルクリックは、ツリーの展開済みフォルダ以外では return と同じ動作になる")
    func doubleClickMatchesReturnExceptExpandedTreeFolder() {
        for mode in SidebarLayoutMode.allCases {
            for target in [folder, expandedFolder, file, parent] {
                if mode == .tree, target == expandedFolder { continue }
                #expect(
                    SidebarKeyAction.doubleClickAction(target: target, mode: mode)
                        == action(.return, target: target, mode: mode)
                )
            }
        }
    }

    /// `.selectNext` を「畳む」の意味で読み替える形を残さないための担保(TASK-408)。
    @Test("ツリー: 展開済みフォルダのダブルクリックは畳む")
    func doubleClickCollapsesExpandedTreeFolder() {
        #expect(SidebarKeyAction.doubleClickAction(target: expandedFolder, mode: .tree) == .collapse)
        #expect(SidebarKeyAction.doubleClickAction(target: folder, mode: .tree) == .expand)
    }

    // MARK: - 開閉三角のクリック（TASK-472）

    /// 三角のクリックは ON/OFF の両方向を担う。片方向しか測らないと、
    /// 「開くが閉じない」形の実装が通ってしまう。
    @Test("三角のクリックは畳み↔展開をどちらの向きにも切り替える")
    func disclosureToggleSwitchesBothDirections() {
        #expect(SidebarKeyAction.disclosureToggleAction(target: folder) == .expand)
        #expect(SidebarKeyAction.disclosureToggleAction(target: expandedFolder) == .collapse)
    }

    /// 展開しているかどうかの導出は `Target(entry:)` と同じもの
    /// (三角クリックとキー操作で判定がずれない)。読み込み中・空・列挙失敗は
    /// いずれも「展開されている」側なので、クリックすると畳む。
    @Test("三角のクリックは全ての開閉状態で正しい向きへ倒れる")
    func disclosureToggleCoversEveryDisclosureState() {
        let base = FileListEntry(url: URL(fileURLWithPath: "/tmp/a"), kind: .folder)
        let expandedStates: [SidebarDisclosureState] = [
            .expanded, .loadingChildren, .expandedEmpty(isFiltered: false),
            .expandedEmpty(isFiltered: true), .expandedFailed,
        ]
        for state in expandedStates {
            let target = SidebarKeyAction.Target(entry: base.disclosing(state))
            #expect(SidebarKeyAction.disclosureToggleAction(target: target) == .collapse)
        }
        let collapsed = SidebarKeyAction.Target(entry: base.disclosing(.collapsed))
        #expect(SidebarKeyAction.disclosureToggleAction(target: collapsed) == .expand)
    }

    /// フォルダ以外に三角は出ないが、呼べてしまう口は残る。
    @Test("三角のクリックはフォルダ行以外では何も起こさない")
    func disclosureToggleIgnoresNonFolders() {
        #expect(SidebarKeyAction.disclosureToggleAction(target: file) == .ignored)
        #expect(SidebarKeyAction.disclosureToggleAction(target: parent) == .ignored)
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
