---
id: TASK-622
title: CI の並列負荷で MainActor・協調プールの空きを待つテスト 2 件が間欠的に落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 16:17'
updated_date: '2026-09-13 16:22'
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
- [x] #1 倍率を当てないテストが非同期の描画の着地を待たずに前提を作る（待機ヘルパーを使わない）
- [x] #2 loadStartsWhileTheMainActorIsBusy が回数ではなく時刻を期限にし、MainActor を塞いだまま CPU を空回しせずに開始を待つ
- [x] #3 どちらのテストも、守っている性質を壊す変更（skip でも倍率を当てる / 開始を MainActor で待つ）を入れると落ちることを確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ZoomProjection の skip テスト: 1 度目の updateContent + waitUntilOnMainActor を、同じ入力に等しい RenderedStateMirror を recordRendered で確定させる形へ置き換える（ViewerRendererContentUpdateTests と同じ前例）
2. LoadStart: StartSignal を NSCondition にし、MainActor 上で wait(until:) により時刻期限で待つ（空ループをやめる）
3. 各テストで、性質を壊す変更（updateContent の plan != .skip ガード削除 / ViewerLoadStarter.start を MainActor 継承に）を一時的に入れて落ちることを確認し、戻す
4. swift test（全体）と swiftformat / swiftlint 差分を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
根本原因: 2 件ともテスト側がキューの空き待ちに予算を置いていた。倍率のテストは描画済み状態を実描画の着地（Task { @MainActor } → withBlockingWork → MainActor 再開）で作っており、~1900 件の @MainActor テストで混んだメインキューの後ろへ回されて 60 秒の予算を超えた。CI ログの Swift Testing の完了時刻を並べると、1 実行の中で 10〜24 秒どのテストも完了しない区間が複数あった（PR #665 attempt 3 / main run 34766362231）。LoadStart は協調プールで走る開始を 20 万回の空ループ（数 ms）で待っていた。
単純化の検討: 予算を延ばす方向は採らない（このテストは過去に markdown→mmd への変更と 30 秒への延長を経ても落ちている）。待ち自体を無くす / 時刻で待つ。
検証: (1) swift test --filter 対象 2 suite 通過 (2) 性質を壊す変更（updateContent の plan != .skip ガード削除 / ViewerLoadStarter.start を @MainActor 化）を一時的に入れると、倍率のテストは applied 0.5 == 1.0 で、LoadStart は期限切れで落ちることを確認して戻した (3) swift test 全体 2053 件通過 (4) swiftlint main との差分ゼロ（48→48）。
native-app-design.md: テストだけの変更で仕様は変わらないため更新不要。
範囲外: 同じ再実行で DistributedAckWaiterIntegrationTests / CLIRequestWireIntegrationTests も 1 回落ちた（プロセス間通知の配送待ち）。再発するなら別タスクで扱う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI の並列負荷で間欠的に落ちていた 2 テストを、キューの空きを待たない形へ直した。ViewerRendererZoomProjectionTests の skip テストは描画済みミラーを recordRendered で直接確定させて非同期の待機を無くし、loadStartsWhileTheMainActorIsBusy は空ループの回数予算を NSCondition による時刻期限の待機へ変えた。性質を壊す変更で両テストが落ちること、swift test 全体 2053 件の通過、swiftlint の main 差分ゼロを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
