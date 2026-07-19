---
id: TASK-69
title: DirectoryLister の同期ディレクトリ列挙をメインスレッドから外す
status: Done
assignee: []
created_date: '2026-07-19 05:31'
updated_date: '2026-07-19 06:10'
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
- [x] #1 大きなディレクトリの列挙がメインスレッドをブロックしない（列挙はメイン外で実行される）
- [x] #2 サイドバーの表示内容・選択状態・ソート順は従来と同一
- [x] #3 既存のサイドバー・DirectoryLister 系テストが通過する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
メイン側で main worktree に取り込み検証: swift build 成功、swift test 全439件pass(新規/更新テスト含む)、swiftlint --strict は該当ファイルで baseline(変更前)と同数7件(いずれもpre-existing、新規違反なし)。ViewerWindowController.init の初回読み込みは1回限りの同期処理のためスコープ外(backlogに理由記録済み)。コミット 5ac4e83 で確定。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DirectoryLister に listEntriesAsync を追加し、ViewerLoadPipeline.load と同様の nonisolated async パターンでメインスレッド外へ列挙処理を退避。SidebarNavigator は listingGeneration で世代管理した Task 経由で結果を反映し、古いリクエストは破棄する。表示内容・選択状態・ソート順は不変。回帰テスト(rapidNavigateToFolderDiscardsStaleResult 等)追加、swift test 439件全pass。コミット 5ac4e83。
<!-- SECTION:FINAL_SUMMARY:END -->
