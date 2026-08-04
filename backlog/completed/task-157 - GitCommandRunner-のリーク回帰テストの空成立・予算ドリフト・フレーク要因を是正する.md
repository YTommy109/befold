---
id: TASK-157
title: GitCommandRunner のリーク回帰テストの空成立・予算ドリフト・フレーク要因を是正する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-26 00:48'
updated_date: '2026-07-26 01:19'
labels:
  - test
  - review
dependencies: []
priority: medium
ordinal: 232000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #303 (TASK-155) で追加したリーク回帰テスト 2 本(killsGrandchildHoldingStandardOutput / repeatedTimeoutsDoNotAccumulateResources)の構造的な弱点。コードレビューで CONFIRMED / PLAUSIBLE 判定。

1. 空成立: 両テストとも「孫プロセス(sleeper)が消えたこと」だけを検証し「存在したこと」を検証しないため、負荷の高い CI で git が 0.5 秒以内に alias シェルを fork できないと、terminate()-only の退行に対しても green のまま通る。ファイル内コメント自身が 0.2 秒でこの空成立が起きたことを記録している。タイムアウト発火前に processExists == true をポーリング確認するアレンジが必要。
2. 予算ドリフト: testTimeLimit(pollingBudgetFallback: 60) は内側の waitUntil に伝播せず、waitUntil は既定の 10 秒でタイムアウトする。Waiting.swift の doc が警告しているドリフトそのもの。20 本のリーダースレッド巻き取りが負荷下で 10 秒を超えると偽赤になる。
3. フレーク要因: baselineFDs/baselineThreads は並列実行中の単発ポイントサンプルなので、他テスト(readsOutputWhileGlobalQueueIsSaturated の ~64 GCD ワーカー等)でベースラインが膨らむと後続の実リークを隠す。逆に slack=10 は並列スイートの持続的ノイズが 10 を超え続けると偽赤になる。スイートの .serialized 化、またはベースラインの最小値サンプリング等で両方向を塞ぐ。
4. 実行時間: repeatedTimeoutsDoNotAccumulateResources は構造上 21 回 x 0.5 秒 = 10.5 秒以上の逐次ブロッキングを必ず消費し、TSan ジョブでは数倍に伸びる。rounds/slack の比率(現状 2 倍の検出マージン)を維持しつつ実行時間を圧縮する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 両テストが sleeper の spawn 成立を検証してから消滅を検証する(空成立しない)
- [x] #2 waitUntil のポーリング予算がテスト宣言の予算と一致している(ドリフトがない)
- [x] #3 fd/スレッド数の検証が並列実行ノイズで偽陰性・偽陽性のどちらにも倒れない設計になっている
- [x] #4 repeatedTimeoutsDoNotAccumulateResources の実測ウォールクロックが現行より短縮され、検出マージンの根拠がコメントで説明されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. スイートを .serialized 化し、同一スイート内の並列ノイズ(ワーカープール飽和テスト等)を排除する。
2. 資源カウンタを対象限定にする: fd は FIFO(pipe)のみ、スレッドは名前が GitCommandRunner.read のもののみを数える。他テストのノイズが原理的に混入しないため slack を小さくでき、偽陰性・偽陽性の両方向を塞ぐ。
3. ポーリング予算を単一の定数から .timeLimit と waitUntil の両方へ渡し、ドリフトを無くす。
4. 両テストとも sleeper の spawn 成立を processExists のポーリングで確認してから消滅を検証する(空成立しない)。git 実行は専用スレッドで走らせ、実行中に確認する。
5. repeatedTimeouts は 20 ラウンドを逐次でなく並行に回し、ウォールクロックを 1 ラウンド分へ圧縮する。ウォームアップは対象限定カウンタでは不要になるため削除する。
6. 書き込み端を握るプロセスを殺し切れない場合(孫が別セッションへ抜けた場合)でもスレッドと fd が返ることを固定するテストを追加する(TASK-156 のフォールバック経路の検証)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test --filter GitCommandRunnerTests で 10 tests green。repeatedTimeoutsDoNotAccumulateResources は 21.0 秒 → 2.28 秒。空成立の防止は #expect(await waitUntil { processExists(...) == true }) で spawn 成立を先に固定する形で担保。予算ドリフトは leakPollingBudget(30 秒)を .timeLimit と waitUntil の双方へ渡して解消。ノイズ耐性は openPipeCount(FIFO のみ)/readerThreadCount(スレッド名で絞る)+ @Suite(.serialized) で両方向を塞いだ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リーク回帰テストの 4 つの弱点を是正した。(1) 打ち切り前に sleeper の実在をポーリングで確認し空成立を防止。(2) ポーリング予算を単一定数 leakPollingBudget から .timeLimit と waitUntil の双方へ渡してドリフトを解消。(3) 数える対象を pipe の fd と GitCommandRunner.read という名前のスレッドに限定し、スイートを .serialized 化して並列ノイズによる偽陰性・偽陽性の両方を塞ぎ、許容幅を 10 から 3(検出マージン約 6.7 倍)へ絞れるようにした。(4) 20 ラウンドを並行実行にしてウォールクロックを 10.5 秒相当から 2.28 秒へ短縮。あわせて、書き込み端を握る孫を殺し切れない経路の回帰テストを追加した。
<!-- SECTION:FINAL_SUMMARY:END -->
