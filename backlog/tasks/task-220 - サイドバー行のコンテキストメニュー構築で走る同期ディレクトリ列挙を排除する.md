---
id: TASK-220
title: サイドバー行のコンテキストメニュー構築で走る同期ディレクトリ列挙を排除する
status: To Do
assignee: []
created_date: '2026-07-31 09:13'
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
- [ ] #1 サイドバー行の body 評価・contextMenu 構築時に MainActor 上でディレクトリ列挙・stat が実行されない
- [ ] #2 「新しいウィンドウで開く」の disabled 判定と実行の挙動が従来と同等である
- [ ] #3 判定ロジックにユニットテストがある
<!-- AC:END -->
