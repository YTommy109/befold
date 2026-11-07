---
id: TASK-919
title: 空タブを文書タブへ置き換えるときに落ちる窓の状態を決める
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/SidebarInheritance.swift
documentation:
  - docs/dev/viewer-ui.md
priority: low
type: bug
ordinal: 885000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。`SidebarInheritance.Seed` が運ぶのは一覧・展開・開閉だけなので、空タブで操作した比較基準・戻る/進む履歴・`rootDirectory` は置き換えで失われる。比較基準を変えてからファイルを選ぶと既定値へ戻り、git のバッジが変わる。フォルダを移動してからファイルを選ぶと、文書タブの「戻る」で移動前のフォルダへ戻れない。docs/dev/viewer-ui.md は比較基準が既定値から「始める」ことだけを決めていて、利用者が変えた値を置き換えで捨てるかどうかは決めていない。

裏付け（コード参照・実機未確認）: `BlankTabWindowController.comparisonTarget` の読み手は空タブの内側だけで、`ViewerWindowManager.makeController` は `ViewerStore` の既定値で文書タブを作る。履歴は `SidebarNavigator` ごとの `SidebarHistoryController` が持つ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 比較基準・履歴・rootDirectory のそれぞれについて、引き継ぐか捨てるかが決まり docs/dev/viewer-ui.md に書かれている
- [ ] #2 引き継ぐと決めたものは、置き換えの後も保たれることを自動テストで確認している
<!-- AC:END -->
