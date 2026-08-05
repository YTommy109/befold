---
id: TASK-221
title: 「パスをコピー」の git ルート解決を MainActor 同期呼び出しから外す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:13'
updated_date: '2026-07-31 09:34'
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
- [x] #1 パスをコピー実行時に MainActor 上で git subprocess やロック待ちが発生しない
- [x] #2 コピー結果（git ルート相対パス／絶対パスのフォールバック）が従来と同等である
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListView から resolveGitRoot closure(同期呼び出し)を削除し、既に SidebarNavigator がメイン外で解決済みの model.baseDirectory(BaseDirectoryDescriptor, gitRoot ?? workspaceRoot の単一情報源)を copyPath の基準に使う
2. PathRelativizer.relativePath(workspaceRoot:gitRoot:) は relativePath(relativeTo: gitRoot ?? workspaceRoot) の薄いラッパーなので、copyPath 側は relativePath(of:relativeTo: model.baseDirectory?.url ?? model.rootDirectory) を直接呼べば同じ規則になる(closure 自体を削除)
3. ViewerWindowController.swift:285-287 の resolveGitRoot 引数(gitFileIndex.repositoryRoot(forFileAt:) の同期呼び出し)を削除する
4. FileListViewTests に relativePathForCopy(internal 化した抽出関数)の単体テストを追加する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査で判明: BaseDirectoryDescriptor は既に PathRelativizer と同じ規則(gitRoot ?? workspaceRoot)で SidebarNavigator がメイン外で解決済み(doc コメントにも「表示とコピー結果を一致させるためこの1か所に規則を寄せる」と明記)。resolveGitRoot closure を FileListView から削除し model.baseDirectory を直接使う単純化で対応(closure 化・非同期化ではなく削除)。ViewerWindowController の gitFileIndex.repositoryRoot(forFileAt:) 同期呼び出しも削除。relativePathForCopy を internal 抽出して FileListViewTests に単体テスト2件追加(git ルート基準/未解決時 rootDirectory フォールバック)。swift build / swift test --skip Integration --skip FileWatcherTests は 880 件全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListView から resolveGitRoot closure(MainActor 上で git rev-parse subprocess を同期待ちしていた経路)を完全に削除し、SidebarNavigator がメイン外で解決済みの model.baseDirectory(BaseDirectoryDescriptor)を copyPath の基準に使うよう単純化した。ViewerWindowController.swift の gitFileIndex.repositoryRoot(forFileAt:) 呼び出しも削除。パスをコピー実行時に git subprocess・ロック待ちは一切発生しない(closure 自体が無いため)。検証: relativePathForCopy を internal 抽出して FileListViewTests に単体テスト2件(git ルート基準/未解決時フォールバック)を追加、swift build 成功、swift test --skip Integration --skip FileWatcherTests で 880 件全て成功。
<!-- SECTION:FINAL_SUMMARY:END -->
