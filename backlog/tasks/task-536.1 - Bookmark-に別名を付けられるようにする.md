---
id: TASK-536.1
title: Bookmark に別名を付けられるようにする
status: To Do
assignee: []
created_date: '2026-08-21 07:27'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 777000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在ブックマークはパス文字列のみを保持し、表示名は常に `lastPathComponent` から算出される（`BookmarksMenuController.swift:29-44`）。任意の別名（表示名）を設定・保存できるようにする。

データモデル（`BookmarkStore` もしくは `PathListDefaults` 相当）に、ファイルパスと関連付けた表示名フィールドを追加する。既存の `noteRenamed(from:to:)`（`BookmarkStore.swift:56-58`、ファイルのリネーム・移動時にパスを追随させる仕組み）との整合を保つこと（パスは追随するが、ユーザーが設定した別名は保持される必要がある）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマークごとに別名を設定できる
- [ ] #2 別名未設定のブックマークは従来どおりファイル名で表示される
- [ ] #3 別名を設定したブックマークは File > Bookmarks サブメニュー等の一覧表示に別名が反映される
- [ ] #4 ファイルのリネーム・移動時、パスが更新されても設定済みの別名は保持される
- [ ] #5 別名の保存・読み込み・リネーム時の保持をユニットテストで担保する
<!-- AC:END -->
