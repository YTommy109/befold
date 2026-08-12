---
id: TASK-457
title: FileListView の注入クロージャを FileListViewDelegate へ畳む
status: To Do
assignee: []
created_date: '2026-08-12 01:54'
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
- [ ] #1 FileListView の注入クロージャが 3 本以下になる
- [ ] #2 コンテキストメニューが独立した View 型へ切り出されている
- [ ] #3 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
