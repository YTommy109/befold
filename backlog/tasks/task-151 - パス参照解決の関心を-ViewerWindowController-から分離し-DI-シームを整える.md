---
id: TASK-151
title: パス参照解決の関心を ViewerWindowController から分離し DI シームを整える
status: To Do
assignee: []
created_date: '2026-07-25 11:31'
labels:
  - path-reference
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI 層レビュー指摘。(1) ViewerWindowController.swift が 703 行（warning 閾値 400 行超過、本機能で +43 行悪化）。パス参照解決の関心一式（gitFileIndex / pathResolver / handleOpenReference / resolveReferences / warm 呼び出し×2）は SidebarNavigator の流儀で ReferenceResolutionCoordinator 等へ切り出せるまとまり。(2) init が具象 GitCommandFileIndex を受ける（warm がプロトコル GitFileIndexing 外にあるため）。注入省略時の unit テストでも init 時の warm 経由で実 git サブプロセスが背景起動し、Unit/Integration 分離規約と摩擦。(3) ViewerWindowManager.swift L26 の `private let gitFileIndex = GitCommandFileIndex()` は注入シームがなく、規約「新しい外部依存はデフォルト引数付きイニシャライザ注入」に違反。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パス参照解決の関心一式が凝集単位として ViewerWindowController から分離されている
- [ ] #2 GitFileIndexing プロトコルに warm を収載し、コントローラ側の依存を any GitFileIndexing にする
- [ ] #3 ViewerWindowManager の gitFileIndex がデフォルト引数付きイニシャライザ注入になっている
- [ ] #4 unit テストで実 git サブプロセスが起動しない（スタブ注入経路がある）
<!-- AC:END -->
