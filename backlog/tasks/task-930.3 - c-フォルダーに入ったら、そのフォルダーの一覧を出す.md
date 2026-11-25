---
id: TASK-930.3
title: (c) フォルダーに入ったら、そのフォルダーの一覧を出す
status: To Do
assignee: []
created_date: '2026-11-25T00:12:54Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: feature
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 5。リスト表示でフォルダー D に入る（ダブルクリック・→・パスメニュー・上へ移動）と、いまは D の一覧ではなく、記憶した選択か先頭の項目を自動で選ぶ（SidebarNavigator.navigateToFolder）。その結果、ファイルが開く・サブフォルダーの一覧が出る・空タブがファイルに置き換わる。利用者がフォルダーを選んだ意図どおり、D の一覧を出すようユーザーが決めた（2026-11-25）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リスト表示でフォルダー D に入ると、本文に D の一覧が出て、ファイルの切り替えは起きない
- [ ] #2 上へ移動したときは、移動先のフォルダーの一覧が出る（直前にいた子フォルダーの一覧ではない）
- [ ] #3 空タブでフォルダーに入っても、空タブがファイルに置き換わらない
- [ ] #4 選択の記憶（SidebarSelectionMemory）が不要になれば撤去し、残すならサイドバーの強調にだけ使う。どちらにしたかを Notes に残す
- [ ] #5 CHANGELOG に載せる利用者向けの変更として、Notes に一文で記録する
<!-- AC:END -->
