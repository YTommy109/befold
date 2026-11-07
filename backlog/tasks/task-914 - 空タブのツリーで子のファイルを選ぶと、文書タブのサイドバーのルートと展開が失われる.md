---
id: TASK-914
title: 空タブのツリーで子のファイルを選ぶと、文書タブのサイドバーのルートと展開が失われる
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowManager+OpenViewer.swift
  - BefoldApp/befold/App/SidebarInheritance.swift
documentation:
  - docs/dev/viewer-ui.md
priority: high
type: bug
ordinal: 880000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769（PR #764〜#768）のレビューで検出。空タブのツリー表示で、展開したサブフォルダ内のファイルを選ぶと、置き換わった文書タブのサイドバーがそのサブフォルダへルートごと移り、展開も消える。文書タブで同じ行を選んでも移動しないので（`SidebarNavigator.syncAfterSwitch` / TASK-465）、空タブを挟んだときだけ挙動が変わる。docs/dev/viewer-ui.md の「開閉・一覧・展開はそのまま文書タブへ渡る」と TASK-910 の AC #4 にも反する。

裏付け（コード参照・実機未確認）: `ViewerWindowAssembler.makeSidebarNavigator` は `currentDirectory` を `fileURL.deletingLastPathComponent()` にする。`SidebarListingSeed.canApply(to:)` は同じディレクトリしか通さず、`SidebarNavigator.attach` はその guard で return するので `tree.adoptExpansion` まで届かない。`seedReadsBlankTabSidebar` は採取した seed の中身しか見ていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 空タブのツリーで展開したフォルダ内のファイルを選ぶと、文書タブのサイドバーのルートと展開が選ぶ前と同じである
- [ ] #2 置き換わった文書タブで、そのファイルの行が選択されている
- [ ] #3 空タブから置き換えたときのルートと展開を確かめる自動テストがあり、修正を戻すと落ちる
<!-- AC:END -->
