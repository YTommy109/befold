---
id: TASK-536
title: Bookmark 管理機能を追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 07:26'
updated_date: '2026-09-12 14:38'
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
- [x] #1 ブックマークに別名を付けられる
- [x] #2 ブックマークを個別に削除できる
- [x] #3 ドラッグ&ドロップでブックマークを追加できる
- [x] #4 ブックマークをフォルダー風の階層で整理できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計は docs/superpowers/specs/2026-09-12-bookmark-management-design.md（4 サブタスク共通）。順序は 536.1（スキーマ・移行・パネル新設・別名）→ 536.2（削除）→ 536.4（フォルダー）→ 536.3（Finder からの D&D）。依存は --dep で構造化済み。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
4 サブタスクすべて Done（536.1 → 536.2 → 536.4 → 536.3 の順で実装。PR #658 → #659 → #660 → 536.3 の PR を積んだ形）。共通設計は docs/superpowers/specs/2026-09-12-bookmark-management-design.md、現在仕様は docs/dev/native-app-design.md に反映済み。スキーマの移行は 536.1 で 1 回だけ行い、旧キー BookmarkedPaths は削除した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマーク管理を 4 つの機能で刷新した: 別名（536.1）、管理パネルからの削除（536.2）、Finder からの D&D 追加（536.3）、フォルダー階層（536.4）。永続化は値型 BookmarkLibrary（JSON、キー Bookmarks）へ一度だけ移行し、Bookmarks メニューと管理パネル（HostedPanel.bookmarks）が同じ値を読む。各サブタスクの検証は Implementation Notes を参照。
<!-- SECTION:FINAL_SUMMARY:END -->
