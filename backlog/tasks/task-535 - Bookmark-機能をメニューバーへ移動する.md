---
id: TASK-535
title: Bookmark 機能をメニューバーへ移動する
status: To Do
assignee: []
created_date: '2026-08-21 07:25'
labels: []
milestone: m-9
dependencies: []
priority: medium
type: enhancement
ordinal: 775000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 Bookmark のトグル操作はツールバーボタン（`BefoldApp/befold/App/ViewerToolbarController.swift:59-63`、SF Symbol `bookmark`/`bookmark.fill`、アクション `bookmarkItemClicked(_:)`。選択状態の見た目は `ViewerToolbarController+State.swift:89-99`）から行える。

一方でメニューバー側には既に以下が存在する:
- View メニューの「ブックマークを追加/削除」トグル（`MainMenuBuilder+ViewMenu.swift:28-30` → `ViewerWindowController.toggleBookmark(_:)`、`ViewerWindowController+MenuActions.swift:96-104`）。キーボードショートカットは `BookmarkShortcut.swift` で一元定義。
- File > Bookmarks サブメニュー（`MainMenuBuilder.swift:103` → `BookmarksMenuController.swift`、`NSMenuDelegate` としてブックマーク済みファイルを `lastPathComponent` でソートして一覧表示し、「Remove Missing Bookmarks」も持つ）。

つまり現時点でも Bookmark 操作の大半はメニューバーから可能だが、ツールバーボタンが並行して残っており、ツールバーとメニューバーの2箇所に同じ機能の導線がある。本タスクでは、ツールバーの Bookmark ボタンを廃止し、Bookmark 操作をメニューバー側（View メニュー + File > Bookmarks サブメニュー）に一本化する。

未確認の前提: ツールバーボタン廃止後、現在のファイルがブックマーク済みかどうかを一目で判別する手段（ツールバーボタンの `.fill` 状態が担っていた役割）をメニューバー側でどう代替するかは未検討。着手時に View メニュー項目のチェックマーク表示可否を確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツールバーの Bookmark ボタンが削除されている
- [ ] #2 Bookmark のトグル操作が View メニューから行え、既存のキーボードショートカットが維持されている
- [ ] #3 File > Bookmarks サブメニューから既存のブックマーク一覧表示・Remove Missing Bookmarks 操作が引き続き行える
- [ ] #4 現在開いているファイルがブックマーク済みかどうかをメニューバー側から視覚的に判別できる
<!-- AC:END -->
