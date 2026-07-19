---
id: TASK-65
title: rename 伝搬を整理し現在ファイル URL の保持を一本化する
status: To Do
assignee: []
created_date: '2026-07-19 02:57'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rename イベントが FileWatcher（befold/FileWatching/FileWatcher.swift:163-174）→ ViewerStore.handleRename（befold/Viewer/ViewerStore.swift:164-169）→ onFileRenamed → ViewerWindowController.handleRename（befold/App/ViewerWindowController.swift:262-291）→ delegate didRenameFrom → ViewerWindowManager.remapController（befold/App/ViewerWindowManager.swift:140-163）と 6 ホップ中継されている。加えて現在ファイル URL が ViewerStore.filePath / pendingURL と ViewerWindowController.fileURL（:53）で二重管理されている。controller 側の fileURL を store 由来に一本化し、applyURLToWindow（:358-363）と per-file 状態の migrate 3 連発（zoom / sourceMode / scroll、:269-271）を単純化する。per-file 状態ストア束の 1 オブジェクト化（PathKeyedDictionary は共通化済み）も検討する。2026-07-19 のアーキテクチャレビュー（データフロー観点）で特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 現在ファイル URL を保持する場所が 1 箇所になっている
- [ ] #2 rename 時の per-file 状態（zoom / sourceMode / scroll）の移行が単一の呼び出しに集約されている
- [ ] #3 既存の rename 系テスト（FileWatcher / ViewerStore / ViewerWindowController）が通過する
<!-- AC:END -->
