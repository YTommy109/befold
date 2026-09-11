---
id: TASK-586
title: サイドバーの表示切り替えを注入クロージャから FileListViewDelegate へ畳む
status: Done
assignee:
  - '@claude'
created_date: '2026-09-04 13:41'
updated_date: '2026-09-08 10:10'
labels: []
dependencies: []
ordinal: 851000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView / SidebarHeaderView が親から受け取る注入クロージャが 5 本ある（onSortOrderChanged / onToggleHiddenFiles / onToggleChangedFilesOnly / onToggleSidebarTreeLayout / onToggleSlideMode）。docs/dev/rules/product-code.md の責務分離節は「親→子へ注入するクロージャが 3 つを超えたら delegate プロトコルを検討する」と定めており、TASK-585 でスライドモードを足した時点で 4 → 5 本になった。

受け皿は既にある。FileListViewDelegate の doc コメントが「受け手が ViewerWindowController / SidebarNavigator に固定されているため、注入クロージャを 1 本ずつ生やさずこのプロトコルへ畳む」と述べており、5 本すべてが ViewerWindowAssembler で controller に束縛されていて適用条件を満たす。TASK-585 では対象タスクのスコープを守るため見送った（判断は TASK-585 の Implementation Notes）。

波及先は TASK-585 の差分で既に全部洗い出されている: FileListView.swift / SidebarHeaderView.swift / ViewerWindowAssembler.swift / FileListViewDelegate.swift と、FileListViewDelegateSpy.swift および FileListView を組み立てるテスト 6 本（FileListViewTests / FileListViewFilteredKeyboardTests / FileListViewNavigationKeyTests / SidebarModifierOpenTests / SidebarParentRowSelectionTests / FocusTraversalTests）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileListView / SidebarHeaderView の表示切り替え用の注入クロージャが 3 本以下になっている
- [x] #2 切り替えは FileListViewDelegate 経由で受け、種別は列挙型の引数で表す（切り替えを 1 つ足すたびにプロトコルのメソッドが増えない）
- [x] #3 ViewerWindowAssembler から controller の弱キャプチャを伴うトグル用クロージャが消えている
- [x] #4 既存のサイドバー操作のテストが通り、表示切り替え 4 種(不可視ファイル・変更のみ・ツリー表示・並び順)が delegate 経由で動くことをテストが確認している。ボタン Kind → SidebarDisplayChange の対応表ごとの担保(ヘッダーのボタン側も含む)は TASK-590 で足した
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListViewDelegate.swift に列挙型 SidebarDisplayRequest（.display(SidebarDisplayChange) / .slideMode）と delegate メソッド fileListDidRequestDisplayChange(_:) を足す。切り替えを 1 つ足してもメソッドは増えない。
2. FileListView / SidebarHeaderView から 5 本の注入クロージャを削除し、delegate 経由に置き換える。
3. ViewerWindowController+FileList.swift で受け、.display は sidebar.applyDisplayChange、.slideMode は toggleSlideMode(nil) へ配る。
4. ViewerWindowAssembler の makeFileListView からトグル用クロージャと makeDisplayToggle を撤去する。
5. FileListViewDelegateSpy に requestedDisplayChanges を足し、5 種すべてが delegate 経由で届くテストを追加。既存 6 本の呼び出し側を更新。
6. swift build / swift test / swiftlint ベースライン差分ゼロを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: FileListViewDelegate に fileListDidRequestDisplayChange(_:) を 1 本足し、種別は新設の列挙 SidebarDisplayRequest（.display(SidebarDisplayChange) / .slideMode）で表した。SidebarDisplayChange へスライドモードを混ぜなかったのは、あちらが窓ごとに保持し既定値へ書き戻す表示 4 値（ADR 0002）の変更を表す型で、幅も動かすスライドモードを入れると SidebarNavigator.applyDisplayChange が幅の面倒まで見ることになるため。

FileListView / SidebarHeaderView の注入クロージャは 5 本 → 0 本（delegate のみ）。ViewerWindowAssembler.makeFileListView は FileListView(model:delegate:) だけになり、makeDisplayToggle と controller の弱キャプチャクロージャは削除した。受け口は ViewerWindowController+FileList.swift の switch（.display → sidebar.applyDisplayChange / .slideMode → toggleSlideMode(nil)）。

GUI 層は自動テスト対象外なのでボタン自体は押せない。押した先の SidebarHeaderView.perform(_:) と ⋯ の対応表 displayRequest(for:) を internal にし、SidebarDisplayRequestRoutingTests が 5 種すべての delegate 到達と 3 項目の写しを測る。perform の本体を _ = request へ差し替えると当該テストが落ちることを実測で確認済み（差し戻し済み）。delegate → controller の switch 側は window を要するため単体では測っていない。

docs/dev/native-app-design.md は更新不要と判断した。同文書は FileListModel / FileListView をコンポーネント表の 1 行で扱うだけで、親子間の配線方式（クロージャか delegate か）を記述していないため、今回の変更で古くなる記述が無い。

検証: swift build 成功 / swift test 1875 tests in 308 suites passed / swiftlint ベースライン差分は真の新規ゼロ（origin/main 51 件 → HEAD 51 件、解消もゼロ）。

実装後レビュー（/code-review high、2026-09-05）の規約メモ: このタスクは新しい型（SidebarDisplayRequest）と新しいプロトコルメソッドを足し、5 ファイルにまたがる表示切替経路にノードを挿入したが、実装前の /review-design を回していない（TASK-585 は回している）。レビューで出た「ヘッダーボタンの配線が新テストの通らない場所に残っている」（TASK-590）は設計文だけから導ける型で、回していれば着手前に見つかっていた。指摘の起票先: TASK-590 / TASK-591 / TASK-592（TASK-586 由来）、TASK-588 / TASK-589（TASK-587 由来、main に PR #632 で入っている）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの表示切り替え 5 種（並び順・不可視ファイル・変更のみ・ツリー表示・スライドモード）を注入クロージャから FileListViewDelegate の 1 メソッドへ畳み、種別を列挙 SidebarDisplayRequest で表した。FileListView / SidebarHeaderView の注入クロージャは 5 → 0 本、ViewerWindowAssembler からトグル用の弱キャプチャクロージャと makeDisplayToggle が消えた。SidebarDisplayRequestRoutingTests で 5 種の delegate 到達を担保（perform を無効化すると落ちることを実測）。swift test 1875 件通過、swiftlint 新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
