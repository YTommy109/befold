---
id: TASK-536.2
title: Bookmark を管理 UI から削除できるようにする
status: To Do
assignee: []
created_date: '2026-08-21 07:27'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 778000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在、存在するファイルのブックマークを外す手段は、そのファイルを開いてツールバー／View メニューでトグルするか、ファイルが見つからない場合に「Remove from Bookmarks」（`FileNotFoundUI.swift:16-42`）や一括の Missing Bookmarks 削除（`MissingBookmarksPruner.swift`、`MissingBookmarksAlerts.swift`）を使うかに限られる。ブックマーク一覧（管理 UI）側から、対象ファイルを開かずに個々のブックマークを直接削除できる導線が無い。

ブックマーク一覧・管理 UI 上で、個々のブックマークを選択して削除できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマーク一覧（管理 UI）から、対象ファイルを開かずに個々のブックマークを削除できる
- [ ] #2 削除は BookmarkStore 経由で即座に永続化される
- [ ] #3 既存の Missing Bookmarks 系の削除導線（MissingBookmarksPruner／FileNotFoundUI）と重複せず整合する
<!-- AC:END -->
