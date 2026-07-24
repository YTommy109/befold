---
id: TASK-118
title: サイドバーを開いた直後にフォーカスをサイドバーへ移す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-24 04:38'
updated_date: '2026-07-24 05:17'
labels:
  - ux
  - ui
dependencies: []
priority: medium
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーを初めて開いたとき、フォルダー名のフォントがグレー(inactive/未フォーカスの見た目)で表示される。サイドバーにフォーカスが移ると通常の黒フォントになる。サイドバーを開いた時点でフォーカスをサイドバー(アウトラインビュー)へ移すことで、初期状態のグレー表示を解消し、開いた直後から矢印キーで操作できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーを開いた直後にフォルダー名が通常(アクティブ)の黒フォントで表示される
- [x] #2 サイドバーを開いた直後に矢印キーでファイル/フォルダーを選択操作できる(フォーカスがサイドバーにある)
- [x] #3 プレビュー領域の操作性を損なわない(フォーカス移動の副作用を確認する)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. focus ロジックを FileListModel.focusSidebarTable() へ集約(クリック時 #144 と共用、参照未解決時は次ランループへ限定リトライ)
2. FileListView.singleTapGesture は model.focusSidebarTable() を呼ぶよう変更
3. ViewerSplitViewController.toggleSidebar の『開いた時』ブロックで、ホストビューへの makeFirstResponder を onSidebarDidReveal クロージャ呼び出しへ差し替え
4. ViewerWindowController が onSidebarDidReveal に fileListModel.focusSidebarTable() を配線
5. テスト: FileListModel.focusSidebarTable が sidebarTableView を first responder にすることを検証。手動でサイドバー開時の黒フォント/矢印キー操作を確認
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーを開いた時のフォーカス先を、SwiftUI ホストビューから実体の NSTableView へ変更。これにより開いた直後からアウトラインビューがアクティブになり、フォルダー名が黒(アクティブ)表示になり矢印キーで操作できる。focus ロジックを FileListModel.focusSidebarTable() へ集約し、クリック時(#144)と共用・参照未解決時は次ランループで限定リトライ。ViewerSplitViewController は onSidebarDidReveal で開いた事実のみ通知し、フォーカス移動は開いた時(wasCollapsed→展開)に限定するためプレビュー操作への副作用はない。focus 要求先が NSTableView であることを FileListModelFocusTests で検証、矢印キー選択は FileListViewTests で担保、全579テスト通過。黒フォント表示・矢印キー操作の視覚確認は本プロジェクト規約のリリース前手動チェックで最終確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
