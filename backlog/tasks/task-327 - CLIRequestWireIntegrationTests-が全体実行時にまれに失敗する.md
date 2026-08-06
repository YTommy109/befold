---
id: TASK-327
title: CLIRequestWireIntegrationTests が全体実行時にまれに失敗する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 17:07'
updated_date: '2026-08-06 02:57'
labels:
  - test
  - flaky
dependencies: []
priority: medium
type: bug
ordinal: 508000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-319 の作業中に遭遇。`swift test` の全体実行で「全オプション付きの要求が実際の Distributed Notification を通って復元できる」（CLIRequestWireIntegrationTests.swift:53 / :65）がまれに失敗する。単独実行（--filter）では常に通る。

実測（2026-08-06、同一マシン）:
- 現ブランチ HEAD で全体実行: 失敗する回と通る回がある（連続 3 回では 3/3 通過、その前は 2 回連続で失敗）
- 失敗時のメッセージ: `waitUntilWithRetry` のタイムアウトと `received.get() → nil`
- origin/main の全体実行では失敗を再現できていない（1 回のみ実施）

当初は同セッションの ViewerStore.openFile の変更が原因かと考え、その行を消すと通ったため因果があるように見えたが、その後同一ツリーで 3 回連続通過したため**偶然の一致**と判断した。実際にはテスト自体が Distributed Notification の配送タイミングに依存しており、並列実行時の負荷で待ち時間を超えていると見られる。

調査の方向: 待機の上限（waitUntilWithRetry のリトライ回数・間隔）が負荷時に不足していないか、Distributed Notification を使う統合テストを直列化（.serialized）すべきか、通知配送がメインランループのターンを要求する点をテスト側でどう担保するか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全体実行を 10 回繰り返しても当該テストが失敗しない
- [x] #2 失敗が負荷・並列度のどちらに起因するかが実測で示されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 全体実行を 10 回繰り返してベースラインの失敗率を実測する
2. 検知用プローブ(1 秒ごとの MainActor.run 到達時間)を仕込み、失敗が負荷か並列度かを実測で切り分ける
3. 実測に基づき、メインアクター/メインキューの一巡に依存しない形へテストを書き換える
4. 全体実行 10 回で失敗ゼロを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-06: 同種の不安定さを ViewerWindowControllerToolbarTests「行番号アイテムはコード表示中のみ有効」（ViewerWindowControllerToolbarTests.swift:98、`(codeButton.isEnabled → false) == true`）でも観測した。単独実行と再実行では通る。全体実行時の負荷・並列度に依存する点が CLIRequestWire と共通のため、調査は 2 件まとめて行うのがよい。

2026-08-06: 全体実行が**終わらない**（テストバイナリが 100% 超の CPU を 20 分以上回し続ける）事象も 2 回連続で観測した。`sample` で採取したスタックは、多数のワーカースレッドが `-[NSAnimation _runBlocking]` → `CFRunLoopRun` で待っている状態で、メインスレッドは `swift_task_asyncMainDrainQueue` → `CFRunLoopRun`。当該セッションの変更（GitDiffLoader）とは無関係な AppKit のウィンドウアニメーション待ちに見える。プロセスを kill して再実行すると 1150 tests が 18.7 秒で通過した。ハング時の sample は scratchpad に採取したが永続化していないため、次回再現時に `sample <pid>` を取り直して保存すること。

2026-08-06 実測（同一マシン、swift test の全体実行）:

ベースライン 10 回: 6 回失敗。内訳は CLIRequestWireIntegrationTests「全オプション付きの要求が…」4 回、ViewerWindowControllerToolbarTests「行番号アイテムはコード表示中のみ有効」3 回（同時失敗あり）。他の失敗は無し。

原因の切り分け（AC #2）: CLI 側のテストに「1 秒ごとに MainActor.run を投げて到達までの時間を測る」プローブを仕込み、全体実行 6 回で計測した。結果、成功した回でも到達まで 5.1〜8.3 秒、失敗した回は 15 秒の待機予算の間に一度も到達しなかった（samples=0）。つまり原因は Distributed Notification の配送遅延でも CLI ターゲットの負荷でもなく、**多数の @MainActor スイートが full suite 実行中ずっとメインアクターを占有していること**。並列度そのものではなく、メインアクターという単一資源の飽和が効いている。

修正:
- CLIRequestWireIntegrationTests: observer の queue を .main → nil にした（配送側スレッドで即実行。received は LockedBox なので任意スレッドから安全）。飽和したメインキューへ配送ブロックを積むのをやめた。既存の DistributedAckWaiter も queue: nil で、こちらは 26 回の全体実行で一度も失敗していない。
- ViewerWindowControllerToolbarTests: 壁時計予算 10 秒の waitUntilOnMainActor ポーリングをやめ、同ファイル内の modeToggleReflectsFileType と同じ既存パターン（await store.loadTask?.value → refreshToolbarState()）に揃えた。混雑は遅延になるだけで失敗にならず、上限はスイートの .timeLimit が担保する。

検証: CLI 側の修正のみで全体実行 10 回 → 当該テストの失敗 0（トグル側は 1 回失敗）。両方修正後に全体実行 10 回 → 当該 2 テストの失敗 0。

副産物: 検証中の 1 回（計 26 回中 1 回）で FileWatcherIntegrationTests の detectsRenameWithinSameDirectory / detectsMoveToAnotherDirectory が失敗した。本タスクの 2 件とは別の flaky なので別途起票する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
flaky の原因は Distributed Notification の配送遅延ではなく、full suite 実行中に多数の @MainActor スイートがメインアクターを飽和させ、メインアクターの一巡が 5〜8 秒（失敗時は 15 秒以上）かかることだった（1 秒ごとの MainActor.run 到達時間を計測して確認）。CLIRequestWireIntegrationTests は observer の queue を .main から nil にして配送をメインキューに依存させないようにし、ViewerWindowControllerToolbarTests は壁時計予算のポーリングを既存の await store.loadTask?.value パターンへ置き換えた。全体実行 10 回でベースライン 6 回失敗 → 修正後 0 回失敗。
<!-- SECTION:FINAL_SUMMARY:END -->
