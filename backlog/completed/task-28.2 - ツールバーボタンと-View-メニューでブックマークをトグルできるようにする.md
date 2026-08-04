---
id: TASK-28.2
title: ツールバーボタンと View メニューでブックマークをトグルできるようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 11:20'
updated_date: '2026-07-19 08:36'
labels: []
dependencies:
  - TASK-28.1
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: medium
ordinal: 600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在開いているファイルのブックマーク状態をツールバーボタン（bookmark/bookmark.fill）と View メニュー項目で表示・トグルできるようにする。BookmarkStore に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツールバーボタンでブックマークの on/off を切り替えられ、状態がアイコン・contentTintColor に反映される
- [x] #2 ファイル切り替え時にツールバーボタンの状態が新しいファイルの状態に更新される
- [x] #3 View メニューにブックマークする/解除の項目があり、現在のファイルの状態に応じてタイトルが動的に切り替わる
- [x] #4 キーボードショートカットが割り当てられ、既存ショートカットと衝突しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppDelegate→ViewerWindowManager→ViewerWindowController の三層に BookmarkStore を注入(ZoomStore/HiddenFilesPreference と同じパターン)\n2. remapController の isRename 分岐に bookmarkStore.noteRenamed を追加\n3. ViewerToolbarController に bookmarkItemIdentifier・makeBookmarkToolbarItem・updateBookmarkToolbarItem を追加し、onContentReloaded で更新\n4. ViewerWindowController に toggleBookmark(_:)・isBookmarked・validateMenuItem 分岐を追加\n5. MainMenuBuilder の View メニューに Bookmark 項目(⌘D、衝突なしを確認済み)を追加\n6. Localizable.xcstrings に menu.view.addBookmark/removeBookmark を追加(en/ja)\n7. テスト追加・全体テスト・lint確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 458件全通過、swiftlint新規違反なし、l10n(en/ja)欠落なしを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツールバーにbookmarkItemIdentifier(bookmark/bookmark.fill・controlAccentColorトグル)、View メニューにBookmark項目(⌘D)を追加。ファイル切替時のonContentReloadedフックで両方とも自動更新。ViewerWindowControllerToolbarTests・MainMenuBuilderTests・ViewerWindowControllerTestsに検証テストを追加し、swift test 458件全通過・swiftlint新規違反なしで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
