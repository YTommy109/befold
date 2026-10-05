---
id: TASK-663
title: >-
  swift test --no-parallel で GitStatusBranchDiffIntegrationTests が signal 5
  で落ち、テストに実行順の依存がある
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 04:30'
updated_date: '2026-09-29 07:53'
labels: []
dependencies: []
priority: medium
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-29 の速度計測（TASK-662）で見つかった。

- `swift test --no-parallel` を回すと、`GitStatusBranchDiffIntegrationTests` の最初のテスト「base ブランチからのコミット済み変更に branchModified が付く」の開始直後に、テストプロセスが `exited with unexpected signal code 5`（trap）で落ちる。直前に走っていたのは `GitStatusBadgeTests`
- 同じスイートを単独で回すと、直列でも並列でも 4 件とも緑（`--filter GitStatusBranchDiffIntegrationTests`、`--no-parallel` 付きでも 0.5 秒で pass）
- 通常の並列実行では落ちていない

つまり、先に走った何か（直列順で前にある全スイートのどれか）が残した状態に依存して trap している。並列実行では順序が変わるため隠れているだけで、TASK-662 の並列化・MainActor 解除の作業で順序が変わると表面化しうる。1 回の再現なので flaky かどうかは未確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 --no-parallel の全体実行で再現するかを複数回測り、再現条件（先行するスイート）を特定している
- [x] #2 trap の原因が直っている（検知を緩める・スイートを skip する形ではなく）
- [x] #3 --no-parallel の全体実行が緑になる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. --no-parallel 全体実行を HEAD と起票時ツリー（26fd76cb）で複数回測る
2. 再現した trap のクラッシュレポート（DiagnosticReports）から落ちた箇所を特定する
3. 検知を緩めず原因側を直し、修正を戻すと落ちる回帰テストを付ける
4. --no-parallel 全体実行が緑になることを確かめる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（2026-09-29）
- `--no-parallel` 全体実行: HEAD（6a81daaa）で 3 回、起票時ツリー（26fd76cb を .tmp へ git archive）で 2 回、いずれも緑。起票時の 1 回は再現しなかった
- TASK-662.6 の作業中、`--filter 'SidebarChangedFilesOnlyIntegrationTests|GitStatusReaderIntegrationTests'` で signal 5 が 4 回中 2 回出た。~/Library/Logs/DiagnosticReports の swiftpm-testing-helper-*.ips（2 件）はどちらも同じスタックだった: `BUG IN CLIENT OF LIBDISPATCH: dispatch_sync called on queue already owned by current thread` / `FileWatcher.stop()`（queue.sync）← `FileWatcher.deinit` ← block_destroy_helper ← 監視キューの drain
- 起票時のクラッシュレポートは残っておらず（Retired 側も 09-28 の無関係な 2 件のみ）、同じ trap だったとは断定できない。同じ signal 5 で、git / 監視を使うスイートの近くで落ちた点は一致する

## 原因
`FileWatcher.init` の `queue.async { self.startMonitorsAndCatchUp() }` が self を強参照で持つ。そのブロックが走り終わる前に持ち主が手放すと、最後の解放はブロックの破棄（監視キュー上）になり、deinit → stop() → `queue.sync` が自分の持つキューへの dispatch_sync になって trap する。`stop()` の doc は「deinit は監視キュー上から呼ばれない」を前提にしていたが、この強参照で破れていた。**先行するスイートの種類ではなく、作ってすぐ手放される FileWatcher があるかどうかとタイミングで決まる。** 本番でも、窓やサイドバーが監視を張ってすぐ閉じると同じ形で落ちうる

## 修正
deinit では stop() を呼ばず、直列化せずに片付ける（stopFileMonitor / stopDirectoryMonitor / debouncer.cancel）。deinit に入った時点で self を持つ者は他に居らず、ハンドラは weak で空振りするため直列化は要らない。ブロック側を weak にする案は採らなかった: ハンドラの `guard let self` が一時的に持つ強参照でも、最後の解放は監視キュー上に来うるため
- 回帰テスト `FileWatcherReleaseOnWatcherQueueTests`: 作ってすぐ手放した FileWatcher 20 個が解放されるまで待つ。修正を戻すと 3 回中 3 回 signal 5、修正ありで 3 回中 3 回緑
- 修正後、上の filter 実行が 5 回連続緑。`--no-parallel` 全体実行が 2 回連続緑（2005 件、47.8 秒 / 47.5 秒）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`--no-parallel` での signal 5 はクラッシュレポートから FileWatcher.deinit の queue.sync（監視キュー上での自己 dispatch_sync）と特定した。init の queue.async が self を強参照で持つため、作ってすぐ手放すと最後の解放が監視キュー上になる。deinit を直列化しない片付けに変え、修正を戻すと 3/3 で落ちる回帰テストを追加した。直列の全体実行は 2 回緑。起票時の 1 回とは同じレポートで突き合わせられていない（Notes）。
<!-- SECTION:FINAL_SUMMARY:END -->
