---
id: TASK-586
title: サイドバーの表示切り替えを注入クロージャから FileListViewDelegate へ畳む
status: To Do
assignee: []
created_date: '2026-09-04 13:41'
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
- [ ] #1 FileListView / SidebarHeaderView の表示切り替え用の注入クロージャが 3 本以下になっている
- [ ] #2 切り替えは FileListViewDelegate 経由で受け、種別は列挙型の引数で表す（切り替えを 1 つ足すたびにプロトコルのメソッドが増えない）
- [ ] #3 ViewerWindowAssembler から controller の弱キャプチャを伴うトグル用クロージャが消えている
- [ ] #4 既存のサイドバー操作のテストが通り、スライドモード・不可視ファイル・変更のみ・ツリー表示・並び順の 5 つがすべて delegate 経由で動くことをテストが確認している
<!-- AC:END -->
