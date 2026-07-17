---
id: TASK-28.1
title: BookmarkStore を実装する（永続化・toggle・列挙・rename追従）
status: To Do
assignee: []
created_date: '2026-07-16 11:20'
updated_date: '2026-07-16 12:16'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: low
ordinal: 9410
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentDocumentsStore と同型の BookmarkStore を新設し、AppDelegate → ViewerWindowManager → ViewerWindowController の経路で注入する。永続化は UserDefaults キー 'BookmarkedPaths' に normalizedPathKey の配列として保存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 isBookmarked(_:) がブックマーク有無を正しく返す
- [ ] #2 toggle(_:) でブックマークの追加/削除ができ、UserDefaults に永続化される
- [ ] #3 bookmarkedURLs() がブックマーク済み URL を返す
- [ ] #4 ファイルリネーム時に noteRenamed(from:to:) でブックマーク状態が新パスに引き継がれる
- [ ] #5 BookmarkStoreTests でインスタンス跨ぎの永続化と toggle/rename 追従を検証する
<!-- AC:END -->
