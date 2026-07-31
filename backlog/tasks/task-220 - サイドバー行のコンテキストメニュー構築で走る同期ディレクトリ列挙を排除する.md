---
id: TASK-220
title: サイドバー行のコンテキストメニュー構築で走る同期ディレクトリ列挙を排除する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:13'
updated_date: '2026-07-31 09:28'
labels:
  - refactor
  - performance
dependencies: []
priority: high
type: task
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView.openInNewWindowButton (BefoldApp/befold/Viewer/FileListView.swift:172,174) が DirectoryLister.containsSupportedFile → FileManager.contentsOfDirectory + stat を MainActor 上で同期実行している。contextMenu の内容は行の body 評価時に組み立てられるため、可視フォルダー行ごとに 1 回のディレクトリ列挙が走り、windowDidBecomeKey ごとの refreshFileList で発火頻度も高い。DirectoryLister 自身が「本番は非同期版のみ」とコメントしているのにこの経路だけ同期版が残っている。disabled 判定は FileListEntry への事前計算か .task による非同期埋めに、Button action 内の firstSupportedFile も非同期化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー行の body 評価・contextMenu 構築時に MainActor 上でディレクトリ列挙・stat が実行されない
- [x] #2 「新しいウィンドウで開く」の disabled 判定と実行の挙動が従来と同等である
- [x] #3 判定ロジックにユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListEntry に containsSupportedFile: Bool を追加(既定 false、既存呼び出し箇所は無変更で通す)
2. DirectoryLister.buildEntries でフォルダーエントリ構築時に containsSupportedFile(in:) を事前計算して埋め込む(この関数は既に nonisolated async の listEntriesAsync から呼ばれる唯一の生成ロジック)
3. FileListView.openInNewWindowButton の disabled 判定を entry.containsSupportedFile 参照に変更し、Button action 内の firstSupportedFile 呼び出しは Task { await Task.detached { ... }.value } で非同期化する
4. DirectoryListerTests にフォルダーエントリの containsSupportedFile 事前計算を検証するテストを追加する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。DirectoryLister.buildEntries(既に MainActor 外で実行される listEntriesAsync が呼ぶ唯一の生成ロジック)でフォルダーエントリ構築時に containsSupportedFile を事前計算するよう変更し、FileListView 側は entry.containsSupportedFile を参照するだけにした(専用サブビュー・@State は不要、既存の非同期一覧構築に処理を寄せる単純化)。ボタン実行時の firstSupportedFile 呼び出しも Task.detached で非同期化。DirectoryListerTests にテスト追加。swift build / swift test --skip Integration --skip FileWatcherTests は 878 件全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListEntry に containsSupportedFile: Bool(既定 false)を追加し、DirectoryLister.buildEntries(listEntriesAsync が呼ぶ非同期・MainActor 外の唯一の生成ロジック)でフォルダーエントリ構築時に事前計算するよう変更。FileListView.openInNewWindowButton は entry.containsSupportedFile を参照するだけになり、body/contextMenu 構築時の同期ディレクトリ列挙・stat が消えた。Button 実行時の firstSupportedFile 呼び出しも Task.detached で非同期化。検証: DirectoryListerTests に事前計算を検証するテストを追加、swift build 成功、swift test --skip Integration --skip FileWatcherTests で 878 件全て成功(FileListViewTests/FileListEntryTests/PreviewTargetResolverTests など既存回帰も含む)。
<!-- SECTION:FINAL_SUMMARY:END -->
