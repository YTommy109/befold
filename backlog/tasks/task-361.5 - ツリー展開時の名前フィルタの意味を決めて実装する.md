---
id: TASK-361.5
title: ツリー展開時の名前フィルタの意味を決めて実装する
status: To Do
assignee: []
created_date: '2026-08-10 01:58'
labels: []
dependencies:
  - TASK-361.4
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 659000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ツリー展開時の名前フィルタの意味を決めて実装する。TASK-361 で「決めること」として残された論点。

## 現状（実測 2026-08-10、HEAD a3202d4）

- Viewer/FileListFilter.swift:27 apply(to:in:) は「directory 直下の一覧」に対する filter のみ（ドキュメントコメントにも明記）。子孫を残す・一致する子を持つ祖先を保つといったツリー考慮は無い
- Viewer/FileListModel.swift:269 visibleEntries が listFilter.apply(to: entries, in: entriesDirectory)

## 決めること（いずれか）

- A: 展開済みの階層だけを絞る（現在の意味をそのまま各階層へ適用）
- B: 一致する子を持つ祖先フォルダを残す（未展開のフォルダも一致すれば自動展開する／しない、も併せて決める）

B は未展開フォルダの再帰列挙が要るため、コストと挙動（大きなツリーでの応答性）を実測してから決めること。

## 制約

- 着手前に /review-design を 1 回回すこと
- 既存テスト FileListModelFilterTests(18) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツリー展開時の名前フィルタの意味が決まり、タスクの Implementation Notes に採用理由とともに記録されている
- [ ] #2 決めた意味がテストで検証されている
- [ ] #3 ドリルダウン時のフィルタ挙動と既存テスト（FileListModelFilterTests 18 件）が壊れていない
<!-- AC:END -->
