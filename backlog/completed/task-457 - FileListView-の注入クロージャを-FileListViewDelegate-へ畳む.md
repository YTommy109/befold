---
id: TASK-457
title: FileListView の注入クロージャを FileListViewDelegate へ畳む
status: Done
assignee: []
created_date: '2026-08-12 01:54'
updated_date: '2026-08-13 07:34'
labels:
  - chore
dependencies: []
priority: low
ordinal: 681000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-443 のヘッダー切り出しで FileListView の注入クロージャは 8 本 → 5 本まで減ったが、規約の上限 3 本を超えたまま残っている（onSelect / onNavigate / onOpenElsewhere / onExpandFolder / onCollapseFolder）。

いずれも受け手は SidebarNavigator / ViewerWindowController で、SidebarNavigatorHost / ViewerWindowControllerDelegate と同じ流儀のプロトコルへ畳める。合わせて、コンテキストメニュー（FileListView.swift の contextMenuItems ほか約 67 行）を SidebarContextMenu として切り出すと onOpenElsewhere の配線もそちらへ移せる。

出典: TASK-443 で回した responsibility-reviewer の指摘（スコープ外として見送り）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileListView の注入クロージャが 3 本以下になる
- [x] #2 コンテキストメニューが独立した View 型へ切り出されている
- [x] #3 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FileListView の注入クロージャ 5 本（onSelect / onNavigate / onOpenElsewhere / onExpandFolder / onCollapseFolder）を FileListViewDelegate（新規, befold/Viewer/FileListViewDelegate.swift）へ畳んだ。残る注入は onSortOrderChanged / onToggleHiddenFiles / onToggleChangedFilesOnly の 3 本で規約の上限内。

- 受け手は ViewerWindowController+FileList.swift の extension（SidebarNavigatorHost と同じ薄い配し層）。ViewerWindowAssembler.makeFileListView は controller を delegate として渡すだけになり、5 本の [weak controller] クロージャが消えた。
- プロトコルに既定実装は置かない。expand/collapse を optional にするとツリー表示側の配線漏れがコンパイル時に落ちなくなるため（表示モードの出し分けは SidebarKeyAction が持つ）。
- コンテキストメニューは SidebarContextMenu へ切り出し、openElsewhereEntries もそちらへ移した（FileListView 204 行 → 127 行）。
- FileListView.delegate は弱参照。テストはスパイを FileListViewDelegateStore が保持する（befoldTests/FileListViewDelegateSpy.swift）。
- 実測: swift test 1478 件パス。swiftlint は main とのベースライン差分ゼロ（両者 54 件で一致）。
<!-- SECTION:NOTES:END -->
