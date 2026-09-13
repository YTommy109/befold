---
id: TASK-620.2
title: Bookmark Editor の行に操作メニューを開く ⋯ ボタンを付ける
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-13 11:42'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 812000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
管理パネルの行の操作（ブックマーク行: 別名・フォルダーへ移動・削除、フォルダー行: 改名・新規フォルダー・削除）は右クリックの `contextMenu` にしか無く、使う人がその存在に気づけない。サイドバーのヘッダー右端にある ⋯（`SidebarHeaderControls` の overflow、`ellipsis.circle`）のように、目に見える入口を置きたい。

右クリックメニューは残す（慣れた人の近道として）。2 つの入口の中身が別々に定義されると片方だけ項目が増える・並びがずれる形で割れるので、同じ定義から作ること（CLAUDE.md「決めたことには、破れたら落ちるものを付ける」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマーク行とフォルダー行の右端に ⋯ ボタンがあり、クリックで操作メニューが開く
- [ ] #2 ⋯ から開くメニューと右クリックメニューの項目・並び・有効/無効が一致する
- [ ] #3 ⋯ ボタンのクリックで行の選択・ダブルクリックで開く動作が誤って起きない
- [ ] #4 ⋯ ボタンに VoiceOver で読み上げられるラベルと help が付いている
<!-- AC:END -->
