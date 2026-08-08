---
id: TASK-335
title: FileWatcherIntegrationTests のリネーム検知が全体実行時にまれに失敗する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-06 02:56'
updated_date: '2026-08-06 04:09'
labels:
  - test
  - flaky
dependencies: []
priority: medium
type: bug
ordinal: 601000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-327 の検証中（全体実行 26 回）に 1 回だけ観測した。`swift test` の全体実行で FileWatcherIntegrationTests の detectsRenameWithinSameDirectory（FileWatcherIntegrationTests.swift:135-136）と detectsMoveToAnotherDirectory（同 :186-187）が同時に失敗した。いずれも renamed が nil のまま 15 秒の待機予算を使い切っている。

TASK-327 で確定した原因（full suite 実行中はメインアクターが飽和し、メインアクターの一巡に 5〜8 秒かかる）と同じ系統の可能性があるが、こちらは FileWatcher の DispatchSource コールバック経路であり未確認。まず待機がメインアクター/メインキューの一巡に依存しているかを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全体実行を 10 回繰り返しても当該 2 テストが失敗しない
- [x] #2 失敗の原因（メインアクター飽和か、DispatchSource のイベント取りこぼしか）が実測で示されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileWatcher の switchToNewPath に一時プローブ(監視キュー側で rename 判定成立、MainActor 側で onRename 配送、それぞれの時刻)を仕込む
2. 全体実行を繰り返し、待機予算を BEFOLD_TEST_TIMEOUT_SECONDS で絞って増幅し、失敗時にどちらのプローブまで到達しているかを実測する（メインアクター飽和 か DispatchSource 取りこぼし かの切り分け = AC #2）
3. 実測に基づき、メインアクターの一巡を壁時計予算に前提しない形へテストを書き換える
4. プローブを外し、全体実行 10 回で当該 2 テストの失敗ゼロを確認する（AC #1）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-06 実測（同一マシン、swift test）:

原因の切り分け（AC #2）: FileWatcher.switchToNewPath に一時プローブを仕込み、(1) 監視キュー上で rename 判定が成立した時刻と (2) `Task { @MainActor }` でホップしたコールバックが実際に走った時刻を記録して、全体実行 6 回を計測した。結果、(1) は毎回即座に成立しており、(2) までに 10.6〜11.7 秒かかっていた（6 回中 6 回）。DispatchSource のイベント取りこぼしではなく、**TASK-327 と同じメインアクター飽和**が原因。待機予算 15 秒に対して常時 11 秒前後を消費しているため、混雑が少し増えるだけで超過する（起票時の観測は 26 回中 1 回）。

増幅による再現: `BEFOLD_TEST_TIMEOUT_SECONDS=4` で待機予算を絞ると、全体実行 6 回すべてで当該 2 テストが失敗した（修正前ベースライン 6/6）。

単純化の検討: FileWatcher 側のコールバック契約から `@MainActor` を外す案を検討したが、本番の呼び出し元（ViewerStore / SidebarNavigator）はいずれも MainActor 状態を触るためホップが呼び出し側へ移るだけで、テスト都合で本番 API を変えることになる。採らなかった。

修正: 壁時計予算を持たないポーリング待機 `waitForMainActorDelivery`（BefoldTestSupport/Waiting.swift）を追加し、FileWatcherIntegrationTests の `@MainActor` 配送待ち（rename 通知・コールバック回数の増加）と `confirmWatcherArmed` の arm 観測をこれに置き換えた。上限はスイートの `.timeLimit` が担保する（TASK-327 で ViewerWindowControllerToolbarTests に適用したのと同じ方針＝混雑は遅延になるだけで失敗にはならない）。

検証: 増幅条件（予算 4 秒）での全体実行 6 回で、配送遅延は依然 6.5〜9.0 秒発生していたが失敗は 0（修正前 6/6 失敗）。本番条件（既定予算）での全体実行 10 回は 1160 tests すべてグリーン、失敗 0（AC #1）。swiftlint はベースライン差分ゼロ（FileWatcherIntegrationTests.swift:22 の large_tuple は HEAD にも存在する既存警告）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
flaky の原因は DispatchSource の取りこぼしではなく、full suite 実行中のメインアクター飽和だった。FileWatcher の rename 判定は監視キュー上で即座に成立しているのに、`Task { @MainActor }` で配送されるコールバックが走るまで 6 回中 6 回とも 10.6〜11.7 秒かかっており（待機予算は 15 秒）、混雑が少し増えるだけで超過していた。壁時計予算を持たない待機 `waitForMainActorDelivery` を追加し、当該スイートの `@MainActor` 配送待ちと `confirmWatcherArmed` の arm 観測を置き換えた（上限はスイートの .timeLimit が担保）。予算を 4 秒に絞った増幅条件で修正前 6/6 失敗 → 修正後 0/6 失敗、既定予算の全体実行 10 回で 1160 tests すべてグリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
