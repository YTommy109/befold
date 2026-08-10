---
id: TASK-361.3
title: サイドバーの非同期列挙の世代ガードを展開単位へ分割する
status: To Do
assignee: []
created_date: '2026-08-10 01:57'
updated_date: '2026-08-10 02:08'
labels: []
dependencies:
  - TASK-361.1
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 657000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダを展開するたびに発生する非同期列挙が、サイドバー全体で 1 つしかない世代ガードと競合しないようにする。

## 現状（実測 2026-08-10、HEAD a3202d4）

- App/SidebarNavigator.swift:222 performListing が、:230-233 で listingGeneration / gitStatusGeneration をインクリメントし、:240 の `guard generation == self.listingGeneration` で古い結果を捨てる
- この世代はディレクトリ単位ではなく**サイドバー全体で 1 つ**。複数フォルダを同時に展開すると、後から始まった列挙が先行分を無効化してしまう

## 方針

- 世代ガードをディレクトリ単位（またはリクエスト単位）へ分割し、異なるフォルダの列挙が互いを無効化しないようにする
- ルート切り替え（navigateToFolder）時は、従来どおり全体を無効化できること
- 展開中フォルダの列挙が未完了の間の表示（プレースホルダの有無）を決める

## 制約

- 着手前に /review-design を 1 回回すこと
- 既存テスト SidebarNavigatorGenerationTests(2) / ListingCoherenceTests(5) / FolderNavigationTests(11) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 複数フォルダの列挙が同時に進行しても、互いの結果を破棄しない
- [ ] #2 ルート切り替え時は進行中の列挙がすべて無効化される
- [ ] #3 世代ガードを全体 1 つへ戻したら落ちるテストがある
- [ ] #4 展開の子リストが空のとき、「空フォルダ」「列挙失敗」「未到着」が区別できる（gitStatus の「空 != nil」と同型。先例: FileListModel.swift:146-152 / TASK-285）
- [ ] #5 フォルダ行 1 件ごとに走る containsSupportedFile(in:)（DirectoryLister.swift:83、内部でディレクトリ列挙）のコスト上限が決まっており、展開数に比例して MainActor を塞がない
- [ ] #6 展開単位の世代ガードに、開始時の無効化と着地時の一致確認の両方がある（既存の 2 系統 SidebarNavigator.performListing:222-258 / FileListModel.applyGitStatus:188-200 はディレクトリ 1 つ単位で、そのままでは足りない）
<!-- AC:END -->
