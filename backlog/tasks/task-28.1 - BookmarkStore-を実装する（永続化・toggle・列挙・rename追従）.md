---
id: TASK-28.1
title: BookmarkStore を実装する（永続化・toggle・列挙・rename追従）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 11:20'
updated_date: '2026-07-19 08:23'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: medium
ordinal: 500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentDocumentsStore と同型の BookmarkStore を新設し、AppDelegate → ViewerWindowManager → ViewerWindowController の経路で注入する。永続化は UserDefaults キー 'BookmarkedPaths' に normalizedPathKey の配列として保存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 isBookmarked(_:) がブックマーク有無を正しく返す
- [x] #2 toggle(_:) でブックマークの追加/削除ができ、UserDefaults に永続化される
- [x] #3 bookmarkedURLs() がブックマーク済み URL を返す
- [x] #4 ファイルリネーム時に noteRenamed(from:to:) でブックマーク状態が新パスに引き継がれる
- [x] #5 BookmarkStoreTests でインスタンス跨ぎの永続化と toggle/rename 追従を検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarkStore.swift を RecentDocumentsStore と同型で新設（UserDefaults key: BookmarkedPaths, 上限なし, isBookmarked/toggle/bookmarkedURLs/noteRenamed）\n2. BookmarkStoreTests.swift を RecentDocumentsStoreTests と同パターンで追加（toggle add/remove, isBookmarked, 永続化, noteRenamed）\n3. swift test で確認\n4. commit
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BookmarkStore.swift を RecentDocumentsStore と同型で新設(UserDefaults key: BookmarkedPaths, 上限なし)。BookmarkStoreTests.swift を追加(7テスト)。swift test 全455件通過、swiftlint 新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BookmarkStore(isBookmarked/toggle/bookmarkedURLs/noteRenamed)を新設し、BookmarkStoreTestsで永続化・toggle・rename追従を検証。swift test 455件全通過、swiftlintに新規違反なしで確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
