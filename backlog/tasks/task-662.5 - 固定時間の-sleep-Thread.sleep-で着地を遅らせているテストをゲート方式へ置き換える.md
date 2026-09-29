---
id: TASK-662.5
title: 固定時間の sleep / Thread.sleep で着地を遅らせているテストをゲート方式へ置き換える
status: Done
assignee: []
created_date: '2026-09-29 04:30'
updated_date: '2026-09-29 07:30'
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
- [x] #1 上記の固定 sleep / Thread.sleep が、ゲート・条件待ち・メインキュー 1 周待ちのいずれかに置き換わっている（残すものは理由を Notes に）
- [x] #2 BookmarkManagerViewDropTests の待機が期限切れを失敗として記録する
- [x] #3 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [x] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 各 sleep をゲート（BlockingGate/AsyncGate）・完了条件待ち・メインキュー 1 周待ちへ置き換える
2. 置き換えたテストは、守っている修正を一時的に戻して落ちることを実測する
3. 変更前後で対象スイート（--filter 直列）と全体 swift test の wall を測る
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 置き換え結果（すべて置き換え済み。残したものは無い）
- DiffPending.keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate: BlockingGate。準備が解決以外（loadTask / diffRefreshTask）を待ち終えてから開く。settleDiffTestController の awaitSettled を外すと baseDirectory != nil で落ちることを実測
- DiffTests.refreshDiffDoesNotBlockMainActorOnRootResolution: **元のテストは空振りしていた**（差分表示でない状態で refreshDiff を呼んでおり、isDiffShown ガードで即 return）。presentDocument で差分表示にしてから索引に閉じたゲートを渡し、refreshDiff を呼ぶ形へ直した。refresh() の中に repositoryRoot の同期呼び出しを足すと、ゲート待ちが上限に達して落ちることを実測
- PDF の 200ms（settleLayout / MainQueueDrainTests / Rotation / Position）: drainMainQueue()（BefoldTestSupport へ新設。4 ファイルにあった同じ private ヘルパーを集約）。TASK-572 の回帰（rotate が main.async で倍率を入れ直す形）を注入すると switchingToRotatedFileKeepsInitialZoom が 1 周待ちで落ちることを実測。keepsFitAfterRotation は待ちなしでも通る（待ちが無くても検証は成立する）。上限: asyncAfter で遅らせたブロックは 1 周待ちでは拾えない
- PDFFindModelTests: scannedPDF は isSearching の降下を待つ（直前に isSearching == true を前提として確認）。自前の waitForSearch（期限切れを記録しない 2 秒ループ）も共有ヘルパーへ
- GitCommandFileIndexConcurrencyTests: SlowRepository を撤去し BlockingRepository へ。呼び出しごとにディレクトリを分けてルート解決の回数を数え、4 本すべてがルートロックの手前まで来てから解放する。rootLocks のキーを呼び出しごとに一意にする（直列化を外す）と 5/5 で落ちることを実測
- SequentialOpenerTests: URL ごとの AsyncGate を後ろから開ける。TaskGroup による並行実装に差し替えると 3/3 で落ちることを実測
- BlockingGateTests.openReleasesAllPendingWaiters: wait 直前の入場数を数えてから検証。wait が素通しする実装に差し替えると落ちることを実測
- DebouncerTests: 0.3 秒の静穏待ちを、同じ直列キューへ後から積んだ目印（期限が先行予約より必ず遅い）へ置き換え。cancel を無効化・合一を無効化するとそれぞれ落ちることを実測
- BookmarkManagerViewDropTests: 自前の待機（期限切れを記録しない）を撤去し、共有の待機 + suite に testTimeLimit()。期限切れは .timeLimit の失敗として記録される
- BefoldCLIIntegrationTests.runCLI: 10ms のビジーループを terminationHandler + DispatchSemaphore（既存の waitOrRecordTimeout）へ。continuation にしなかったのは、同期のテストから呼ばれ、タイムアウトとの競合を async で書くと AsyncGate がキャンセルに応じないため終了待ちが外れないから
- ついで: RecordingDiffReader(delay:) を撤去（非ゼロの呼び出し元 0 件）

## 待機ヘルパーの選択で 1 回落とした
最初は MainActor 上の待ちに waitUntilOnMainActor（壁時計 10 秒）を使い、全体の並列実行で Bookmark 2 件・PDFFind・SequentialOpener の計 4 件が 21〜41 秒後に期限切れで落ちた（2 回とも同じ 4 件）。Waiting.swift の doc（TASK-354）どおり、壁時計予算は MainActor の順番待ちまで測ってしまう。旧来の自前ループは反復回数で数えていたため、混雑時は実質もっと長く待っていて表面化しなかった。MainActor へ届く結果の待ちは waitForDeliveryOnMainActor（予算なし・suite の testTimeLimit() で打ち切り）へ切り替え、3 回連続で緑。

## 計測（手元 / debug / 2026-09-29）
| 実行 | 変更前 | 変更後 |
|---|---|---|
| 対象 14 スイート --no-parallel --filter | 6.15 秒（+CLI 0.20） | 3.42〜3.86 秒（+CLI 0.04） |
| swift test（並列）全体 | 44.1 秒（real 46.1） | 40.3 / 39.1 / 40.3 秒（real 42.6 / 40.9 / 42.1） |
スイート別（直列）: DiffPending 1.77→0.69、DiffTests 1.00→1.14（空振りを直して提示の準備が入った分）、Debouncer 0.93→0.67、GitCommandFileIndexConcurrency 0.43→0.23、BlockingGate 0.32→0.11、PDFSurfaceRendering 0.32→0.10、Rotation 0.30→0.15、Position 0.24→0.07、MainQueueDrain 0.21→0.001、CLI 0.20→0.05
swiftlint: main とのベースライン差分で新規 0 件
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
固定 sleep / Thread.sleep を、ゲート・完了条件待ち・メインキュー 1 周待ちへ置き換えた（該当箇所は残さず全て）。置き換えた各テストは、守っている修正を一時的に戻して落ちることを実測した。その過程で、refreshDiffDoesNotBlockMainActorOnRootResolution が差分表示でない状態で呼んでいて空振りしていたのを見つけ、直した。対象スイートは直列で 6.15→約 3.4〜3.9 秒、全体の並列実行は 44.1→39〜40 秒。
<!-- SECTION:FINAL_SUMMARY:END -->
