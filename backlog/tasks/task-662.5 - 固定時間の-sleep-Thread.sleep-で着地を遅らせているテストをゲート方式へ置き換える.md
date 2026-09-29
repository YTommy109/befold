---
id: TASK-662.5
title: 固定時間の sleep / Thread.sleep で着地を遅らせているテストをゲート方式へ置き換える
status: To Do
assignee: []
created_date: '2026-09-29 04:30'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: medium
ordinal: 861000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「遅れて着地する」「メインキューが流れる」ことを固定時間の sleep で作っているテストがある。壁時計を確実に消費し、`Thread.sleep` はスレッドも塞ぐ（協調スレッドプール上なら並列実行全体を止めうる）。既存の `BlockingGate` / `AsyncGate` やメインキューの 1 周待ちで、時間に依存せず同じことを検証できる。

## 該当
- `ViewerWindowControllerDiffPendingTests.keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate`: `SlowRootGitFileIndex(delay: 0.5)` の `Thread.sleep`
- `ViewerWindowControllerDiffTests.refreshDiffDoesNotBlockMainActorOnRootResolution`: 0.5 秒の `Thread.sleep` が最大 2 回。`refreshDiff()` の直後にゲートを開く形にすれば判定（elapsed < delay/2）はそのままで壁時計ゼロ
- PDF 系の 200ms 固定: `PDFSurfaceRenderingTests`（`settleLayout` と `MainQueueDrainTests`）、`PDFSurfaceRotationTests`、`PDFSurfacePositionTests`。目印ブロックで `DispatchQueue.main` を 1 周させる方式を `MainQueueDrainTests` で確かめてから置き換える（PDFKit が asyncAfter を積むなら 1 周では足りない。未確認）
- `PDFFindModelTests.scannedPDFYieldsNoMatches`: 300ms 固定。`!model.isSearching` を待てば 0 件でも待てる（`restartSearch` で同期に true、`handleEnd` で false）
- `GitCommandFileIndexConcurrencyTests.concurrentCallsForSameRootEnumerateOnce`: `SlowRepository(enumerationDelay: 0.2)` の `Thread.sleep`。同ファイルの `BlockingRepository` 方式へ
- `SequentialOpenerTests`: 30/10/1ms の `Task.sleep` で完了順を作っている。AsyncGate で順序を明示する
- `BlockingWaitTests.openReleasesAllPendingWaiters`: 200ms 固定。待機スレッドが wait に入った数を数えてから検証する
- `DebouncerTests`: settlePeriod 0.3 秒 ×2（「発火しない」否定検証）。`TestClock` 相当のキュー差し替えができるなら待たずに測れる。優先度低
- `BookmarkManagerViewDropTests`: 独自 `waitUntil` が期限切れでも `Issue.record` せず黙って 2 秒使う（正しさの問題でもある）。共有の `waitUntilOnMainActor` へ
- `BefoldCLIIntegrationTests.runCLI`: `Thread.sleep(0.01)` のビジーループでプロセス終了を待つ。`terminationHandler` + continuation へ
- ついで: `DiffTestSupport.swift` の `RecordingDiffReader(delay:)` は非ゼロ delay の呼び出し元が 0 件（`rg 'RecordingDiffReader\([^)]*delay'`）。`Thread.sleep` 分岐ごと消せる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記の固定 sleep / Thread.sleep が、ゲート・条件待ち・メインキュー 1 周待ちのいずれかに置き換わっている（残すものは理由を Notes に）
- [ ] #2 BookmarkManagerViewDropTests の待機が期限切れを失敗として記録する
- [ ] #3 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [ ] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->
