---
id: TASK-221
title: 「パスをコピー」の git ルート解決を MainActor 同期呼び出しから外す
status: To Do
assignee: []
created_date: '2026-07-31 09:13'
labels:
  - refactor
  - performance
dependencies: []
priority: high
type: task
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController.swift:285-287 の resolveGitRoot closure が GitCommandFileIndex.repositoryRoot を MainActor 上で同期呼び出ししている。キャッシュ未命中時は共有 NSLock + git rev-parse subprocess を最大 10 秒（+ terminationGrace 5 秒）待つため、サイドバーの「パスをコピー」(FileListView.copyPath) で UI が停止しうる。同ファイル :157-159 の SidebarNavigator 向けは Task.detached 済みで、この経路だけ取り残されている。closure を async 化するか、非同期解決済みの FileListModel.baseDirectory (BaseDirectoryDescriptor) を使って closure 自体を削除する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パスをコピー実行時に MainActor 上で git subprocess やロック待ちが発生しない
- [ ] #2 コピー結果（git ルート相対パス／絶対パスのフォールバック）が従来と同等である
<!-- AC:END -->
