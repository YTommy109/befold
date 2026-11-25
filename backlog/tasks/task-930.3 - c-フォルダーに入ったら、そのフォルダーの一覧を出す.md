---
id: TASK-930.3
title: (c) フォルダーに入ったら、そのフォルダーの一覧を出す
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T00:12:54Z'
updated_date: '2026-11-25T01:27:41Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: feature
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 5。リスト表示でフォルダー D に入る（ダブルクリック・→・パスメニュー・上へ移動）と、いまは D の一覧ではなく、記憶した選択か先頭の項目を自動で選ぶ（SidebarNavigator.navigateToFolder）。その結果、ファイルが開く・サブフォルダーの一覧が出る・空タブがファイルに置き換わる。利用者がフォルダーを選んだ意図どおり、D の一覧を出すようユーザーが決めた（2026-11-25）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リスト表示でフォルダー D に入ると、本文に D の一覧が出て、ファイルの切り替えは起きない
- [x] #2 上へ移動したときは、移動先のフォルダーの一覧が出る（直前にいた子フォルダーの一覧ではない）
- [x] #3 空タブでフォルダーに入っても、空タブがファイルに置き換わらない
- [x] #4 選択の記憶（SidebarSelectionMemory）が不要になれば撤去し、残すならサイドバーの強調にだけ使う。どちらにしたかを Notes に残す
- [x] #5 CHANGELOG に載せる利用者向けの変更として、Notes に一文で記録する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarNavigator.navigateToFolder: host/ホーム上限のガードを通った直後、moveCurrentDirectory と同じ同期区間で presentingFolder(url) を呼ぶ(意図を着地前に書く。ADR 0013 決定 4/5)
2. 着地コールバックの 3 分岐(記憶の復元/上へ移動で子フォルダー行/先頭行の自動選択)を削除し、選択は nil にする。select(_:presentingWith:) を削除し、フォルダー移動から performFileSwitch へ届く経路を無くす(AC#1/#3 を構造で満たす)。recordHistory は着地のまま
3. SidebarSelectionMemory を撤去(AC#4)。行のタップは選択の一致に関係なく presentSelected を呼ぶため強調の記憶は操作に要らず、提示していない行を強調しない(ADR 0002 の投影)・履歴再生 .folder(nil) → 選択 nil と揃える。firstSelectableEntryURL が本番で未使用になれば撤去
4. テスト: 窓レベルで、入る/上へ移動で intent==.folder(移動先) かつ fileURL 不変、空タブが置き換わらない。既存の期待が変わるテスト(FolderNavigation / SelectionMemory / History / FileOpenPresentation.folderEntryHeadFile / ControllerIntegration)を更新。修正を戻して落ちることを確認
5. docs(native-app-design / viewer-ui / spec 注記)・doc コメント・xcodegen generate

[/review-design 結果] 1 判定の源: 行の有無で本文を決めない。意図は入口の事実(フォルダーに入った)で書く / 2 不変条件: 「開いている文書を一覧へ含める」は refreshFileList 側で無関係 / 3 消費経路: ダブルクリック・→(FileListView+Keyboard)・←上へ・パスメニュー(SidebarHeaderView)・本文の一覧(ViewerWindowAssembler onNavigateToFolder)・空タブがすべて SidebarNavigator.navigateToFolder を通る(rg 実測)ので絞り込み点で直す / 4 新しい表示状態: 無し(既存の FolderListingView) / 5 順序: 意図が一覧の着地より先になる。FolderListingSourceResolver が currentDirectory 先行中を扱う(TASK-293/295)ので本文は出る。recordHistory は着地のままで意図を読む / 6 高頻度: 無し / 7 測るもの: 窓レベルで presentationIntent.target と fileURL を測る / 8 世代: 意図は同期書きで着地を待たない。連続移動は最後の書き込みが勝ち、古い着地は performListing の世代ガードで捨てる / 9 粒度: 記憶を撤去し状態が減る / 10 型グループ SidebarNavigator 438 行 → 減る。責務・stored property・注入クロージャは増えない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: SidebarNavigator.navigateToFolder は、ガードを通った時点で選択を外して presentingFolder(移動先) を呼び、着地では行の反映と履歴の記録だけを行う。select(_:presentingWith:) を削除したので、フォルダー移動から performFileSwitch へ届く経路は無い(AC#1/#3 を構造で満たす)。入口(ダブルクリック・→・←上へ・パスメニュー・本文の一覧・空タブ)はすべてこの関数を通る(rg で実測)。
AC#4: SidebarSelectionMemory は撤去した。行のタップは選択の一致に関係なく presentSelected を呼ぶ(FileListView.handleRowTap)ので、強調を残す必要が操作の面で無い。提示していない行を強調しない形(ADR 0002 の投影)と、履歴再生 .folder(nil) → 選択 nil にも揃う。上へ移動での子フォルダー行の強調もやめた。本番で使い手の無くなった FileListModel.firstSelectableEntryURL も撤去した(キー操作は FileListSnapshot.firstSelectable を直接使っており、既存テストはそちらへ付け替えた)。
テスト: 窓レベル ViewerWindowFileOpenPresentationTests.enteringOrLeavingFolderPresentsDestinationListing、navigator レベル SidebarNavigatorFolderNavigationTests の 3 本(入る×先頭がファイル/フォルダー、上へ、再訪)、空タブ BlankTabReplacementTests.navigatingToFolderWithFileKeepsBlank(旧: 置き換わる、を反転)。旧挙動(着地で先頭行を選んで開く)の変異を入れて、新しいテストがケースごとにすべて落ちることを確認した。swift test --skip PDF: 1997 件が通過。swiftlint は変更ファイルで 0 件。
削除したテスト: SidebarNavigatorSelectionMemoryTests、HistoryTests の『履歴の適用は moveCurrentDirectory を通り…選択を記憶する』(記憶の有無を観測量にしていた)。
文書: docs/dev/viewer-ui.md に『フォルダーに入る』節を足し、空タブの段落を直した。native-app-design.md には該当する記述が無かった。
CHANGELOG 用(AC#5): リスト表示でフォルダーに入ったり上へ移動したりすると、ファイルを自動で開かず、そのフォルダーの一覧を表示するようになりました。
実機(GUI)での確認はまだ。窓レベルのテスト(実ファイルシステム上の ViewerWindowController)で測った。

追加修正(advisor の指摘で実測): 入った後の選択が nil になったため、refreshFileList の既定フォールバック(選択が一覧に無ければ開いている文書を選び直す)が、窓がキーになるたびに走る常態の経路になっていた。文書の行が強調されるうえ、文書が D の外にあると、ツリー→リストの切り替え(SidebarLayoutTransition)がカレントを文書のフォルダーへ移していた(変異で実測)。フォールバックで host.presentedTarget がフォルダー一覧なら選択を nil にする形に直した(ADR 0013 決定 3)。テスト SidebarNavigatorFolderNavigationTests.refreshAfterEnteringKeepsFolderPresentation(文書が D の中/外)。全体 1998 件が通過。
削除した履歴テストが担保していた『履歴適用は moveCurrentDirectory を通る』は、SidebarPostSwitchSyncTests の『履歴適用: …展開が捨てられる』が引き続き担保している。
引き換えになった挙動: ←(上へ)の直後は子フォルダー行が強調されないため、→ ですぐ入り直せない(performOnSelectedEntry は選択が無いと無視する)。↓ で先頭行から選び直せる。強調だけを残す形も AC#4 の範囲内なので、ユーザーが判断できる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダーに入る・上へ移動すると、記憶した選択や先頭行を自動で選ばず、本文に移動先の一覧を一覧の着地前に出すようにした(ADR 0013 決定 5)。SidebarSelectionMemory と firstSelectableEntryURL を撤去。空タブは置き換わらなくなった。テストは変異を入れて落ちることを確認し、全体 1997 件が通過。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
