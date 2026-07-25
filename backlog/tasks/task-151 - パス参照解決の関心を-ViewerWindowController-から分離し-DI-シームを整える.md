---
id: TASK-151
title: パス参照解決の関心を ViewerWindowController から分離し DI シームを整える
status: In Progress
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:31'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFileIndexing に warm(forFileAt:) を追加（既定は no-op 拡張。warm は最適化ヒントで必須挙動ではないため）
2. ReferenceResolutionHost（weak 参照プロトコル）+ ReferenceResolutionCoordinator を新設し、SidebarNavigator / SidebarNavigatorHost の流儀に揃える。移す責務: gitIndex 保持・resolver・warm・handleOpenReference・resolveReferences
3. ViewerWindowController の依存を any GitFileIndexing に変え、既定は git を起動しない DisabledGitFileIndex にする（現行の既定 GitCommandFileIndex() は、注入忘れ時に共有されない実索引が静かに生まれる＝規約が禁じる形でもある）
4. ViewerWindowManager の gitFileIndex をデフォルト引数付きイニシャライザ注入にする
5. 「Manager が生成するコントローラへ共有索引を注入している」ことをテストで固定し、既定を no-op にしたことで本番の配線が黙って外れないようにする
6. 既存テスト（controller.pathResolver 差し替え 3 件）をコーディネータ経由へ追従
<!-- SECTION:PLAN:END -->
