---
id: TASK-622
title: CI の並列負荷で MainActor・協調プールの空きを待つテスト 2 件が間欠的に落ちる
status: To Do
assignee: []
created_date: '2026-09-13 16:17'
labels:
  - test
  - ci
dependencies: []
priority: high
ordinal: 816000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-13 の main push の CI（build-and-test / thread-sanitizer）と PR #665 の再実行 3 回で、ブックマーク UI の変更と無関係な次の 2 テストが交互に落ち、PR をマージできなくなった。

- ViewerRendererZoomProjectionTests「内容に差が無い更新では倍率を当てない」: 前提の描画済み状態を実描画（Task { @MainActor } → withBlockingWork → MainActor で再開）の着地待ちで作っており、waitUntilOnMainActor が 60 秒で予算切れする（main 2 回・#665 2 回）。
- ViewerStoreLoadStartTests.loadStartsWhileTheMainActorIsBusy: 協調プールで走る読み込み開始を、MainActor を塞いだまま 20 万回の空ループ（回数予算、数 ms）で待っており、プールが混むと開始前にループが尽きる（main 2 回）。

CI ログの Swift Testing の完了時刻を並べると、1 回の実行の中に 10〜24 秒どのテストも完了しない区間が複数あり、~1900 件の @MainActor テストでメインキュー・協調プールが詰まっている。TASK-607（実 WKWebView の didFinish がメインキューで後ろへ回される）と同じ型で、今回は WebKit ではなく Swift 側のホップで起きている。

同じ再実行では DistributedAckWaiterIntegrationTests / CLIRequestWireIntegrationTests（プロセス間通知の配送待ち）も 1 回落ちたが、配送経路が別なのでこのタスクの範囲外とする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 倍率を当てないテストが非同期の描画の着地を待たずに前提を作る（待機ヘルパーを使わない）
- [ ] #2 loadStartsWhileTheMainActorIsBusy が回数ではなく時刻を期限にし、MainActor を塞いだまま CPU を空回しせずに開始を待つ
- [ ] #3 どちらのテストも、守っている性質を壊す変更（skip でも倍率を当てる / 開始を MainActor で待つ）を入れると落ちることを確認している
<!-- AC:END -->
