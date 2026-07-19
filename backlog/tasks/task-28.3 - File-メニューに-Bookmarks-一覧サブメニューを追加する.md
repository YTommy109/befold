---
id: TASK-28.3
title: File メニューに Bookmarks 一覧サブメニューを追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 11:20'
updated_date: '2026-07-19 08:41'
labels: []
dependencies:
  - TASK-28.1
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: medium
ordinal: 700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Open Recent と同様に、File メニュー内に Bookmarks サブメニューを新設し、ブックマーク済みファイルをファイル名アルファベット順に列挙してオープンできるようにする。RecentDocumentsMenuController を参考に BookmarksMenuController を実装する。BookmarkStore に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bookmarks サブメニューを開くとブックマーク済みファイルがファイル名アルファベット順に列挙される
- [x] #2 メニュー項目を選択するとそのファイルが開く（既存の openViewer 経路を再利用）
- [x] #3 ブックマーク済みファイルが存在しない場合でも一覧から自動削除されず、選択時に既存の FileNotFoundUI が表示される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarksMenuController を RecentDocumentsMenuController と同パターンで新設(クリア/個別削除なし、lastPathComponent でアルファベット順ソート)\n2. AppDelegate に bookmarksMenuController を保持し MainMenuBuilder.build に bookmarksMenuDelegate として渡す\n3. MainMenuBuilder の File メニューに Open Recent と並んで Bookmarks サブメニューを追加\n4. Localizable.xcstrings に menu.file.bookmarks を追加(en/ja)\n5. BookmarksMenuControllerTests・MainMenuBuilderTests にテスト追加\n6. 全体テスト・lint確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 463件全通過、swiftlint新規違反なし、l10n(en/ja)欠落なしを確認。選択時の未存在ファイル処理はAppDelegate.openViewer→windowManager.openViewer既存のFileNotFoundUI経路を再利用(追加実装不要)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BookmarksMenuController を新設し、File メニューに Open Recent と並ぶ Bookmarks サブメニューを追加。lastPathComponent でアルファベット順ソートして列挙し、選択時は既存の openViewer(FileNotFoundUI含む)経路を再利用。BookmarksMenuControllerTests・MainMenuBuilderTests にテストを追加し、swift test 463件全通過・swiftlint新規違反なしで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
