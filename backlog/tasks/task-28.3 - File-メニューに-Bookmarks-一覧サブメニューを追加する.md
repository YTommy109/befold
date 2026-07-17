---
id: TASK-28.3
title: File メニューに Bookmarks 一覧サブメニューを追加する
status: To Do
assignee: []
created_date: '2026-07-16 11:20'
updated_date: '2026-07-16 12:16'
labels: []
dependencies:
  - TASK-28.1
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: low
ordinal: 7300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Open Recent と同様に、File メニュー内に Bookmarks サブメニューを新設し、ブックマーク済みファイルをファイル名アルファベット順に列挙してオープンできるようにする。RecentDocumentsMenuController を参考に BookmarksMenuController を実装する。BookmarkStore に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bookmarks サブメニューを開くとブックマーク済みファイルがファイル名アルファベット順に列挙される
- [ ] #2 メニュー項目を選択するとそのファイルが開く（既存の openViewer 経路を再利用）
- [ ] #3 ブックマーク済みファイルが存在しない場合でも一覧から自動削除されず、選択時に既存の FileNotFoundUI が表示される
<!-- AC:END -->
