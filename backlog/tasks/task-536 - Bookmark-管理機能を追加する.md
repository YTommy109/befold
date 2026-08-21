---
id: TASK-536
title: Bookmark 管理機能を追加する
status: To Do
assignee: []
created_date: '2026-08-21 07:26'
labels: []
milestone: m-9
dependencies: []
priority: medium
type: feature
ordinal: 776000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 `BookmarkStore`（`BefoldApp/BefoldKit/BookmarkStore.swift:8-59`、`@MainActor`）は `PathListDefaults`（`BefoldApp/BefoldKit/PathListDefaults.swift`）経由で、UserDefaults キー `"BookmarkedPaths"` にフラットな `[String]`（正規化済みファイルパス）を保持するだけ。名前・順序（配列順は保持されるが表示は常にアルファベット順で未使用）・フォルダ・作成日時などのメタデータは一切無い。File > Bookmarks サブメニュー（`BookmarksMenuController.swift:29-44`）は `lastPathComponent` でソートして一覧表示するのみで、リネーム・任意の並び替え・グルーピングはできない。

親タスクとして「別名を付けられる」「削除できる」「ドラッグ&ドロップで追加できる」「フォルダー風の階層で整理できる」の4機能を追加する。実装は下記4件のサブタスクに分割する。

参考: 本プロダクトにはドラッグ&ドロップの実装が現状どこにも無い（`NSDraggingDestination` / SwiftUI `onDrop` 等、実測でヒット0件）。サイドバーのファイルツリー（`DirectoryListing.swift:9-59` / `SidebarRowBuilder` / `SidebarTreePresenter.swift`）は階層表示と展開状態分離のパターンを持つが、ファイルシステムのディレクトリ構造をそのまま反映するものであり、ブックマーク側で必要な「ファイルシステムとは独立したユーザー定義の仮想フォルダ」にはそのまま流用できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマークに別名を付けられる
- [ ] #2 ブックマークを個別に削除できる
- [ ] #3 ドラッグ&ドロップでブックマークを追加できる
- [ ] #4 ブックマークをフォルダー風の階層で整理できる
<!-- AC:END -->
