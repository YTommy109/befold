---
id: TASK-69
title: DirectoryLister の同期ディレクトリ列挙をメインスレッドから外す
status: To Do
assignee: []
created_date: '2026-07-19 05:31'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-19 の PR #262 コードレビュー時のスレッド独立性調査で特定。DirectoryLister.listEntries / sortedContents（befold/Viewer/DirectoryLister.swift:90-115）は同期 FileManager 列挙＋各エントリの resourceValues 取得で、呼び出しは全て MainActor 同期（windowDidBecomeKey:555 でウィンドウがキーになるたび、SidebarNavigator.refreshFileList / navigateToFolder、ViewerWindowController.init:103 等）。巨大ディレクトリではキー化やフォルダ移動のたびにメインスレッドを同期ブロックし体感悪化の可能性がある。改善方向: 列挙を Task でメイン外実行し結果だけメインで反映する、または少なくとも windowDidBecomeKey の無条件 refresh を差分/デバウンス化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 大きなディレクトリの列挙がメインスレッドをブロックしない（列挙はメイン外で実行される）
- [ ] #2 サイドバーの表示内容・選択状態・ソート順は従来と同一
- [ ] #3 既存のサイドバー・DirectoryLister 系テストが通過する
<!-- AC:END -->
