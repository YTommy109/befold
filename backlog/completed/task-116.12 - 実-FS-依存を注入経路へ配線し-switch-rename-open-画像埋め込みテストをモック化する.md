---
id: TASK-116.12
title: 実 FS 依存を注入経路へ配線し switch/rename/open/画像埋め込みテストをモック化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 11:27'
updated_date: '2026-07-24 13:03'
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
- [x] #1 製品コードの実 FS 存在確認(ViewerWindowController.swift:291/:373, ViewerWindowManager.swift:85)が注入 fileReader/クロージャ経由になっている
- [x] #2 ViewerLoadPipeline の画像埋め込みウォームアップが注入 fileReader を共有する embedder を使う
- [x] #3 TASK-116.10 で Integration リネームしたテストのうち配線修正でモック可能になったものが unit(InMemoryFileReader)へ戻っている
- [x] #4 製品挙動(switch/rename/open/画像埋め込み)の回帰がなく swift test / jest が green
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 製品コード配線(AC#1/#2)
  - ViewerStore に fileExists(at:)/isExistingFile(at:) を追加し注入 fileReader へ委譲
  - VWC performFileSwitch/handleOpenReference の存在ガードを store 経由へ
  - VWM に fileReader を注入し openViewer の存在ガードを注入経由へ
  - ViewerLoadPipeline.load/loadFull と ViewerRenderer.renderableContent に imageEmbedder(既定 .shared)を注入口として追加
2. 明確に変換可能なテストを unit へ戻す(embedder 系)
  - ViewerLoadPipelineIntegrationTests → ViewerLoadPipelineTests(InMemoryFileReader + 注入 embedder)
  - ViewerWebViewCoordinatorIntegrationTests → unit(renderableContent に注入 embedder)
3. switch/rename/toolbar/sourcemode 系のうち、アサーションが実 FS 列挙(サイドバー・navigate)に依存しないものを InMemory store 注入で unit へ戻す
  - サイドバー entries / navigateToFolder / rename後の実列挙を検証するものは実 FS が対象そのものなので Integration 据え置き
4. swift test / jest green を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。

## 製品コード配線(AC#1/#2)
- ViewerStore に fileExists(at:)/isExistingFile(at:) を追加し注入 fileReader へ委譲
- ViewerWindowController: handleOpenReference の存在確認を store.isExistingFile(at:)、performFileSwitch を store.fileExists(at:) へ変更(静的 DirectoryLister 直呼びを排除)
- ViewerWindowManager: init に fileReader を注入、openViewer の存在ガードを fileReader.fileExists(at:) へ変更
- ViewerLoadPipeline.load/loadFull と ViewerRenderer.renderableContent に imageEmbedder(既定 .shared)を注入口として追加。本番は .shared 共有のままキャッシュ共有を維持

## テスト移行(AC#3)
配線でモック可能になった 20 件を InMemoryFileReader へ移行し unit へ復帰:
- 画像埋め込み: ViewerLoadPipelineIntegrationTests(2)→ViewerLoadPipelineTests、ViewerWebViewCoordinatorIntegrationTests(3)→ViewerWebViewCoordinatorTests。Integration 2ファイル削除
- ソース表示切替: SourceMode 2件 → unit
- ツールバー切替更新: Toolbar 3件 → unit
- switch/rename/history/handleOpenReference: VWC 10件 → unit。Integration には実サイドバー列挙・実 rename 再一覧・実フォルダーナビ依存の 11件を据え置き

## Integration 据え置き(ユーザー判断)
VWM/DisplayOverrides/SessionRestorer は openViewer が実コントローラ生成パイプライン(実 store/FileWatcher/サイドバー DirectoryLister 列挙)を踏むため、存在ガード配線だけでは unit 化不可。コントローラ生成の注入シーム新設は本タスク範囲外とし Integration 据え置き。該当ファイルの理由コメントを実態に合わせて更新。

## 検証
swift test 607 tests green / jest 203 tests green(JS 無変更)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
存在確認と画像埋め込みウォームアップを注入経路へ配線し(ViewerStore.fileExists/isExistingFile、VWM.fileReader、ViewerLoadPipeline/renderableContent の imageEmbedder)、TASK-116.10 で Integration リネームしたテストのうち配線で真にモック可能になった 20 件を InMemoryFileReader で unit へ復帰。VWM/DisplayOverrides/SessionRestorer は openViewer の実コントローラ生成パイプラインを踏むため据え置き(ユーザー判断)。swift test 607 / jest 203 green で回帰なしを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
