---
id: TASK-918
title: 空タブのサイドバーでファイルを選ぶと、キーボードのフォーカスがサイドバーから外れる
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
labels:
  - sidebar
  - tabs
  - keyboard
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController+Sidebar.swift
  - BefoldApp/befold/Viewer/FileListView.swift
priority: medium
type: bug
ordinal: 884000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。矢印キーや j/k で空タブのサイドバーを操作してファイルを選ぶと、文書タブへ置き換わった後にキー操作が続かない。文書タブでは TASK-581 で「サイドバー由来のオープンはフォーカスをサイドバーに残す」としており、続けて次のファイルへ移れる。

裏付け（コード参照・実機未確認）: `FileListView` の `tableFocuser.focus()` は閉じる空タブの `FileListModel` に対して走る。`BlankTabWindowController.fileListDidSelectFile` から新しい `ViewerWindowController` の表へフォーカスを渡す経路は無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 空タブのサイドバーをキーボードで操作して開いた文書タブで、サイドバーの表がフォーカスを持つ
- [ ] #2 続けて矢印キーを押すと次の行へ移り、そのファイルが表示される
- [ ] #3 Quick Open など本文へフォーカスを置く経路の動作は変わらない
<!-- AC:END -->
