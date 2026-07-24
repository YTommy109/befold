---
id: TASK-116.12
title: 実 FS 依存を注入経路へ配線し switch/rename/open/画像埋め込みテストをモック化する
status: To Do
assignee: []
created_date: '2026-07-24 11:27'
labels:
  - test
  - cleanup
  - refactor
dependencies: []
parent_task_id: TASK-116
priority: medium
ordinal: 108000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-116.10 で切り分けた結果、以下の製品コードが注入した fileReader を無視して実 FS を直接叩くため、当該テスト群が単独ではモック化できず ~IntegrationTests へリネームで暫定対応した。本タスクで配線を注入経路へ直し、それらのテストを再度 unit(モック)へ戻す。

## 配線の穴(TASK-116.10 調査で特定)
1. ViewerLoadPipeline.swift:116 が MarkdownImageEmbedder.shared(=DefaultFileReader 固定)を呼び、注入 fileReader を無視 → ViewerLoadPipeline の embed ウォームアップ / ViewerWebViewCoordinator の画像埋め込み系テストがモック不可
2. ViewerWindowController.swift:291(switchFile の DirectoryLister.isExistingFile) / :373(handleRename の fileExists) / ViewerWindowManager.swift:85(openViewer の fileExists) が注入 fileReader を通らない静的 FS 呼び出し → VWC本体の switch/rename 系, Toolbar, SourceMode, Manager, DisplayOverrides, SessionRestorer がモック不可

## 対応方針
存在確認・画像読込を store.fileReader(または注入クロージャ)経由へ変更。製品コード(ウィンドウ管理・ロードパイプライン)の refactor になるため TASK-116.10 から分離した。

## 完了後
TASK-116.10 で ~IntegrationTests にリネームしたテストのうち、配線修正でモック化可能になったものを unit(InMemoryFileReader)へ戻す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 製品コードの実 FS 存在確認(ViewerWindowController.swift:291/:373, ViewerWindowManager.swift:85)が注入 fileReader/クロージャ経由になっている
- [ ] #2 ViewerLoadPipeline の画像埋め込みウォームアップが注入 fileReader を共有する embedder を使う
- [ ] #3 TASK-116.10 で Integration リネームしたテストのうち配線修正でモック可能になったものが unit(InMemoryFileReader)へ戻っている
- [ ] #4 製品挙動(switch/rename/open/画像埋め込み)の回帰がなく swift test / jest が green
<!-- AC:END -->
