---
id: TASK-29.6
title: 検索の DOM 全量構築を廃止し表示範囲内検索にする
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
labels: []
dependencies:
  - TASK-29.3
parent_task_id: TASK-29
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loadAllLinesForSearch の仕組み（JS→Swift→全チャンク DOM 化→フリーズ）を削除し、表示済み DOM のみを検索する方式に変更する。切り詰め中は検索件数に「表示範囲内」と表示する。Swift 側の String 検索への完全移行は後続タスクとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWebView から loadAllLinesForSearch メッセージハンドラが削除される
- [ ] #2 ViewerBridge から loadAllLinesForSearchMessageName / allLinesLoadedScript が削除される
- [ ] #3 viewer.html/viewer.js から _mmdOnAllLinesLoaded / _mmdSetFindLoading が削除される
- [ ] #4 Cmd+F が常に表示済み DOM のみを検索する
- [ ] #5 切り詰め中は検索件数に「表示範囲内」の表示が付く
- [ ] #6 検索入力が無効化されたままにならない（TASK-24 解消）
<!-- AC:END -->
